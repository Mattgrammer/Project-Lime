import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:convert';

class SubjectsPage extends StatefulWidget {
  final Stream<QuerySnapshot>? sectionsStream;
  final QuerySnapshot? initialSectionsSnapshot;

  final int? initialTabIndex;
  const SubjectsPage({super.key, this.sectionsStream, this.initialSectionsSnapshot, this.initialTabIndex});

  @override
  State<SubjectsPage> createState() => _SubjectsPageState();
}

class _SubjectsPageState extends State<SubjectsPage> {
  bool _isLoading = true;
  List<Map<String, String>> _subjects = [];
  Map<String, Map<String, dynamic>> _teacherProfiles = {};

  StreamSubscription? _sectionsSub;
  StreamSubscription? _teachersSub;

  @override
  void initState() {
    super.initState();
    
    if (widget.initialSectionsSnapshot != null) {
      _processSections(widget.initialSectionsSnapshot!);
      _isLoading = false;
    }
    
    // Only start active listener if we don't have data yet OR if an external stream is provided
    if (widget.sectionsStream != null || widget.initialSectionsSnapshot == null) {
      _initListener();
    }

    // Safety timeout
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant SubjectsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh view if new data is passed from parent (Real-time sync)
    if (widget.initialSectionsSnapshot != oldWidget.initialSectionsSnapshot) {
      if (widget.initialSectionsSnapshot != null) {
        _processSections(widget.initialSectionsSnapshot!);
        _isLoading = false;
      }
    }
  }

  @override
  void dispose() {
    _sectionsSub?.cancel();
    _studentSub?.cancel();
    _teachersSub?.cancel();
    super.dispose();
  }

  // Track current section IDs to avoid unnecessary re-subscriptions
  List<String> _currentSectionIds = [];
  StreamSubscription? _studentSub;

  void _initListener() {
    if (widget.sectionsStream != null) {
      _sectionsSub = widget.sectionsStream!.listen((snapshot) {
        _processSections(snapshot);
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Listen to Profile to get Section IDs
    if (_subjects.isEmpty) {
      setState(() => _isLoading = true);
    }
    
    _studentSub = FirebaseFirestore.instance
        .collection('students')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      
      final data = doc.data();
      final sections = List<String>.from(data?['sections'] ?? []);
      _updateSectionsSubscription(sections);
    }, onError: (e) {
      debugPrint("Error listening to student profile: $e");
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _updateSectionsSubscription(List<String> newSectionIds) {
    // If lists are same, usually we return. BUT if we are still loading and list is empty,
    // we must clear the loading flag!
    if (_areListsEqual(_currentSectionIds, newSectionIds)) {
      if (_isLoading && newSectionIds.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }
    
    _currentSectionIds = newSectionIds;
    _sectionsSub?.cancel();

    if (newSectionIds.isEmpty) {
      if (mounted) {
        setState(() {
          _subjects = [];
          _isLoading = false;
        });
      }
      return;
    }

    // Filter out empty/null IDs just in case
    final idsToQuery = newSectionIds.where((id) => id.isNotEmpty).take(10).toList();
    
    if (idsToQuery.isEmpty) {
       if (mounted) setState(() => _isLoading = false);
       return;
    }

    _sectionsSub = FirebaseFirestore.instance
        .collection('sections')
        .where(FieldPath.documentId, whereIn: idsToQuery)
        .snapshots()
        .listen((snapshot) {
      _processSections(snapshot);
    }, onError: (e) {
      debugPrint('Error loading sections: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _listenToTeachers(List<String> uids) {
    if (uids.isEmpty) return;

    _teachersSub?.cancel();
    _teachersSub = FirebaseFirestore.instance
        .collection('teachers')
        .where(FieldPath.documentId, whereIn: uids)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final Map<String, Map<String, dynamic>> updatedProfiles = {};
      for (var doc in snapshot.docs) {
        updatedProfiles[doc.id] = doc.data();
      }
      setState(() {
        _teacherProfiles = updatedProfiles;
      });
    });
  }

  bool _areListsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _processSections(QuerySnapshot snapshot) {
    if (!mounted) return;
    final Map<String, Map<String, String>> groupedSubjects = {};

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data?['schedule'] != null) {
        final schedule = data!['schedule'] as List<dynamic>;
        for (var item in schedule) {
          if (item is Map<String, dynamic>) {
            final subject = item['subject'] as String? ?? '';
            final semester = (item['semester'] as int? ?? 1).toString();
            final key = "${subject}_$semester";
            
            final day = item['day'] as String? ?? '';
            final time = item['time'] as String? ?? '';
            final timeSlot = "$day $time";

            if (groupedSubjects.containsKey(key)) {
              final existingSchedule = groupedSubjects[key]!['schedule']!;
              if (!existingSchedule.contains(timeSlot)) {
                 groupedSubjects[key]!['schedule'] = "$existingSchedule\n$timeSlot";
              }
            } else {
              groupedSubjects[key] = {
                'subject': subject,
                'title': subject,
                'schedule': timeSlot,
                'teacher': item['teacherName'] as String? ?? '',
                'teacherUid': item['teacherUid'] as String? ?? '',
                'semester': semester,
              };
            }
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _subjects = groupedSubjects.values.toList();
        _isLoading = false;
        
        // Fetch teacher profiles
        final teacherUids = _subjects
            .map((s) => s['teacherUid'])
            .where((uid) => uid != null && uid.isNotEmpty)
            .cast<String>()
            .toSet()
            .toList();
        if (teacherUids.isNotEmpty) {
          _listenToTeachers(teacherUids);
        }
      });
    }
  }

  Future<void> _loadSubjects() async {
    // This is now handled by the stream, but keeping for RefreshIndicator
    // The stream will naturally stay up to date.
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final firstSem = _subjects.where((s) => s['semester'] == '1').toList();
    final secondSem = _subjects.where((s) => s['semester'] == '2').toList();

    return Container(
      color: Colors.grey[50],
      child: DefaultTabController(
        length: 2,
        initialIndex: widget.initialTabIndex ?? 0,
        child: Column(
          children: [
            PreferredSize(
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
                        color: HexColor("#116754"),
                      ),
                    ),
                  ),
                  TabBar(
                    indicatorColor: HexColor("#116754"),
                    labelColor: HexColor("#116754"),
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
            Expanded(
              child: TabBarView(
                children: [
                  _buildSubjectsList(firstSem),
                  _buildSubjectsList(secondSem),
                ],
              ),
            ),
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
              s['teacherUid'] ?? '',
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
      String teacherUid,
      ) {
    final teacherProfile = _teacherProfiles[teacherUid];
    final String? thumbnail = teacherProfile?['profileImageThumbnail'];
    final String? imageUrl = teacherProfile?['profileImageUrl'];
    final String displayTeacherName = teacherProfile?['name'] ?? teacher;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: HexColor("#116754").withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  subject,
                  style: TextStyle(
                    color: HexColor("#116754"),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              Icon(Icons.more_horiz, color: Colors.grey[300]),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule, size: 18, color: HexColor("#116754")),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  schedule,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.0),
                ),
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                  backgroundImage: thumbnail != null
                      ? MemoryImage(base64Decode(thumbnail))
                      : (imageUrl != null ? NetworkImage(imageUrl) : null) as ImageProvider?,
                  child: (thumbnail == null && imageUrl == null)
                      ? Icon(Icons.person_outline, size: 14, color: HexColor("#116754"))
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                displayTeacherName,
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
