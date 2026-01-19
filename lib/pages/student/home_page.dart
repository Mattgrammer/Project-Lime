import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lime/pages/student/request_section_page.dart';
import 'package:lime/pages/student/about_page.dart';
import 'package:lime/pages/student/notifications_page.dart';
import 'package:lime/widgets/guide_pointer.dart'; // NEW IMPORT
import 'dart:convert';
import 'dart:async';
import 'dart:io';

class HomePage extends StatefulWidget {
  final Function(int index)? onNavigate;
  final bool startTour;
  final Stream<QuerySnapshot>? sectionsStream;
  final String? profileImagePath;
  final String? profileImageThumbnail;
  final String? profileImageUrl;
  
  // Keys for spotlight targets
  final GlobalKey? scheduleKey;
  final GlobalKey? classesKey;
  final GlobalKey? gradesKey;
  final GlobalKey? inboxKey;
  final GlobalKey? profileKey;
  final GlobalKey? helpKey;

  const HomePage({
    super.key, 
    this.onNavigate, 
    this.startTour = false,
    this.scheduleKey,
    this.classesKey, 
    this.gradesKey,
    this.inboxKey,
    this.profileKey,
    this.helpKey,
    this.sectionsStream,
    this.profileImagePath,
    this.profileImageThumbnail,
    this.profileImageUrl,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription? _statsSubscription;
  StreamSubscription? _sectionsSubscription;
  int _enrolledCount = 0;
  int _upcomingClasses = 0;
  double _averageGrade = 0.0;
  int _unreadMessages = 0;
  List<Map<String, dynamic>> _todayClassesDetails = [];
  String? _profileImageUrl;
  String? _profileImageThumbnail;
  bool _isLoading = true;

  // NEW: For tutorial
  final GlobalKey _joinClassKey = GlobalKey();
  final GlobalKey _statsOverviewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadStats();
    
    // Safety timeout: If still loading after 3 seconds, force show the dashboard.
    // This prevents stuck spinners if streams are slow or unexpectedly empty.
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });

    if (widget.startTour) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _startTour();
      });
    }
  }

  void _startTour() {
    GuidePointer.show(
      context,
      steps: [
        GuideStep(
           targetKey: _statsOverviewKey,
           title: "Academic Performance",
           content: "Monitor your enrolled subjects, daily schedule, GPA transitions, and unread communications at a glance.",
        ),
         // Only show Join Class step if not enrolled and looking at empty state
        if (_enrolledCount == 0)
          GuideStep(
            targetKey: _joinClassKey,
            title: "Requesting a Section",
            content: "New here? Use this card to search for your course code and request to join your class section.",
          ),
          
        if (widget.classesKey != null)
          GuideStep(
            targetKey: widget.classesKey!,
            title: "My Subjects",
            content: "Access your enrolled subjects and grades from this tab.",
            buttonLabel: "Next",
          ),
          
        if (widget.gradesKey != null)
          GuideStep(
            targetKey: widget.gradesKey!,
            title: "Grades Overview",
            content: "Track your academic progress and see your latest marks here.",
            buttonLabel: "Next",
          ),
          
        if (widget.inboxKey != null)
           GuideStep(
            targetKey: widget.inboxKey!,
            title: "Inbox",
            content: "Check messages and announcements from your teachers here.",
            buttonLabel: "Next",
          ),
          
        if (widget.helpKey != null)
           GuideStep(
            targetKey: widget.helpKey!,
            title: "Help & Tutorials",
            content: "Need guidance? Access all interactive tutorials and app information right here.",
            buttonLabel: "Next",
          ),
          
        if (widget.profileKey != null)
           GuideStep(
            targetKey: widget.profileKey!,
            title: "Your Profile",
            content: "Manage your account, update your photo, and request new sections for your subjects.",
            buttonLabel: "Finish Tour",
          ),
      ],
      onComplete: () {},
    );
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.startTour && !oldWidget.startTour) {
      _startTour();
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  String _getDayName() {
    final now = DateTime.now();
    switch (now.weekday) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return '';
    }
  }


  @override
  void dispose() {
    GuidePointer.dismiss();
    _statsSubscription?.cancel();
    _sectionsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Listen to Profile (Average Grade, Inbox count etc.)
    _statsSubscription?.cancel();
    _statsSubscription = FirebaseFirestore.instance
        .collection('students')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      final data = doc.data()!;
      
      // Calculate Average Grade from doc
      double avg = 0.0;
      final gradesMap = data['grades'] as Map<String, dynamic>?;
      if (gradesMap != null && gradesMap.isNotEmpty) {
        double sum = 0;
        int count = 0;
        gradesMap.forEach((_, val) {
           if (val is Map) {
             final quarters = val.values.whereType<num>();
             if (quarters.isNotEmpty) {
               final qSum = quarters.fold(0.0, (a, b) => a + b.toDouble());
               sum += qSum / quarters.length;
               count++;
             }
           } else if (val is num) {
             sum += val.toDouble();
             count++;
           }
        });
        if (count > 0) avg = double.parse((sum / count).toStringAsFixed(1));
      }

      // Fetch Unread count (Independent sub-query)
      FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .collection('inbox')
          .where('read', isEqualTo: false)
          .count() // Use count() for efficiency! 0.001 reads/index
          .get()
          .then((countSnap) {
            if (mounted) setState(() => _unreadMessages = countSnap.count ?? 0);
          });

      if (mounted) {
        setState(() {
          _averageGrade = avg;
          _enrolledCount = List<String>.from(data['sections'] ?? []).toSet().length;
        });
      }
    });

    // 2. Listen to Shared Sections Stream
    _sectionsSubscription?.cancel();
    if (widget.sectionsStream != null) {
      _sectionsSubscription = widget.sectionsStream!.listen((snapshot) {
        _processSectionData(snapshot);
      });
    } else {
      // Fallback: Fetch manually if no stream provided (safeguard)
      FirebaseFirestore.instance
          .collection('sections')
          .where('studentUids', arrayContains: user.uid)
          .snapshots()
          .listen((snapshot) {
        _processSectionData(snapshot);
      });
    }
  }

  void _processSectionData(QuerySnapshot snapshot) {
    if (!mounted) return;
    int todayClassesCount = 0;
    List<Map<String, dynamic>> todayDetails = [];
    final currentDay = _getDayName();

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      final schedule = data?['schedule'] as List?;
      if (schedule != null) {
        for (var item in schedule) {
          if (item is Map<String, dynamic> && item['day'] == currentDay) {
            todayClassesCount++;
            todayDetails.add({
              ...item,
              'sectionTitle': doc.id,
            });
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _upcomingClasses = todayClassesCount;
        _todayClassesDetails = todayDetails;
        _isLoading = false;
      });
    }
  }

  void _showTodayClassesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.class_outlined, color: HexColor("#116754")),
                const SizedBox(width: 10),
                const Text('Classes Today'),
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
            child: _todayClassesDetails.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No classes scheduled for today.', textAlign: TextAlign.center),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _todayClassesDetails.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final c = _todayClassesDetails[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: HexColor("#116754").withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.book, color: HexColor("#116754"), size: 20),
                        ),
                        title: Text(c['subject'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${c['time']} • ${c['section']}'),
                            Text('Instructor: ${c['teacher']}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.displayName ?? 'Student';

    return Stack( // WRAPPED IN STACK
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = width < 600;

        if (!isMobile) {
           return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome Back!',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: HexColor("#116754"),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    key: _statsOverviewKey,
                    child: _buildDesktopStats(width),
                  ),
                  const SizedBox(height: 32),
                  _buildInteractiveGuide(context, _enrolledCount), // Added guide to desktop too
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        }

        // Mobile Layout - Modern Dashboard
        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA), // Light grey bg
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Header
                  Row(
                    children: [
                      CircleAvatar(
                        key: ValueKey(_profileImageUrl ?? _profileImageThumbnail),
                        radius: 24,
                        backgroundColor: HexColor("#116754"),
                        backgroundImage: (_profileImageThumbnail ?? widget.profileImageThumbnail) != null 
                            ? MemoryImage(base64Decode(_profileImageThumbnail ?? widget.profileImageThumbnail!))
                            : ((_profileImageUrl ?? widget.profileImageUrl) != null 
                                ? NetworkImage(_profileImageUrl ?? widget.profileImageUrl!) 
                                : (widget.profileImagePath != null && File(widget.profileImagePath!).existsSync()
                                    ? FileImage(File(widget.profileImagePath!))
                                    : null)) as ImageProvider?,
                        child: (_profileImageUrl == null && _profileImageThumbnail == null && widget.profileImageUrl == null && widget.profileImageThumbnail == null && (widget.profileImagePath == null || !File(widget.profileImagePath!).existsSync()))
                            ? Text(
                                userName.isNotEmpty ? userName[0].toUpperCase() : 'S',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getGreeting(),
                              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                            ),
                            Text(
                              userName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: HexColor("#116754"),
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const NotificationsPage()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Icon(Icons.notifications_none_rounded, color: HexColor("#116754")),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),

                  // 2. Search Bar
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RequestSectionPage()),
                      );
                    },
                    child: Container(
                      key: _joinClassKey,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: Colors.grey[400]),
                          const SizedBox(width: 12),
                          Text(
                            'Find your class...',
                            style: TextStyle(color: Colors.grey[400], fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 3. Stats / Quick Actions (Horizontal Scroll)
                  SizedBox(
                    key: _statsOverviewKey,
                    height: 150, // Increased to 150 to definitively fix overflow
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      children: [
                         _buildStatChip('SUBJECTS', _enrolledCount.toString(), Icons.book, HexColor("#116754"), onTap: () => widget.onNavigate?.call(0)),
                         const SizedBox(width: 12),
                         _buildStatChip(
                           'Classes Today', 
                           _upcomingClasses.toString(), 
                           Icons.class_outlined, 
                           HexColor("#1e824c"),
                           onTap: () => _showTodayClassesDialog(context),
                         ),
                         const SizedBox(width: 12),
                         _buildStatChip('Avg Grade', _averageGrade.toString(), Icons.grade, HexColor("#d4af37"), onTap: () => widget.onNavigate?.call(1)),
                         const SizedBox(width: 12),
                         _buildStatChip('Inbox', _unreadMessages.toString(), Icons.mail, HexColor("#e63946"), onTap: () => widget.onNavigate?.call(4)),
                         const SizedBox(width: 12),
                         _buildActionChip('Request', Icons.person_add, HexColor("#8e44ad"), () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const RequestSectionPage()));
                         }),
                         const SizedBox(width: 12),
                         _buildActionChip('About', Icons.info_outline, HexColor("#2c3e50"), () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const AboutPage()));
                         }),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 4. Interactive Quick Start Guide
                  _buildInteractiveGuide(context, _enrolledCount),

                  const SizedBox(height: 32),

                    
                  // Extra space for bottom nav
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        );
        }
        ), // END LayoutBuilder
      ],
    );
  }

  Widget _buildStatChip(String label, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      width: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
            style: TextStyle(
              fontSize: 18, 
              fontWeight: FontWeight.bold, 
              color: Colors.black87
            ),
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

  Widget _buildActionChip(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
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
              label, // Label treated as title for actions
              style: TextStyle(
                fontSize: 14, 
                fontWeight: FontWeight.bold, 
                color: Colors.black87
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
             Text(
              "Tap to view",
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }


  // --- Legacy / Desktop Widgets ---
  
  Widget _buildDesktopStats(double width) {
    int crossAxisCount = width < 900 ? 3 : 4;
    final double spacing = 16;
    final totalSpacing = spacing * (crossAxisCount - 1);
    final cardWidth = (width - 48 - totalSpacing) / crossAxisCount;

    return Wrap(
      key: _statsOverviewKey,
      spacing: spacing,
      runSpacing: spacing,
      children: [
        SizedBox(width: cardWidth, child: _buildStatCard('SUBJECTS', _enrolledCount.toString(), Icons.book, HexColor("#116754"), onTap: () => widget.onNavigate?.call(0))),
         // Removed Account Type
        SizedBox(width: cardWidth, child: _buildStatCard(
          'Classes Today', 
          _upcomingClasses.toString(), 
          Icons.class_outlined, 
          HexColor("#1e824c"),
          onTap: () => _showTodayClassesDialog(context),
        )),
        SizedBox(width: cardWidth, child: _buildStatCard('Average Grade', _averageGrade.toString(), Icons.grade, HexColor("#d4af37"), onTap: () => widget.onNavigate?.call(1))),
        SizedBox(width: cardWidth, child: _buildStatCard('Unread Messages', _unreadMessages.toString(), Icons.mail, HexColor("#e63946"), onTap: () => widget.onNavigate?.call(4))),
      ],
    );
  }


  Widget _buildStatCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.black,
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildInteractiveGuide(BuildContext context, int enrolledCount) {
    if (enrolledCount > 0) return const SizedBox.shrink();

    String title = "Step 1: Join Your Class";
    String description = "You aren't enrolled in any classes yet. Find your class and request to join to see your grades and subjects.";
    IconData icon = Icons.search_rounded;

    return Container(
      key: _joinClassKey,
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [HexColor("#116754"), HexColor("#1e824c")],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: HexColor("#116754").withValues(alpha: 0.3),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RequestSectionPage()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: HexColor("#116754"),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text(
                "Find My Class",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}