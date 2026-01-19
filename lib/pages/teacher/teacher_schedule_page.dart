import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../widgets/guide_pointer.dart';

class TeacherSchedulePage extends StatefulWidget {
  final bool startScheduleTour;
  final Stream<List<DocumentSnapshot>>? sectionsStream;
  const TeacherSchedulePage({super.key, this.startScheduleTour = false, this.sectionsStream});

  @override
  State<TeacherSchedulePage> createState() => TeacherSchedulePageState();
}

class TeacherSchedulePageState extends State<TeacherSchedulePage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _mySchedule = [];
  bool _isDemoMode = false;
  final GlobalKey _titleKey = GlobalKey();
  final GlobalKey _firstCardKey = GlobalKey();

  StreamSubscription? _sectionsSub;

  @override
  void initState() {
    super.initState();
    if (widget.startScheduleTour) {
      _loadDemoSchedule();
    } else {
      _initSectionsListener();
    }
  }

  @override
  void dispose() {
    GuidePointer.dismiss();
    _sectionsSub?.cancel();
    super.dispose();
  }

  void _initSectionsListener() {
    if (widget.sectionsStream != null) {
      _sectionsSub = widget.sectionsStream!.listen((snapshots) {
        _processSections(snapshots);
      });
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      _sectionsSub = FirebaseFirestore.instance
          .collection('sections')
          .where(Filter.or(
            Filter('teacherUids', arrayContains: user.uid),
            Filter('adviserUid', isEqualTo: user.uid),
          ))
          .snapshots()
          .listen((snapshot) {
        _processSections(snapshot.docs);
      });
    }
  }

  void _processSections(List<DocumentSnapshot> snapshots) {
    if (!mounted || _isDemoMode) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    List<Map<String, dynamic>> allItems = [];
    for (var doc in snapshots) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data?['schedule'] is List) {
        final List<dynamic> schedList = data!['schedule'];
        final isAdviser = data['adviserUid'] == user.uid;
        
        for (final item in schedList) {
          if (item is Map<String, dynamic>) {
            final itemTeacherUid = item['teacherUid']?.toString() ?? '';
            final isMySubject = itemTeacherUid == user.uid;
            
            if (isMySubject || isAdviser) {
              allItems.add({
                ...item,
                'section': doc.id,
                'isMySubject': isMySubject,
                'isAdviser': isAdviser,
              });
            }
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _mySchedule = allItems;
        _isLoading = false;
      });
    }
  }

  void _loadDemoSchedule() {
    // ... (rest of the demo schedule logic remains same)
    // Demo schedule data for tour
    setState(() {
      _isDemoMode = true;
      _mySchedule = [
        {'section': 'Grade 10 - A', 'subject': 'Math', 'day': 'Monday', 'time': '8:00 AM - 9:00 AM', 'semester': 1},
        {'section': 'Grade 10 - A', 'subject': 'Math', 'day': 'Wednesday', 'time': '8:00 AM - 9:00 AM', 'semester': 1},
        {'section': 'Grade 10 - A', 'subject': 'Science', 'day': 'Tuesday', 'time': '10:00 AM - 11:00 AM', 'semester': 1},
        {'section': 'Grade 10 - A', 'subject': 'Science', 'day': 'Thursday', 'time': '10:00 AM - 11:00 AM', 'semester': 1},
        {'section': 'Grade 10 - B', 'subject': 'Math', 'day': 'Monday', 'time': '2:00 PM - 3:00 PM', 'semester': 1},
        {'section': 'Grade 10 - B', 'subject': 'Math', 'day': 'Friday', 'time': '9:00 AM - 10:00 AM', 'semester': 1},
        {'section': 'Grade 11 - STEM', 'subject': 'Physics', 'day': 'Friday', 'time': '1:00 PM - 3:00 PM', 'semester': 2},
      ];
      _isLoading = false;
    });
  }

  // Public method to trigger schedule tour with demo data
  void startScheduleTour() {
    _loadDemoSchedule();
    
    // Slight delay to allow UI to rebuild with demo data before showing guide
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GuidePointer.show(
        context,
        steps: [
          GuideStep(
            targetKey: _firstCardKey,
            title: "Class Details",
            content: "Each card shows the subject name, assigned section, and specific day/time slots for that class.",
          ),
          GuideStep(
            targetKey: _firstCardKey,
            title: "Schedules & Management",
            content: "Schedules are tracked per semester. Tip: These are managed by Section Advisers. If any info is incorrect, please contact the adviser of that section.",
            buttonLabel: "Finish Tour",
          ),
        ],
        onComplete: () {},
      );
    });
  }

  void resetTour() {
    if (mounted) {
      setState(() {
        _isDemoMode = false;
        _isLoading = true;
      });
      _initSectionsListener();
    }
  }
  // Group entries by subject+section
  Map<String, List<Map<String, dynamic>>> _groupSchedule() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var entry in _mySchedule) {
      final key = '${entry['subject']}|${entry['section']}';
      grouped.putIfAbsent(key, () => []).add(entry);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final groupedSchedule = _groupSchedule();

    return Container(
      color: Colors.grey[50],
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Teaching Schedule',
                key: _titleKey,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: HexColor("#116754"),
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
              
              if (groupedSchedule.isEmpty)
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
                ...groupedSchedule.entries.map((entry) {
                  final parts = entry.key.split('|');
                  final subject = parts[0];
                  final section = parts[1];
                  final timeSlots = entry.value;
                  
                  return Container(
                    key: entry.key == groupedSchedule.keys.first ? _firstCardKey : null,
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: HexColor("#116754").withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.book, color: HexColor("#116754")),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subject,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                                Text(
                                  'Section: $section • Sem ${timeSlots.first['semester']}',
                                  style: TextStyle(
                                    fontSize: 14,
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
                                      '${slot['day']} ${slot['time']}',
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
                }),
            ],
          ),
        ),
      ),
    );
  }
}
