import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _scheduleItems = [];

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Live listener for student document to get enrolled sections
      FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .snapshots()
          .listen((studentDoc) async {
        if (!studentDoc.exists) return;

        final studentData = studentDoc.data();
        if (studentData == null) return;

        final sections = List<String>.from(studentData['sections'] ?? []);

        List<Map<String, dynamic>> allItems = [];

        // For each section, fetch the schedule.
        // Improvements: We could use a group query or listen to each section for real-time schedule updates.
        // For now, let's just fetch them whenever the student doc updates or on init.
        // To make schedule items real-time too, we would need a stream for each section.
        
        for (final sectionName in sections) {
          try {
             final sectionDoc = await FirebaseFirestore.instance.collection('sections').doc(sectionName).get();
             if (sectionDoc.exists && sectionDoc.data() != null) {
               final data = sectionDoc.data()!;
               if (data['schedule'] is List) {
                 final List<dynamic> schedList = data['schedule'];
                 for (final item in schedList) {
                   if (item is Map<String, dynamic>) {
                     allItems.add({
                       ...item,
                       'section': sectionName,
                     });
                   }
                 }
               }
             }
          } catch (e) {
            debugPrint('Error fetching schedule for section $sectionName: $e');
          }
        }

        if (mounted) {
          setState(() {
            _scheduleItems = allItems;
            _isLoading = false;
          });
        }
      });
      
    } catch (e) {
      debugPrint('Error loading schedule: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // Separate schedule by semester
    final firstSemSchedule = _scheduleItems.where((item) => (item['semester'] ?? 1) == 1).toList();
    final secondSemSchedule = _scheduleItems.where((item) => item['semester'] == 2).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  'Class Schedule',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: HexColor("#0F4C7F"),
                  ),
                ),
              ),
              TabBar(
                isScrollable: false,
                indicatorColor: HexColor("#0F4C7F"),
                labelColor: HexColor("#0F4C7F"),
                unselectedLabelColor: Colors.grey,
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
            _buildScheduleList(firstSemSchedule),
            _buildScheduleList(secondSemSchedule),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 64,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                'No classes scheduled for this semester',
                style: TextStyle(color: Colors.grey[500], fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSchedule,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildScheduleCard(
              item['time'] ?? 'TBA',
              item['subject'] ?? 'Unknown Subject',
              item['section'] ?? '',
              item['teacherName'] ?? 'TBA',
            ),
          );
        },
      ),
    );
  }

  Widget _buildScheduleCard(String time, String subject, String section, String teacher) {
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HexColor("#0F4C7F").withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.access_time,
              color: HexColor("#0F4C7F"),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[800],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                 Text(
                  '$section • $teacher',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
