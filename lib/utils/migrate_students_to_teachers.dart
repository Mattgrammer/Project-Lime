import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Scans the `students` collection for documents that appear to be teachers
/// (have `userType == 'Teacher'` or have a `teacherType` field) and moves
/// them into the `teachers` collection (copy then delete).
///
/// This runs client-side and should be considered a convenience/migration
/// helper for small datasets. For large datasets use a server-side script
/// with proper admin credentials.
Future<void> migrateStudentsToTeachers() async {
  final firestore = FirebaseFirestore.instance;
  debugPrint('Migration: scanning students for teacher records...');

  try {
    final snapshot = await firestore.collection('students').get();
    int moved = 0;

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final userType = data['userType'] as String?;
      final teacherType = data['teacherType'];

      final looksLikeTeacher = (userType != null && userType == 'Teacher') || (teacherType != null);
      if (!looksLikeTeacher) continue;

      final targetRef = firestore.collection('teachers').doc(doc.id);

      // Copy data into teachers collection, preserving fields and adding createdAt if missing
      final Map<String, dynamic> copy = Map<String, dynamic>.from(data);
      if (copy['createdAt'] == null) {
        copy['createdAt'] = FieldValue.serverTimestamp();
      }

      // Merge so we don't accidentally delete other data in target
      await targetRef.set(copy, SetOptions(merge: true));

      // Delete original student doc
      await firestore.collection('students').doc(doc.id).delete();
      moved++;
      debugPrint('Migration: moved student ${doc.id} -> teachers');
    }

    debugPrint('Migration complete. Documents moved: $moved');
  } catch (e) {
    debugPrint('Migration error: $e');
  }
}
