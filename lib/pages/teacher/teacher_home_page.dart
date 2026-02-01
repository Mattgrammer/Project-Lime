import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';
import 'dart:async';
import '../../widgets/guide_pointer.dart';
import 'student_directory_page.dart';

class TeacherHomePage extends StatefulWidget {
  final Function(int index, {int? initialTab})? onNavigate;
  final GlobalKey? scheduleKey;
  final GlobalKey? classesKey;
  final GlobalKey? profileKey;
  final GlobalKey? sidebarScheduleKey;
  final GlobalKey? sidebarClassesKey;
  final GlobalKey? sidebarProfileKey;
  final Stream<List<DocumentSnapshot>>? sectionsStream;
  final String? userName;
  final String? profileImageUrl;
  final String? profileImageThumbnail;
  final String? profileImagePath;
  final String? teacherType;
  final Stream<DocumentSnapshot>? userStream;
  final Uint8List? profileThumbnailBytes;

  const TeacherHomePage({
    super.key, 
    this.onNavigate, 
    this.scheduleKey,
    this.classesKey,
    this.profileKey,
    this.sidebarScheduleKey,
    this.sidebarClassesKey,
    this.sidebarProfileKey,
    this.sectionsStream,
    this.userName,
    this.profileImageUrl,
    this.profileImageThumbnail,
    this.profileImagePath,
    this.teacherType,
    this.userStream,
    this.profileThumbnailBytes,
  });

  @override
  State<TeacherHomePage> createState() => TeacherHomePageState();
}

class TeacherHomePageState extends State<TeacherHomePage> with AutomaticKeepAliveClientMixin {
  StreamSubscription? _sectionsSub;
  StreamSubscription? _inboxSub;

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
  final GlobalKey _notificationBellKey = GlobalKey();
  final ScrollController _statsScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initListeners();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _sectionsSub?.cancel();
    _inboxSub?.cancel();
    _statsScrollController.dispose();
    super.dispose();
  }

  void _initListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final baseQuery = FirebaseFirestore.instance.collection('sections').where(Filter.or(
      Filter('teacherUids', arrayContains: user.uid),
      Filter('adviserUid', isEqualTo: user.uid),
    ));

    final Stream<List<DocumentSnapshot>> stream = widget.sectionsStream ?? baseQuery.snapshots().map((s) => s.docs);
    
    _sectionsSub = stream.listen((snaps) => _processSections(snaps, user.uid));

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

  void _processSections(List<DocumentSnapshot> snaps, String uid) {
    if (!mounted) return;
    int today = 0;
    List<Map<String, dynamic>> list = [];
    int students = 0;
    final String currentDay = _getDayName();

    for (var doc in snaps) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      
      students += (data['studentUids'] as List?)?.length ?? 0;
      final schedule = data['schedule'] as List? ?? [];
      final bool isAdviser = data['adviserUid'] == uid;
      
      for (var item in schedule) {
        if (item is Map) {
          final String itemDay = (item['day'] ?? '').toString().toLowerCase();
          if (itemDay == currentDay.toLowerCase()) {
            final String tUid = (item['teacherUid'] ?? '').toString();
            if (tUid == uid || isAdviser) {
              today++;
              list.add({
                'subject': item['subject'] ?? 'Untitled',
                'time': item['time'] ?? 'TBA',
                'section': doc.id,
              });
            }
          }
        }
      }
    }

    setState(() {
      _classesCount = snaps.length;
      _studentCount = students;
      _todayClassesCount = today;
      _todayClassesList = list;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 32),
          Container(key: _statsOverviewKey, child: _buildResponsiveStats()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        if (widget.profileThumbnailBytes != null) ...[
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: CircleAvatar(radius: 28, backgroundImage: MemoryImage(widget.profileThumbnailBytes!)),
          ),
          const SizedBox(width: 16),
        ],
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Welcome back,', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: HexColor("#116754"))),
          Text(widget.userName ?? 'Teacher', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: HexColor("#116754"))),
        ])),
      ],
    );
  }


  Widget _buildResponsiveStats() {
    final stats = [
      {'title': 'My Classes', 'value': _classesCount.toString(), 'icon': Icons.class_outlined, 'onTap': () => widget.onNavigate?.call(1), 'key': _myClassesKey, 'iconColor': HexColor("#116754")},
      {'title': 'Classes Today', 'value': _todayClassesCount.toString(), 'icon': Icons.calendar_today, 'onTap': () => _showTodayDialog(), 'key': _todayClassesKey, 'iconColor': HexColor("#116754")},
      {'title': 'Total Students', 'value': _studentCount.toString(), 'icon': Icons.people, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => const StudentDirectoryPage())), 'key': _totalStudentsKey, 'iconColor': HexColor("#116754")},
      {'title': 'Inbox', 'value': _unreadMessages.toString(), 'icon': Icons.mail, 'onTap': () => widget.onNavigate?.call(4), 'key': _notificationBellKey, 'iconColor': Colors.orange},
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: constraints.maxWidth > 800 ? 2.2 : (constraints.maxWidth > 600 ? 1.7 : 1.3),
          ),
          itemCount: stats.length,
          itemBuilder: (context, index) {
            final stat = stats[index];
            return _buildStatCard(
              stat['title'] as String,
              stat['value'] as String,
              stat['icon'] as IconData,
              stat['onTap'] as VoidCallback,
              stat['key'] as Key,
              iconColor: stat['iconColor'] as Color,
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, VoidCallback onTap, Key key, {Color? iconColor}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate responsive sizes based on card width
        final double width = constraints.maxWidth;
        final double valSize = (width * 0.18).clamp(24.0, 40.0); // 18% of width, min 24, max 40
        final double titleSize = (width * 0.09).clamp(12.0, 18.0); // 9% of width, min 12, max 18
        final double iconSize = (width * 0.12).clamp(24.0, 32.0); // 12% of width, min 24, max 32

        return InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[400]!, width: 1.5),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: iconSize, color: iconColor ?? HexColor("#116754")),
                  SizedBox(height: width * 0.05), // Dynamic gap
                  Text(value, style: TextStyle(fontSize: valSize, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    title, 
                    style: TextStyle(fontSize: titleSize, color: Colors.grey[700], fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }




  void _showTodayDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Schedule Today'),
      content: SizedBox(
        width: double.maxFinite,
        child: _todayClassesList.isEmpty ? const Text('No classes today') : ListView(
          shrinkWrap: true,
          children: _todayClassesList.map((c) => ListTile(title: Text(c['subject']), subtitle: Text('${c['time']} • ${c['section']}'))).toList(),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ));
  }


  String _getDayName() => ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][DateTime.now().weekday - 1];

  void startTour() {
    GuidePointer.show(
      context,
      steps: [
        GuideStep(targetKey: _statsOverviewKey, title: "Dashboard Overview", content: "View your classes, total students, and unread messages here."),
        GuideStep(targetKey: _myClassesKey, title: "Your Classes", content: "Tap here to see all your assigned sections and manage them."),
        GuideStep(targetKey: _totalStudentsKey, title: "Student Directory", content: "Access a complete directory of all students in your sections."),
        GuideStep(targetKey: _notificationBellKey, title: "Inbox & Notifications", content: "Keep track of student requests and system updates."),
        if (widget.sidebarScheduleKey != null || widget.scheduleKey != null)
          GuideStep(targetKey: widget.sidebarScheduleKey ?? widget.scheduleKey!, title: "Easy Navigation", content: "Switch quickly between your Schedule, Classes, Dashboard, and Profile."),
      ],
      onComplete: () {},
    );
  }
}
