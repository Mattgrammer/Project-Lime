import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Deletes a user's account and all associated data
///
/// For Teachers (Advisers):
/// - Deletes all sections owned by the teacher (including students, schedules, requests)
/// - Removes students from those sections
/// - Deletes section documents from Firestore
/// - Deletes teacher document from Firestore
///
/// For Students:
/// - Removes student from all enrolled sections
/// - Removes pending requests from teacher inboxes
/// - Deletes student document from Firestore
///
/// For all users:
/// - Deletes Firebase Auth account
Future<void> deleteUserAccount(String password) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    debugPrint('No user logged in to delete');
    return;
  }

  final firestore = FirebaseFirestore.instance;
  final uid = user.uid;

  try {
    // 0. Re-authenticate user before deletion (required by Firebase for sensitive ops)
    if (user.email != null) {
      debugPrint('🔄 STEP 0: Attempting re-authentication for user: $uid');
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      
      try {
        // Try re-auth with broad timeout
        await user.reauthenticateWithCredential(credential).timeout(const Duration(seconds: 60));
        debugPrint('✅ STEP 0: Successfully re-authenticated user (Method A)');
      } catch (e) {
        debugPrint('⚠️ STEP 0 WARNING: Re-auth failed/timed out ($e). Trying Sign-In fallback...');
        // Fallback: Sign in explicitly (refreshes the user session same as reauth)
        await FirebaseAuth.instance.signInWithCredential(credential).timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            debugPrint('❌ STEP 0 FAILED: Both Auth methods timed out');
            throw Exception('Connection unstable. Please switching networks or try again.');
          },
        );
        debugPrint('✅ STEP 0: Successfully re-authenticated user (Method B)');
      }
    } else {
      debugPrint('⚠️ STEP 0 SKIPPED: User email is null');
    }

    // 1. Check if user is a teacher
    debugPrint('🔄 STEP 1: Checking if user is a teacher...');
    final teacherDoc = await firestore.collection('teachers').doc(uid).get().timeout(const Duration(seconds: 10));
    final isTeacher = teacherDoc.exists;
    debugPrint('✅ STEP 1: User is ${isTeacher ? '' : 'NOT '}a teacher');

    if (isTeacher) {
      final data = teacherDoc.data();
      if (data == null) {
        throw Exception('Teacher profile data missing');
      }
      
      final ownedSections = List<String>.from(data['ownedSections'] ?? data['sections'] ?? []);
      final allSections = List<String>.from(data['sections'] ?? []);
      
      debugPrint('🔄 STEP 2 (Teacher): Cleaning up sections and grades for: $allSections');

      for (var sectionName in allSections) {
         try {
            final isOwner = ownedSections.contains(sectionName);
            final sectionDoc = await firestore.collection('sections').doc(sectionName).get().timeout(const Duration(seconds: 5));
            if (!sectionDoc.exists) continue;
            
            final sectionData = sectionDoc.data() ?? {};
            final schedule = List<dynamic>.from(sectionData['schedule'] ?? []);
            
            List<String> subjectsToPurge;
            
            if (isOwner) {
              // If adviser owns the section, purge ALL subjects from the section (entire section being deleted)
              subjectsToPurge = schedule
                  .map((s) => s['subject'] as String?)
                  .where((s) => s != null)
                  .cast<String>()
                  .toSet()
                  .toList();
            } else {
              // If just a subject teacher, only purge subjects they taught
              subjectsToPurge = schedule
                  .where((s) => s['teacherUid'] == uid)
                  .map((s) => s['subject'] as String)
                  .toSet()
                  .toList();
            }

            debugPrint('  - Cleaning up $sectionName (Owner:$isOwner, Purging ALL subjects: $subjectsToPurge)');

            // 1. Scrub grades from students
            await _cleanupStudentRecords(firestore, sectionName, subjects: subjectsToPurge, removeSection: isOwner);

            if (isOwner) {
               // 2. Full cleanup for owned sections
               await Future.wait([
                 _removeSectionFromTeachers(firestore, sectionName, uid),
                 _deleteSectionDoc(firestore, sectionName)
               ]);
            } else {
               // 3. Just remove schedule entries for non-owned sections
               final updatedSchedule = schedule.where((s) => s['teacherUid'] != uid).toList();
               
               // Recalculate teacherUids from the updated schedule
               final updatedTeacherUids = updatedSchedule
                   .map((s) => s['teacherUid'] as String?)
                   .where((id) => id != null)
                   .toSet()
                   .toList();
               
               await firestore.collection('sections').doc(sectionName).update({
                 'schedule': updatedSchedule,
                 'teacherUids': updatedTeacherUids,
               }).timeout(const Duration(seconds: 5));
            }
         } catch (e) {
            debugPrint('    ⚠️ Error cleaning up section $sectionName: $e');
         }
      }
      
      debugPrint('🔄 STEP 4 (Teacher): Deleting inbox and profile...');
      await Future.wait([
        _deleteCollection(firestore.collection('teachers').doc(uid).collection('inbox')),
        firestore.collection('teachers').doc(uid).delete().timeout(const Duration(seconds: 10))
      ]);
      
    } else {
      // User is a student
      debugPrint('🔄 STEP 2 (Student): Loading student profile...');
      final studentDoc = await firestore.collection('students').doc(uid).get().timeout(const Duration(seconds: 10));
      
      if (studentDoc.exists) {
        final studentData = studentDoc.data();
        final studentSections = List<String>.from(studentData?['sections'] ?? []);
        debugPrint('🔄 STEP 3 (Student): Cleaning up enrollments: $studentSections');
        
        // 1. Parallelize removal from sections
        await Future.wait(studentSections.map((sectionName) async {
           try {
             await Future.wait([
               firestore.collection('sections').doc(sectionName).collection('students').doc(uid).delete(),
               firestore.collection('sections').doc(sectionName).update({
                  'students': FieldValue.arrayRemove([uid])
               })
             ]).timeout(const Duration(seconds: 5));
           } catch (e) {
             debugPrint('    ⚠️ Error removing from section $sectionName: $e');
           }
        }));
        
        // 2. Clean up any pending requests in teacher inboxes
        debugPrint('🔄 STEP 4 (Student): Cleaning up teacher inboxes...');
        final teachersSnapshot = await firestore.collection('teachers').get().timeout(const Duration(seconds: 15));
        
        await Future.wait(teachersSnapshot.docs.map((teacherDoc) async {
          final inboxQuery = await firestore
              .collection('teachers')
              .doc(teacherDoc.id)
              .collection('inbox')
              .where('studentUid', isEqualTo: uid)
              .get()
              .timeout(const Duration(seconds: 5));
          
          if (inboxQuery.docs.isNotEmpty) {
              final batch = firestore.batch();
              for (var doc in inboxQuery.docs) {
                batch.delete(doc.reference);
              }
              await batch.commit().timeout(const Duration(seconds: 5));
          }
        }));
        
        // 3. Delete student's inbox & profile in parallel
        debugPrint('🔄 STEP 5 (Student): Deleting student inbox and profile...');
        await Future.wait([
           _deleteCollection(firestore.collection('students').doc(uid).collection('inbox')),
           firestore.collection('students').doc(uid).delete().timeout(const Duration(seconds: 10))
        ]);
      }
    }

    // Final Auth deletion
    debugPrint('🔄 FINAL STEP: Deleting Auth account...');
    await user.delete().timeout(const Duration(seconds: 15));
    debugPrint('✅ SUCCESS: Account deleted permanently');

  } catch (e) {
    debugPrint('❌ FATAL ERROR: $e');
    final errorStr = e.toString().toLowerCase();
    if (errorStr.contains('requires-recent-login')) {
       throw Exception('Security timeout. Please logout and login again.');
    }
    rethrow;
  }
}

// Helper to remove section from all students who have it and scrub specific grades
Future<void> _cleanupStudentRecords(FirebaseFirestore firestore, String sectionName, {List<String>? subjects, bool removeSection = false}) async {
  final studentsWithSection = await firestore
      .collection('students')
      .where('sections', arrayContains: sectionName)
      .get()
      .timeout(const Duration(seconds: 10));
  
  if (studentsWithSection.docs.isEmpty) return;

  final batch = firestore.batch();
  for (var doc in studentsWithSection.docs) {
    Map<String, dynamic> updates = {};
    
    if (removeSection) {
      updates['sections'] = FieldValue.arrayRemove([sectionName]);
    }
    
    if (subjects != null && subjects.isNotEmpty) {
      for (var subject in subjects) {
        updates['grades.$subject'] = FieldValue.delete();
      }
    }
    
    if (updates.isNotEmpty) {
      batch.update(doc.reference, updates);
    }
  }
  await batch.commit().timeout(const Duration(seconds: 5));
}

// Helper to remove section from other teachers
Future<void> _removeSectionFromTeachers(FirebaseFirestore firestore, String sectionName, String ownerUid) async {
  final teachersWithSection = await firestore
      .collection('teachers')
      .where('sections', arrayContains: sectionName)
      .get()
      .timeout(const Duration(seconds: 10));
  
  if (teachersWithSection.docs.isEmpty) return;

  final batch = firestore.batch();
  var count = 0;
  
  for (var doc in teachersWithSection.docs) {
    if (doc.id == ownerUid) continue; // Skip owner, will be deleted anyway
    batch.update(doc.reference, {
      'sections': FieldValue.arrayRemove([sectionName]),
      'ownedSections': FieldValue.arrayRemove([sectionName]),
    });
    count++;
  }
  
  if (count > 0) {
    await batch.commit().timeout(const Duration(seconds: 5));
  }
}

// Helper to delete section doc and its subcollections
Future<void> _deleteSectionDoc(FirebaseFirestore firestore, String sectionName) async {
  // Delete subcollections first
  await _deleteCollection(firestore.collection('sections').doc(sectionName).collection('students'));
  // Then delete the doc
  await firestore.collection('sections').doc(sectionName).delete().timeout(const Duration(seconds: 10));
}

// Helper to delete a collection
Future<void> _deleteCollection(CollectionReference collection) async {
  final snapshot = await collection.get().timeout(const Duration(seconds: 5));
  if (snapshot.docs.isEmpty) return;
  
  final batch = collection.firestore.batch();
  for (var doc in snapshot.docs) {
    batch.delete(doc.reference);
  }
  await batch.commit().timeout(const Duration(seconds: 5));
}
