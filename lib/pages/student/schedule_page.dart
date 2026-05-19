import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class SchedulePage extends StatefulWidget {
  final Stream<QuerySnapshot>? sectionsStream;
  final int? initialTabIndex;
  const SchedulePage({super.key, this.sectionsStream, this.initialTabIndex});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  bool _isLoading = true;
  bool _showDemoSections = false;
  List<Map<String, dynamic>> _scheduleItems = [];

  StreamSubscription? _sectionsSub;

  @override
  void initState() {
    super.initState();
    _loadDemoSectionsFlag();
    _initListener();
  }

  @override
  void dispose() {
    _sectionsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDemoSectionsFlag() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showDemoSections = prefs.getBool('show_demo_sections') ?? false;
      });
    }
  }

  void _initListener() {
    if (widget.sectionsStream != null) {
      _sectionsSub = widget.sectionsStream!.listen((snapshot) {
        _processSchedule(snapshot);
      });
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      _sectionsSub = FirebaseFirestore.instance
          .collection('sections')
          .where('studentUids', arrayContains: user.uid)
          .snapshots()
          .listen((snapshot) {
        _processSchedule(snapshot);
      });
    }
  }

  void _processSchedule(QuerySnapshot snapshot) {
    if (!mounted) return;
    List<Map<String, dynamic>> allItems = [];

    for (var doc in snapshot.docs) {
      final sectionName = doc.id;

      // Skip demo sections unless explicitly showing them
      if ((sectionName.contains('[TUTORIAL]') || sectionName.contains('Demo Section')) && !_showDemoSections) {
        continue;
      }

      final data = doc.data() as Map<String, dynamic>?;
      if (data?['schedule'] is List) {
        final List<dynamic> schedList = data!['schedule'];
        for (final item in schedList) {
          if (item is Map<String, dynamic>) {
            allItems.add({
              ...item,
              'section': doc.id,
            });
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _scheduleItems = allItems;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSchedule() async {
    // Stream handles updates
  }

  // Group entries by subject+section+semester
  Map<String, List<Map<String, dynamic>>> _groupSchedule(List<Map<String, dynamic>> items) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var entry in items) {
      final key = '${entry['subject']}|${entry['section']}|${entry['teacherName']}';
      grouped.putIfAbsent(key, () => []).add(entry);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // Separate schedule by semester
    final firstSemSchedule = _scheduleItems.where((item) => (item['semester'] ?? 1) == 1).toList();
    final secondSemSchedule = _scheduleItems.where((item) => item['semester'] == 2).toList();

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex ?? 0,
      child: Column(
        children: [
          PreferredSize(
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
                      color: HexColor("#116754"),
                    ),
                  ),
                ),
                TabBar(
                  isScrollable: false,
                  indicatorColor: HexColor("#116754"),
                  labelColor: HexColor("#116754"),
                  unselectedLabelColor: Colors.grey,
                  tabs: const [
                    Tab(text: '1st Semester'),
                    Tab(text: '2nd Semester'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildScheduleList(firstSemSchedule),
                _buildScheduleList(secondSemSchedule),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleList(List<Map<String, dynamic>> items) {
    final grouped = _groupSchedule(items);
    
    if (grouped.isEmpty) {
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
                style: TextStyle(color: Colors.grey[700], fontSize: 18, fontWeight: FontWeight.w800),
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
        itemCount: grouped.length,
        itemBuilder: (context, index) {
          final entry = grouped.entries.elementAt(index);
          final parts = entry.key.split('|');
          final subject = parts[0];
          final section = parts[1];
          final teacher = parts.length > 2 ? parts[2] : 'TBA';
          final timeSlots = entry.value;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildScheduleCard(subject, section, teacher, timeSlots),
          );
        },
      ),
    );
  }

  Widget _buildScheduleCard(String subject, String section, String teacher, List<Map<String, dynamic>> timeSlots) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HexColor("#116754").withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.book,
              color: HexColor("#116754"),
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
                  '$section • $teacher',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                ...timeSlots.map((slot) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, size: 16, color: HexColor("#116754")),
                      const SizedBox(width: 6),
                      Text(
                        slot['time'] == 'TBA' ? 'TBA' : '${slot['day'] ?? ''} ${slot['time'] ?? 'TBA'}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: HexColor("#116754"),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
