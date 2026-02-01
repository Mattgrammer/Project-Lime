import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lime/pages/student/request_section_page.dart';
import 'package:lime/pages/student/about_page.dart';
import 'package:lime/pages/student/inbox_page.dart';
import 'package:lime/widgets/guide_pointer.dart'; // NEW IMPORT
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:io';

class HomePage extends StatefulWidget {
  final Function(int index, {int? initialTab})? onNavigate;
  final Stream<QuerySnapshot>? sectionsStream;
  final String? profileImagePath;
  final String? profileImageThumbnail;
  final String? profileImageUrl;
  final Uint8List? profileThumbnailBytes;
  
  // Keys for spotlight targets
  final GlobalKey? scheduleKey;
  final GlobalKey? classesKey;
  final GlobalKey? gradesKey;
  final GlobalKey? profileKey;
  final GlobalKey? helpKey;
  final GlobalKey? statsOverviewKey; // Parent-managed key

  const HomePage({
    super.key, 
    this.onNavigate, 
    this.scheduleKey,
    this.classesKey, 
    this.gradesKey,
    this.profileKey,
    this.helpKey,
    this.statsOverviewKey,
    this.sectionsStream,
    this.profileImagePath,
    this.profileImageThumbnail,
    this.profileImageUrl,
    this.profileThumbnailBytes,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription? _statsSubscription;
  StreamSubscription? _sectionsSubscription;
  StreamSubscription? _messagesSubscription;
  int _enrolledS1 = 0;
  int _enrolledS2 = 0;
  int _upcomingClasses = 0;
  double _avgSem1 = 0.0;
  double _avgSem2 = 0.0;
  Map<String, dynamic>? _lastGradesMap;
  QuerySnapshot? _lastSectionsSnapshot;
  int _unreadMessages = 0;
  List<Map<String, dynamic>> _todayClassesDetails = [];
  String? _profileImageUrl;
  String? _profileImageThumbnail;
  bool _isLoading = true;
  Map<String, dynamic> _releaseDates = {};

  // NEW: For tutorial
  final GlobalKey _joinClassKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadStats();
    _listenToGradeRelease();
    
    // Safety timeout: If still loading after 3 seconds, force show the dashboard.
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });
  }

  void _listenToGradeRelease() {
    FirebaseFirestore.instance
        .collection('app_config')
        .doc('grades')
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _releaseDates = data['releaseDates'] as Map<String, dynamic>? ?? {};
        });
      }
    });
  }

  bool _isQuarterLocked(String quarter) {
    final qData = _releaseDates[quarter] as Map<String, dynamic>?;
    final ts = qData?['date'] as Timestamp?;
    if (ts == null) return false;
    return ts.toDate().isAfter(DateTime.now());
  }

  bool _isSemesterLocked(int semester) {
    if (semester == 1) {
      return _isQuarterLocked('q1') || _isQuarterLocked('q2');
    } else {
      return _isQuarterLocked('q3') || _isQuarterLocked('q4');
    }
  }

  DateTime? _getNextReleaseDate() {
    DateTime? next;
    _releaseDates.forEach((key, val) {
      final ts = val['date'] as Timestamp?;
      if (ts != null) {
        final date = ts.toDate();
        if (date.isAfter(DateTime.now())) {
          if (next == null || date.isBefore(next!)) {
            next = date;
          }
        }
      }
    });
    return next;
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _messagesSubscription?.cancel();
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
      
      // Update state data for GPA calculation
      _lastGradesMap = data['grades'] as Map<String, dynamic>?;
      _calculateSemesterGPAs();

      // Fetch Unread count (Real-time listener)
      _messagesSubscription?.cancel();
      _messagesSubscription = FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .collection('inbox')
          .where('read', isEqualTo: false)
          .snapshots()
          .listen((snap) {
            if (mounted) setState(() => _unreadMessages = snap.docs.length);
          });

      // Calculations triggered above
      if (mounted) {
        setState(() {
          // No longer using single _averageGrade
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
      final Set<String> s1Subjects = {};
      final Set<String> s2Subjects = {};
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        final schedule = data?['schedule'] as List?;
        if (schedule != null) {
          for (var item in schedule) {
            if (item is Map<String, dynamic> && item['subject'] != null) {
              final sem = item['semester'] as int? ?? 1;
              if (sem == 1) {
                s1Subjects.add(item['subject']);
              } else {
                s2Subjects.add(item['subject']);
              }
            }
          }
        }
      }

      setState(() {
        _upcomingClasses = todayClassesCount;
        _todayClassesDetails = todayDetails;
        _enrolledS1 = s1Subjects.length;
        _enrolledS2 = s2Subjects.length;
        _lastSectionsSnapshot = snapshot;
        _calculateSemesterGPAs();
        _isLoading = false;
      });
    }
  }

  void _calculateSemesterGPAs() {
    if (_lastGradesMap == null) return;

    final Map<String, int> subjectSemesters = {};
    if (_lastSectionsSnapshot != null) {
      for (var doc in _lastSectionsSnapshot!.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        final schedule = data?['schedule'] as List?;
        if (schedule != null) {
          for (var item in schedule) {
            if (item is Map<String, dynamic> && item['subject'] != null) {
              subjectSemesters[item['subject']] = item['semester'] as int? ?? 1;
            }
          }
        }
      }
    }

    double s1Sum = 0, s2Sum = 0;
    int s1Count = 0, s2Count = 0;

    _lastGradesMap!.forEach((subject, val) {
      double subjectAvg = 0;
      bool hasData = false;
      if (val is Map) {
        final scores = val.values.whereType<num>();
        if (scores.isNotEmpty) {
          subjectAvg = scores.fold(0.0, (a, b) => a + b.toDouble()) / scores.length;
          hasData = true;
        }
      } else if (val is num) {
        subjectAvg = val.toDouble();
        hasData = true;
      }

      if (hasData) {
        int sem = subjectSemesters[subject] ?? 1;
        if (sem == 1) {
          s1Sum += subjectAvg;
          s1Count++;
        } else {
          s2Sum += subjectAvg;
          s2Count++;
        }
      }
    });

    if (mounted) {
      setState(() {
        _avgSem1 = s1Count > 0 ? (s1Sum / s1Count).roundToDouble() : 0.0;
        _avgSem2 = s2Count > 0 ? (s2Sum / s2Count).roundToDouble() : 0.0;
      });
    }
  }

  int get _activeSemester {
    final month = DateTime.now().month;
    // Standard: 2nd Sem (Jan-May: 1-5), 1st Sem (Rest)
    int dateBasedSem = (month >= 1 && month <= 5) ? 2 : 1;
    
    // Smart switch: If date-based sem has 0 subjects but other has data, show the other
    if (dateBasedSem == 1 && _enrolledS1 == 0 && _enrolledS2 > 0) return 2;
    if (dateBasedSem == 2 && _enrolledS2 == 0 && _enrolledS1 > 0) return 1;
    
    return dateBasedSem;
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
                    key: widget.statsOverviewKey,
                    child: _buildDesktopStats(width),
                  ),
                  const SizedBox(height: 32),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        }

        // Mobile Layout - Modern Dashboard
        // Removed nested Scaffold on mobile to avoid Overlay/SafeArea conflicts
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Header
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2.0),
                        ),
                        child: CircleAvatar(
                          key: ValueKey("${_profileImageUrl ?? _profileImageThumbnail}_${widget.profileThumbnailBytes?.length ?? 0}_${widget.profileImagePath}"),
                          radius: 24,
                          backgroundColor: HexColor("#116754"),
                          backgroundImage: widget.profileThumbnailBytes != null 
                              ? MemoryImage(widget.profileThumbnailBytes!)
                              : ((_profileImageThumbnail ?? widget.profileImageThumbnail) != null 
                                  ? MemoryImage(base64Decode(_profileImageThumbnail ?? widget.profileImageThumbnail!))
                                  : ((_profileImageUrl ?? widget.profileImageUrl) != null 
                                      ? NetworkImage(_profileImageUrl ?? widget.profileImageUrl!) 
                                      : (widget.profileImagePath != null && File(widget.profileImagePath!).existsSync()
                                          ? FileImage(File(widget.profileImagePath!))
                                          : null))) as ImageProvider?,
                          child: (widget.profileThumbnailBytes == null && _profileImageUrl == null && _profileImageThumbnail == null && widget.profileImageUrl == null && widget.profileImageThumbnail == null && (widget.profileImagePath == null || !File(widget.profileImagePath!).existsSync()))
                              ? Text(
                                  userName.isNotEmpty ? userName[0].toUpperCase() : 'S',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible( // Changed from Expanded to Flexible to keep photo closer
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
                      if (MediaQuery.of(context).size.width <= 900)
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const InboxPage(isStandalone: true)),
                            );
                          },
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
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
                              if (_unreadMessages > 0)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Text(
                                      _unreadMessages > 9 ? '9+' : '$_unreadMessages',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
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
                    key: widget.statsOverviewKey,
                    height: 150,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      children: [
                         _buildStatChip(
                           'Subjects (S$_activeSemester)',
                           (_activeSemester == 1 ? _enrolledS1 : _enrolledS2).toString(),
                           Icons.book,
                           HexColor("#116754"),
                           onTap: () => widget.onNavigate?.call(0, initialTab: _activeSemester - 1)
                         ),
                         const SizedBox(width: 12),
                         _buildStatChip(
                           'Average Grade',
                           _isSemesterLocked(_activeSemester)
                               ? '🔒' 
                               : (_activeSemester == 1 ? _avgSem1 : _avgSem2).round().toString(),
                           Icons.grade,
                           HexColor("#1e824c"),
                           onTap: _isSemesterLocked(_activeSemester)
                               ? () {
                                   final nextDate = _getNextReleaseDate();
                                   ScaffoldMessenger.of(context).showSnackBar(
                                     SnackBar(
                                       content: Text(nextDate != null 
                                         ? 'Next release: ${_formatDateTime(nextDate)}'
                                         : 'Grades are currently being processed'),
                                       backgroundColor: HexColor("#116754"),
                                     ),
                                   );
                                 }
                               : () => widget.onNavigate?.call(1, initialTab: _activeSemester)
                         ),
                         const SizedBox(width: 12),
                         _buildStatChip(
                           'Classes Today',
                           _upcomingClasses.toString(),
                           Icons.class_outlined,
                           HexColor("#1e824c"),
                           onTap: () => _showTodayClassesDialog(context),
                         ),
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



                  const SizedBox(height: 32),

                    
            ],
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

  String _formatDateTime(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String hour = dt.hour > 12 ? (dt.hour - 12).toString() : (dt.hour == 0 ? "12" : dt.hour.toString());
    String period = dt.hour >= 12 ? "PM" : "AM";
    String minute = dt.minute.toString().padLeft(2, '0');
    return "${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute $period";
  }

  // --- Legacy / Desktop Widgets ---
  
  Widget _buildDesktopStats(double width) {
    int crossAxisCount = width < 900 ? 3 : 4;
    final double spacing = 16;
    final totalSpacing = spacing * (crossAxisCount - 1);
    final cardWidth = (width - 48 - totalSpacing) / crossAxisCount;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        SizedBox(width: cardWidth, child: _buildStatCard('Subjects (S$_activeSemester)', (_activeSemester == 1 ? _enrolledS1 : _enrolledS2).toString(), Icons.book, HexColor("#116754"), onTap: () => widget.onNavigate?.call(0, initialTab: _activeSemester - 1))),
         // Removed Account Type
        SizedBox(width: cardWidth, child: _buildStatCard(
          'Classes Today', 
          _upcomingClasses.toString(), 
          Icons.class_outlined, 
          HexColor("#1e824c"),
          onTap: () => _showTodayClassesDialog(context),
        )),
        SizedBox(width: cardWidth, child: _buildStatCard(
          'Average (S$_activeSemester)', 
          _isSemesterLocked(_activeSemester) 
              ? '🔒' 
              : (_activeSemester == 1 ? _avgSem1 : _avgSem2).round().toString(), 
          Icons.grade, 
          HexColor("#d4af37"), 
          onTap: () => widget.onNavigate?.call(1, initialTab: _activeSemester)
        )),
        SizedBox(width: cardWidth, child: _buildStatCard('Inbox', _unreadMessages.toString(), Icons.mail_outline, HexColor("#e63946"), onTap: () => widget.onNavigate?.call(4))),
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


}