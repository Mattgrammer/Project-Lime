import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TeacherSchedulePage extends StatefulWidget {
  const TeacherSchedulePage({super.key});

  @override
  State<TeacherSchedulePage> createState() => _TeacherSchedulePageState();
}

class _TeacherSchedulePageState extends State<TeacherSchedulePage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _mySchedule = [];

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      
      // 1. Get sections where this teacher is assigned
      final teacherDoc = await firestore.collection('teachers').doc(user.uid).get();
      final List<String> sections = List<String>.from(teacherDoc.data()?['sections'] ?? []);
      
      List<Map<String, dynamic>> scheduleEntries = [];

      // 2. For each section, find subjects assigned to this teacher
      for (var sectionName in sections) {
        final sectionDoc = await firestore.collection('sections').doc(sectionName).get();
        if (sectionDoc.exists) {
          final schedule = sectionDoc.data()?['schedule'] as List<dynamic>?;
          if (schedule != null) {
            for (var item in schedule) {
              if (item is Map<String, dynamic> && item['teacherUid'] == user.uid) {
                scheduleEntries.add({
                  'section': sectionName,
                  'subject': item['subject'],
                  'time': item['time'],
                });
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _mySchedule = scheduleEntries;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading teacher schedule: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Teaching Schedule',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: HexColor("#0F4C7F"),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your weekly teaching schedule',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            
            if (_mySchedule.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No subjects assigned yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _mySchedule.length,
                itemBuilder: (context, index) {
                  final entry = _mySchedule[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: HexColor("#0F4C7F").withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.book, color: HexColor("#0F4C7F")),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry['subject'] ?? 'Unknown Subject',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Section: ${entry['section']}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                'Time: ${entry['time']}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: HexColor("#0F4C7F"),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

