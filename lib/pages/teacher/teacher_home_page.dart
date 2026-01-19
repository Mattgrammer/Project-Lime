import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../../widgets/guide_pointer.dart';

class TeacherHomePage extends StatefulWidget {
  final Function(int index)? onNavigate;
  
  // Keys for external navigation items (Mobile/Nav Bar)
  final GlobalKey? scheduleKey;
  final GlobalKey? classesKey;
  final GlobalKey? inboxKey;
  final GlobalKey? profileKey;

  // Keys for external navigation items (Desktop/Sidebar)
  final GlobalKey? sidebarScheduleKey;
  final GlobalKey? sidebarClassesKey;
  final GlobalKey? sidebarInboxKey;
  final GlobalKey? sidebarProfileKey;
  final Stream<List<DocumentSnapshot>>? sectionsStream;
  
  final String? userName;
  final String? profileImageUrl;
  final String? profileImageThumbnail;
  final String? profileImagePath;
  final Stream<DocumentSnapshot>? userStream;

  const TeacherHomePage({
    super.key, 
    this.onNavigate, 
    this.scheduleKey,
    this.classesKey,
    this.inboxKey,
    this.profileKey,
    this.sidebarScheduleKey,
    this.sidebarClassesKey,
    this.sidebarInboxKey,
    this.sidebarProfileKey,
    this.sectionsStream,
    this.userName,
    this.profileImageUrl,
    this.profileImageThumbnail,
    this.profileImagePath,
    this.userStream,
  });

  @override
  State<TeacherHomePage> createState() => TeacherHomePageState();
}

class TeacherHomePageState extends State<TeacherHomePage> {
  StreamSubscription? _sectionsSub;
  StreamSubscription? _inboxSub;

  // State variables
  int _classesCount = 0;
  int _studentCount = 0;
  int _todayClassesCount = 0;
  List<Map<String, dynamic>> _todayClassesList = [];
  int _unreadMessages = 0;
  bool _isLoading = true;
  
  final GlobalKey _myClassesKey = GlobalKey();
  final GlobalKey _statsOverviewKey = GlobalKey();
  final GlobalKey _todayClassesKey = GlobalKey();
  final GlobalKey _totalStudentsKey = GlobalKey();
  final GlobalKey _inboxKey = GlobalKey();
  List<String> _sectionIds = [];

  @override
  void initState() {
    super.initState();
    _initListeners();
    
    // Safety timeout: If still loading after 3 seconds, force show the dashboard.
    // This prevents stuck spinners if streams are slow or unexpectedly empty.
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  void didUpdateWidget(TeacherHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sectionsStream != widget.sectionsStream || oldWidget.userStream != widget.userStream) {
      _initListeners();
    }
  }

  @override
  void dispose() {
    GuidePointer.dismiss();
    _sectionsSub?.cancel();
    _inboxSub?.cancel();
    super.dispose();
  }

  void _initListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Listen to Sections (Optimized via shared stream)
    if (widget.sectionsStream != null) {
      _sectionsSub = widget.sectionsStream!.listen((snapshot) {
        _processSections(snapshot, user.uid);
      });
    } else {
      _sectionsSub = FirebaseFirestore.instance
          .collection('sections')
          .where(Filter.or(
            Filter('teacherUids', arrayContains: user.uid),
            Filter('adviserUid', isEqualTo: user.uid),
          ))
          .snapshots()
          .listen((snapshot) {
        _processSections(snapshot.docs, user.uid);
      });
    }

    // 2. Real-time inbox count
    _inboxSub = FirebaseFirestore.instance
        .collection('teachers')
        .doc(user.uid)
        .collection('inbox')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
          if (mounted) setState(() => _unreadMessages = snap.docs.length);
        });
  }

  void _processSections(List<DocumentSnapshot> snapshots, String uid) {
    if (!mounted) return;
    
    int todayCount = 0;
    List<Map<String, dynamic>> todayList = [];
    final currentDay = _getDayName();
    int totalStudents = 0;

    for (var doc in snapshots) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      
      final studentUids = List.from(data['studentUids'] ?? []);
      totalStudents += studentUids.length;

      final schedule = data['schedule'] as List<dynamic>? ?? [];
      final isAdviser = data['adviserUid'] == uid;
      
      for (var item in schedule) {
        if (item is Map) {
          final itemDay = item['day']?.toString().trim() ?? '';
          if (itemDay.toLowerCase() == currentDay.toLowerCase()) {
            final itemTeacherUid = item['teacherUid']?.toString() ?? '';
            final isMySubject = itemTeacherUid == uid;
            
            if (isMySubject || isAdviser) {
              todayCount++;
              todayList.add({
                'subject': item['subject'] ?? 'Untitled',
                'time': item['time'] ?? 'TBA',
                'section': doc.id,
                'isMySubject': isMySubject,
                'isAdviser': isAdviser,
                'room': item['room'] ?? 'TBA',
              });
            }
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _sectionIds = snapshots.map((doc) => doc.id).toList();
        _classesCount = snapshots.length;
        _studentCount = totalStudents;
        _todayClassesCount = todayCount;
        _todayClassesList = todayList;
        _isLoading = false; // Data arrived, we can stop loading
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Please log in'));

    // If fully loaded or at least sections loaded:
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                  StreamBuilder<DocumentSnapshot>( 
                    stream: widget.userStream ?? FirebaseFirestore.instance.collection('teachers').doc(user.uid).snapshots(),
                    builder: (context, snapshot) {
                      final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                      final name = data['name'] as String? ?? widget.userName ?? 'Teacher';
                      final thumb = data['profileImageThumbnail'] ?? widget.profileImageThumbnail;
                      final url = data['profileImageUrl'] ?? widget.profileImageUrl;
                      final localPath = data['profileImagePath'] ?? widget.profileImagePath;

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Welcome back,',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: HexColor("#116754"),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: HexColor("#116754").withValues(alpha: 0.1), width: 2),
                            ),
                            child: CircleAvatar(
                              radius: 28,
                              backgroundColor: HexColor("#116754"),
                              backgroundImage: thumb != null
                                  ? MemoryImage(base64Decode(thumb))
                                  : (url != null 
                                      ? NetworkImage(url) 
                                      : (localPath != null && File(localPath).existsSync() 
                                          ? FileImage(File(localPath)) 
                                          : null)) as ImageProvider?,
                              child: (url == null && thumb == null && (localPath == null || !File(localPath).existsSync()))
                                  ? Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : 'T',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      );
                    }
                  ),
          
          const SizedBox(height: 32),
          
          // Stats Grid
          Container(key: _statsOverviewKey, child: _buildResponsiveStatCards(
             context, 
             _classesCount, 
             _todayClassesCount, 
             _todayClassesList, 
             _studentCount, 
             _sectionIds, 
             _unreadMessages
          )),

          const SizedBox(height: 32),
          
          // Setup Checklist
          _buildSetupChecklist(context, _classesCount, _studentCount),
          
          // We can remove the ListView of students below or keep it? 
          // Previous code had a FutureBuilder for students list at the bottom in StreamBuilder.
          // Let's keep the UI clean. Use the dialog for viewing students.
        ],
      ),
    );
  }


  void _showTodayClassesDialog(BuildContext context, List<Map<String, dynamic>> classes) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today, color: HexColor("#116754")),
                const SizedBox(width: 10),
                const Text('Your Schedule Today'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _getDayName(),
              style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.bold),
            ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SizedBox(
            width: double.maxFinite,
            child: classes.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('You have no classes scheduled for today.', textAlign: TextAlign.center),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: classes.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final c = classes[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: HexColor("#116754").withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.class_outlined, color: HexColor("#116754"), size: 20),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(c['subject'], style: const TextStyle(fontWeight: FontWeight.bold))),
                            if (c['isMySubject'] == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: HexColor("#116754"),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('You', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${c['time']} • Section: ${c['section']}'),
                            if (c['isMySubject'] == false)
                              Text('Instructor: ${c['assignedTeacher']}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: HexColor("#116754"), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showStudentsListDialog(BuildContext context, List<String> mySections) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('My Students'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SizedBox(
            width: double.maxFinite,
            child: mySections.isEmpty 
              ? const Center(child: Text('No students found. Create a section first!'))
              : FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('students')
                      .where('sections', arrayContainsAny: mySections)
                      .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final docs = snapshot.data?.docs ?? [];
                
                if (docs.isEmpty) {
                  return const Center(child: Text('No students found in your sections.'));
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final name = data['name'] ?? 'Unknown';
                    final studentSections = List<String>.from(data['sections'] ?? []);
                    final matchedSections = studentSections.where((s) => mySections.contains(s)).join(', ');

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                        child: Text(
                          name[0].toUpperCase(),
                          style: TextStyle(color: HexColor("#116754"), fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Sections: $matchedSections'),
                    );
                  },
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: HexColor("#116754"), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveStatCards(
    BuildContext context,
    int classesCount,
    int todayClassesCount,
    List<Map<String, dynamic>> todayClassesList,
    int studentCount,
    List<String> allMySections,
    int unreadCount,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (isMobile) {
      return SizedBox(
        height: 140,
        child: ListView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          children: [
            _buildStatChip('CLASSES', classesCount.toString(), Icons.class_outlined, HexColor("#116754"), onTap: () => widget.onNavigate?.call(1), key: _myClassesKey),
            const SizedBox(width: 12),
            _buildStatChip('TODAY', todayClassesCount.toString(), Icons.calendar_today, HexColor("#1e824c"), onTap: () => _showTodayClassesDialog(context, todayClassesList), key: _todayClassesKey),
            const SizedBox(width: 12),
            _buildStatChip('STUDENTS', studentCount.toString(), Icons.people, HexColor("#d4af37"), onTap: () => _showStudentsListDialog(context, allMySections), key: _totalStudentsKey),
            const SizedBox(width: 12),
            _buildStatChip('INBOX', unreadCount.toString(), Icons.mail, HexColor("#e63946"), onTap: () => widget.onNavigate?.call(4), key: _inboxKey),
          ],
        ),
      );
    }

    double cardWidth = 160;
    double spacing = 12;

    if (screenWidth > 900) {
      cardWidth = (screenWidth - 48 - (3 * spacing)) / 4;
    } else if (screenWidth > 600) {
      cardWidth = (screenWidth - 48 - spacing) / 2;
    }

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        SizedBox(
          key: _myClassesKey,
          width: cardWidth, 
          child: _buildStatCard('My Classes', classesCount.toString(), Icons.class_outlined, HexColor("#116754"), onTap: () => widget.onNavigate?.call(1))
        ),
        SizedBox(
          key: _todayClassesKey,
          width: cardWidth,
          child: _buildStatCard(
            'Classes Today',
            todayClassesCount.toString(),
            Icons.calendar_today,
            HexColor("#1e824c"),
            onTap: () => _showTodayClassesDialog(context, todayClassesList),
          ),
        ),
        SizedBox(key: _totalStudentsKey, width: cardWidth, child: _buildStatCard('Total Students', studentCount.toString(), Icons.people, HexColor("#d4af37"), onTap: () => _showStudentsListDialog(context, allMySections))),
        SizedBox(key: _inboxKey, width: cardWidth, child: _buildStatCard('Inbox', unreadCount.toString(), Icons.mail, HexColor("#e63946"), onTap: () => widget.onNavigate?.call(4))),
      ],
    );
  }

  Widget _buildStatChip(String label, String value, IconData icon, Color color, {VoidCallback? onTap, Key? key}) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupChecklist(BuildContext context, int classesCount, int studentCount) {
    if (classesCount > 0 && studentCount > 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: HexColor("#116754").withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded, color: HexColor("#116754"), size: 28),
              const SizedBox(width: 12),
              Text(
                "Getting Started",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: HexColor("#116754"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildChecklistItem(
            title: "Create your first class",
            isCompleted: classesCount > 0,
            onTap: classesCount == 0 ? () => widget.onNavigate?.call(1) : null,
          ),
          const SizedBox(height: 12),
          _buildChecklistItem(
            title: "Add students to your class",
            isCompleted: studentCount > 0,
            onTap: (classesCount > 0 && studentCount == 0) ? () => widget.onNavigate?.call(1) : null,
            isLocked: classesCount == 0,
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem({
    required String title,
    required bool isCompleted,
    VoidCallback? onTap,
    bool isLocked = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isCompleted 
              ? HexColor("#116754").withValues(alpha: 0.1) 
              : (isLocked ? Colors.grey[100] : Colors.grey[50]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCompleted 
                ? HexColor("#116754") 
                : (isLocked ? Colors.grey[300]! : Colors.grey[400]!),
          ),
        ),
        child: Row(
          children: [
             Container(
               padding: const EdgeInsets.all(4),
               decoration: BoxDecoration(
                 shape: BoxShape.circle,
                 color: isCompleted ? HexColor("#116754") : Colors.transparent,
                 border: Border.all(
                   color: isCompleted ? HexColor("#116754") : (isLocked ? Colors.grey : Colors.grey[600]!),
                   width: 2,
                 ),
               ),
               child: Icon(
                 Icons.check,
                 size: 14,
                 color: isCompleted ? Colors.white : Colors.transparent,
               ),
             ),
             const SizedBox(width: 16),
             Expanded(
               child: Text(
                 title,
                 style: TextStyle(
                   fontSize: 16,
                   fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
                   color: isCompleted 
                      ? HexColor("#116754") 
                      : (isLocked ? Colors.grey : Colors.black87),
                   decoration: isCompleted ? TextDecoration.lineThrough : null,
                 ),
               ),
             ),
             if (!isCompleted && !isLocked)
               Icon(Icons.arrow_forward_ios_rounded, size: 16, color: HexColor("#116754")),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: value.length > 12 ? 22 : 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
  String _getDayName() {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[DateTime.now().weekday - 1];
  }

  void startTour() {
    GuidePointer.show(
      context,
      steps: [
        GuideStep(
          targetKey: _statsOverviewKey,
          title: "Teacher Dashboard",
          content: "Welcome! Here you can see an overview of your classes, today's schedule, students, and inbox messages.",
        ),
        GuideStep(
          targetKey: _myClassesKey,
          title: "Class Management",
          content: "Tap here to manage your sections, add students, or update grades.",
        ),
        GuideStep(
          targetKey: _todayClassesKey,
          title: "Today's Schedule",
          content: "Review your upcoming classes for today at a glance.",
        ),
        GuideStep(
          targetKey: _totalStudentsKey,
          title: "Students Count",
          content: "Monitor the total number of students across all your active sections.",
        ),
        GuideStep(
          targetKey: _inboxKey,
          title: "Inbox & Messages",
          content: "View student requests to join your sections, or notifications when other teachers add you to their classes.",
          buttonLabel: "Finish Tour",
        ),
      ],
      onComplete: () {},
    );
  }
}
