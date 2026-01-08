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
      
      // Get owned sections (use ownedSections first, fall back to sections for backwards compatibility)
      final ownedSections = List<String>.from(data['ownedSections'] ?? data['sections'] ?? []);
      final allSections = List<String>.from(data['sections'] ?? []);
      
      debugPrint('🔄 STEP 2 (Teacher): Cleaning up owned sections: $ownedSections');
      
      // 1. For owned sections: delete section completely
      for (var sectionName in ownedSections) {
        try {
          debugPrint('  - Cleaning up section: $sectionName');
          // Remove section from all students
          final studentsWithSection = await firestore
              .collection('students')
              .where('sections', arrayContains: sectionName)
              .get()
              .timeout(const Duration(seconds: 10));
          
          final studentBatch = firestore.batch();
          for (var doc in studentsWithSection.docs) {
            studentBatch.update(doc.reference, {
              'sections': FieldValue.arrayRemove([sectionName])
            });
          }
          await studentBatch.commit().timeout(const Duration(seconds: 5));
          debugPrint('    - Removed section from ${studentsWithSection.docs.length} students');
          
          // Remove section from all other teachers
          final teachersWithSection = await firestore
              .collection('teachers')
              .where('sections', arrayContains: sectionName)
              .get()
              .timeout(const Duration(seconds: 10));
          
          final teacherBatch = firestore.batch();
          for (var doc in teachersWithSection.docs) {
            if (doc.id == uid) continue;
            teacherBatch.update(doc.reference, {
              'sections': FieldValue.arrayRemove([sectionName]),
              'ownedSections': FieldValue.arrayRemove([sectionName]),
            });
          }
          await teacherBatch.commit().timeout(const Duration(seconds: 5));
          
          // Delete section's students subcollection
          final sectionStudents = await firestore
              .collection('sections')
              .doc(sectionName)
              .collection('students')
              .get()
              .timeout(const Duration(seconds: 5));
          
          final subBatch = firestore.batch();
          for (var doc in sectionStudents.docs) {
            subBatch.delete(doc.reference);
          }
          await subBatch.commit().timeout(const Duration(seconds: 5));
          
          // Delete section document
          await firestore.collection('sections').doc(sectionName).delete().timeout(const Duration(seconds: 10));
          debugPrint('    - Successfully deleted section: $sectionName');
        } catch (e) {
          debugPrint('    ⚠️ Error cleaning up owned section $sectionName: $e');
        }
      }
      
      // 2. For non-owned sections (acting as subject teacher)
      final nonOwnedSections = allSections.where((s) => !ownedSections.contains(s)).toList();
      debugPrint('🔄 STEP 3 (Teacher): Cleaning up schedule references: $nonOwnedSections');
      for (var sectionName in nonOwnedSections) {
        try {
          final sectionDoc = await firestore.collection('sections').doc(sectionName).get().timeout(const Duration(seconds: 5));
          if (sectionDoc.exists) {
            final sectionData = sectionDoc.data();
            if (sectionData != null && sectionData['schedule'] != null) {
              final List<dynamic> schedule = sectionData['schedule'];
              final updatedSchedule = schedule.where((s) => s['teacherUid'] != uid).toList();
              
              if (updatedSchedule.length != schedule.length) {
                await firestore.collection('sections').doc(sectionName).update({
                  'schedule': updatedSchedule,
                }).timeout(const Duration(seconds: 5));
              }
            }
          }
        } catch (e) {
          debugPrint('    ⚠️ Error cleaning up schedule in $sectionName: $e');
        }
      }
      
      // 3. Delete teacher inbox
      debugPrint('🔄 STEP 4 (Teacher): Deleting inbox...');
      final inboxDocs = await firestore.collection('teachers').doc(uid).collection('inbox').get().timeout(const Duration(seconds: 10));
      final inboxBatch = firestore.batch();
      for (var doc in inboxDocs.docs) {
        inboxBatch.delete(doc.reference);
      }
      await inboxBatch.commit().timeout(const Duration(seconds: 5));

      // 4. Delete teacher document
      debugPrint('🔄 STEP 5 (Teacher): Deleting teacher profile...');
      await firestore.collection('teachers').doc(uid).delete().timeout(const Duration(seconds: 10));
      
    } else {
      // User is a student
      debugPrint('🔄 STEP 2 (Student): Loading student profile...');
      final studentDoc = await firestore.collection('students').doc(uid).get().timeout(const Duration(seconds: 10));
      
      if (studentDoc.exists) {
        final studentData = studentDoc.data();
        final studentSections = List<String>.from(studentData?['sections'] ?? []);
        debugPrint('🔄 STEP 3 (Student): Cleaning up enrollments: $studentSections');
        
        for (var sectionName in studentSections) {
          try {
            await firestore
                .collection('sections')
                .doc(sectionName)
                .collection('students')
                .doc(uid)
                .delete()
                .timeout(const Duration(seconds: 5));
            
            // Also update the section doc's students array
            await firestore.collection('sections').doc(sectionName).update({
              'students': FieldValue.arrayRemove([uid])
            }).timeout(const Duration(seconds: 5));
          } catch (e) {
            debugPrint('    ⚠️ Error removing from section $sectionName: $e');
          }
        }
        
        // 2. Clean up any pending requests in teacher inboxes
        debugPrint('🔄 STEP 4 (Student): Cleaning up teacher inboxes...');
        final teachersSnapshot = await firestore.collection('teachers').get().timeout(const Duration(seconds: 15));
        for (var teacherDoc in teachersSnapshot.docs) {
          final inboxQuery = await firestore
              .collection('teachers')
              .doc(teacherDoc.id)
              .collection('inbox')
              .where('studentUid', isEqualTo: uid)
              .get()
              .timeout(const Duration(seconds: 5));
          
          final batch = firestore.batch();
          for (var doc in inboxQuery.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit().timeout(const Duration(seconds: 5));
        }
        
        // 3. Delete student's own inbox
        debugPrint('🔄 STEP 5 (Student): Deleting student inbox...');
        final studentInboxDocs = await firestore
            .collection('students')
            .doc(uid)
            .collection('inbox')
            .get()
            .timeout(const Duration(seconds: 10));
        final inboxBatch = firestore.batch();
        for (var doc in studentInboxDocs.docs) {
          inboxBatch.delete(doc.reference);
        }
        await inboxBatch.commit().timeout(const Duration(seconds: 5));
      }
      
      // 4. Delete student document
      debugPrint('🔄 STEP 6 (Student): Deleting student profile...');
      await firestore.collection('students').doc(uid).delete().timeout(const Duration(seconds: 10));
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
