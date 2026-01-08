import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SubjectTeacherPage extends StatefulWidget {
  final String teacherUid;
  final String teacherName;

  const SubjectTeacherPage({super.key, required this.teacherUid, required this.teacherName});

  @override
  State<SubjectTeacherPage> createState() => _SubjectTeacherPageState();
}

class _SubjectTeacherPageState extends State<SubjectTeacherPage> {
  String? _teacherType;
  List<String> _sections = [];
  List<String> _ownedSections = [];
  final Map<String, List<Map<String, dynamic>>> _sectionStudents = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final firestore = FirebaseFirestore.instance;

    try {
      // 1. Fetch teacher metadata and sections from Firestore
      final teacherDoc = await firestore.collection('teachers').doc(widget.teacherUid).get();
      if (teacherDoc.exists) {
        final data = teacherDoc.data()!;
        _teacherType = data['teacherType'] as String?;
        _sections = List<String>.from(data['sections'] ?? []);
        _ownedSections = List<String>.from(data['ownedSections'] ?? []);
      }

      // 2. For each assigned section, fetch students assigned to it
      for (var section in _sections) {
        final studentsSnapshot = await firestore
            .collection('students')
            .where('sections', arrayContains: section)
            .get();
        
        final List<Map<String, dynamic>> students = [];
        for (var doc in studentsSnapshot.docs) {
          final sdata = doc.data();
          sdata['uid'] = doc.id;
          students.add(sdata);
        }
        _sectionStudents[section] = students;
      }
    } catch (e) {
      debugPrint('Error loading data from Firestore: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.teacherName),
        backgroundColor: HexColor('#0F4C7F'),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: HexColor('#0F4C7F').withValues(alpha: 0.1),
                            child: Icon(Icons.person, color: HexColor('#0F4C7F')),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.teacherName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text(_teacherType ?? 'Teacher', style: TextStyle(color: Colors.grey[700])),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Sections', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: HexColor('#0F4C7F'))),
                    const SizedBox(height: 12),
                    if (_sections.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('No sections found for this teacher.', style: TextStyle(color: Colors.grey[600])),
                      )
                    else
                      ..._sections.map((section) {
                        final isOwned = _ownedSections.contains(section);
                        final students = _sectionStudents[section] ?? [];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(section, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: (isOwned ? HexColor("#0F4C7F") : Colors.green).withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              isOwned ? 'Adviser' : 'Subject Teacher',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: isOwned ? HexColor("#0F4C7F") : Colors.green[700],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.arrow_forward_ios, size: 16, color: HexColor('#0F4C7F')),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (students.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Text('No assigned students', style: TextStyle(color: Colors.grey[600])),
                                )
                              else
                                ...students.map((stu) => Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.grey[200]!),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(child: Text(stu['name'] ?? 'Unnamed', style: const TextStyle(fontSize: 15))),
                                            Text(stu['studentId'] ?? '', style: TextStyle(color: Colors.grey[600])),
                                          ],
                                        ),
                                      ),
                                    )),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
    );
  }
}
