import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SubjectsPage extends StatefulWidget {
  const SubjectsPage({super.key});

  @override
  State<SubjectsPage> createState() => _SubjectsPageState();
}

class _SubjectsPageState extends State<SubjectsPage> {
  bool _isLoading = true;
  List<Map<String, String>> _subjects = [];

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      List<Map<String, String>> subjects = [];

      // Fetch enrolled sections from Firestore
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .get();

      if (studentDoc.exists && studentDoc.data()?['sections'] != null) {
        final sections = List<String>.from(studentDoc.data()!['sections']);

        // For each section, fetch the schedule
        for (final sectionName in sections) {
          try {
            final sectionDoc = await FirebaseFirestore.instance
                .collection('sections')
                .doc(sectionName)
                .get();

            if (sectionDoc.exists && sectionDoc.data()?['schedule'] != null) {
              final schedule = sectionDoc.data()!['schedule'] as List<dynamic>;

              for (var item in schedule) {
                if (item is Map<String, dynamic>) {
                  subjects.add({
                    'subject': item['subject'] as String? ?? '',
                    'title': item['subject'] as String? ?? '',
                    'schedule': item['time'] as String? ?? '',
                    'teacher': item['teacherName'] as String? ?? '',
                    'semester': (item['semester'] as int? ?? 1).toString(),
                  });
                }
              }
            }
          } catch (e) {
            debugPrint('Error loading schedule for section $sectionName: $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          _subjects = subjects;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading subjects: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final firstSem = _subjects.where((s) => s['semester'] == '1').toList();
    final secondSem = _subjects.where((s) => s['semester'] == '2').toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(115),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  'Subjects',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: HexColor("#0F4C7F"),
                  ),
                ),
              ),
              TabBar(
                indicatorColor: HexColor("#0F4C7F"),
                labelColor: HexColor("#0F4C7F"),
                unselectedLabelColor: Colors.grey,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: '1st Semester'),
                  Tab(text: '2nd Semester'),
                ],
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSubjectsList(firstSem),
            _buildSubjectsList(secondSem),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectsList(List<Map<String, String>> subjects) {
    if (subjects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                'No subjects enrolled for this semester',
                style: TextStyle(color: Colors.grey[500], fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSubjects,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: subjects.length,
        itemBuilder: (context, index) {
          final s = subjects[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildSubjectCard(
              s['subject'] ?? '',
              s['title'] ?? '',
              s['schedule'] ?? '',
              s['teacher'] ?? '',
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubjectCard(
      String subject,
      String title,
      String schedule,
      String teacher,
      ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: HexColor("#0F4C7F").withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  subject,
                  style: TextStyle(
                    color: HexColor("#0F4C7F"),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                schedule,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.person, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                teacher,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
