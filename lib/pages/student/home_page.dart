import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lime/pages/student/request_section_page.dart';
import 'package:lime/pages/student/about_page.dart';
import 'package:lime/pages/student/inbox_page.dart';
import 'package:lime/widgets/guide_pointer.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';

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
      final sectionName = doc.id;

      // Skip demo sections unless in tutorial mode
      if ((sectionName.contains('[TUTORIAL]') || sectionName.contains('Demo Section'))) {
        continue;
      }

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
        final sectionName = doc.id;

        // Skip demo sections
        if ((sectionName.contains('[TUTORIAL]') || sectionName.contains('Demo Section'))) {
          continue;
        }

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

  void _showEventDetailDialog(BuildContext context, Map<String, dynamic> data, String day, String month) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        backgroundColor: const Color(0xFFF9F7F2), // Off-white paper color
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Newspaper Header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.black26, width: 1)),
                ),
                child: Text(
                  'LIME CHRONICLE',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: Colors.black54,
                  ),
                ),
              ),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Headline
                            Text(
                              data['title'] ?? 'No Title',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Byline / Date
                            Row(
                              children: [
                                Text(
                                  '$month $day, 2026',
                                  style: GoogleFonts.merriweather(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.black54,
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('•', style: TextStyle(color: Colors.black26)),
                                ),
                                Text(
                                  'By Administration',
                                  style: GoogleFonts.merriweather(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Image
                      if (data['imageUrl'] != null && (data['imageUrl'] as String).isNotEmpty)
                        Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            border: Border.symmetric(horizontal: BorderSide(color: Colors.black12)),
                          ),
                          child: _buildNetworkImage(
                            data['imageUrl'] as String,
                            height: 250,
                            width: double.infinity,
                          ),
                        ),

                      // Body Text
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          data['desc'] ?? 'No description available.',
                          style: GoogleFonts.merriweather(
                            fontSize: 16,
                            height: 1.6,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.justify,
                        ),
                      ),

                      // Link Button
                      if (data['externalLink'] != null && (data['externalLink'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                final uri = Uri.parse(data['externalLink'] as String);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: HexColor("#116754"),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                elevation: 0,
                              ),
                              child: Text(
                                'READ FULL STORY ON ${Uri.parse(data['externalLink'] as String).host.replaceFirst('www.', '').toUpperCase()}',
                                style: GoogleFonts.playfairDisplay(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Footer / Close
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.black12)),
                ),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.black54,
                  ),
                  child: Text(
                    'CLOSE EDITION',
                    style: GoogleFonts.playfairDisplay(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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
                  const SizedBox(height: 12),
                  Container(
                    key: widget.statsOverviewKey,
                    child: _buildDesktopStats(width),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildEventsList()),
                      const SizedBox(width: 24),
                      Expanded(child: _buildAcademicCalendar()),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        }

        // Mobile Layout - Modern Dashboard
        // Removed nested Scaffold on mobile to avoid Overlay/SafeArea conflicts
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                  
                  const SizedBox(height: 16),

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

                  const SizedBox(height: 16),

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



                  const SizedBox(height: 24),
                  _buildEventsList(),
                  const SizedBox(height: 24),
                  _buildAcademicCalendar(),
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

  Widget _buildEventsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'News & Events',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: HexColor("#116754"),
              ),
            ),
            TextButton(
              onPressed: () => _showAllEvents(),
              child: Text(
                'View All',
                style: TextStyle(color: HexColor("#116754"), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('events')
              .orderBy('date', descending: true)
              .limit(10)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(color: HexColor("#116754")),
                ),
              );
            }
            
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(Icons.event_busy, size: 40, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      'No upcoming events',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                debugPrint('Event data for ${doc.id}: imageUrl=${data['imageUrl']}, title=${data['title']}');
                final Timestamp? ts = data['date'] as Timestamp?;
                final dt = ts?.toDate() ?? DateTime.now();
                final day = dt.day.toString().padLeft(2, '0');
                final months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
                final month = months[dt.month - 1];
                
                return InkWell(
                  onTap: () => _showEventDetailDialog(context, data, day, month),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        if (data['imageUrl'] != null && (data['imageUrl'] as String).isNotEmpty)
                          Container(
                            width: 80,
                            height: 80,
                            margin: const EdgeInsets.only(right: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _buildNetworkImage(
                                data['imageUrl'] as String,
                                height: 80,
                                width: 80,
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 60,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: HexColor("#116754").withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: HexColor("#116754").withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  day,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: HexColor("#116754"),
                                  ),
                                ),
                                Text(
                                  month,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: HexColor("#116754"),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (data['imageUrl'] == null || (data['imageUrl'] as String).isEmpty)
                          const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['title'] ?? 'No Title',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                data['desc'] ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (data['externalLink'] != null && (data['externalLink'] as String).isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    'Tap to view more →',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: HexColor("#116754"),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAcademicCalendar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Academic Calendar',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: HexColor("#116754"),
              ),
            ),
              TextButton(
              onPressed: () => _showFullCalendar(),
              child: Text(
                'View Full',
                style: TextStyle(color: HexColor("#116754"), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 340,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('events').snapshots(),
            builder: (context, snapshot) {
              // Note: Standard CalendarDatePicker doesn't support custom day builders.
              // We listen to the stream here so the widget rebuilds on updates,
              // preparing for a future upgrade to a custom calendar widget that supports markers.
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.light(
                    primary: HexColor("#116754"),
                    onPrimary: Colors.white,
                    onSurface: Colors.black87,
                  ),
                  textButtonTheme: TextButtonThemeData(
                    style: TextButton.styleFrom(foregroundColor: HexColor("#116754")),
                  ),
                ),
                child: CalendarDatePicker(
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2025),
                  lastDate: DateTime(2030),
                  onDateChanged: (v) {},
                ),
              );
            }
          ),
        ),
      ],
    );
  }

  void _showAllEvents() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: HexColor("#F9F7F2"),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: Text(
              'NEWS & EVENTS',
              style: GoogleFonts.playfairDisplay(
                color: HexColor("#116754"),
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            iconTheme: IconThemeData(color: HexColor("#116754")),
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('events')
                .orderBy('date', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) return const Center(child: Text('No events found'));

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final Timestamp? ts = data['date'] as Timestamp?;
                  final dt = ts?.toDate() ?? DateTime.now();
                  final day = dt.day.toString().padLeft(2, '0');
                  final months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
                  final month = months[dt.month - 1];

                  return InkWell(
                    onTap: () => _showEventDetailDialog(context, data, day, month),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        children: [
                          if (data['imageUrl'] != null && (data['imageUrl'] as String).isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _buildNetworkImage(data['imageUrl'] as String, height: 100, width: 100),
                            )
                          else
                            Container(
                              width: 80,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              decoration: BoxDecoration(
                                color: HexColor("#116754").withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Text(day, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: HexColor("#116754"))),
                                  Text(month, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: HexColor("#116754"))),
                                ],
                              ),
                            ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['title'] ?? 'No Title', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text(data['desc'] ?? '', style: TextStyle(color: Colors.grey[600]), maxLines: 3, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showFullCalendar() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Academic Calendar',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: HexColor("#116754")),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 400,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: ColorScheme.light(
                      primary: HexColor("#116754"),
                      onPrimary: Colors.white,
                      onSurface: Colors.black87,
                    ),
                  ),
                  child: CalendarDatePicker(
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2030),
                    onDateChanged: (v) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkImage(String url, {double? height, double? width}) {
    debugPrint('_buildNetworkImage called for URL length: ${url.length}');
    
    // Check for Base64 Data URI
    if (url.startsWith('data:image')) {
      try {
        final base64String = url.split(',').last;
        final Uint8List bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          height: height,
          width: width,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: height,
              width: width,
              color: Colors.grey[100],
              child: const Icon(Icons.error, color: Colors.red),
            );
          },
        );
      } catch (e) {
        debugPrint('Error decoding base64 image: $e');
        return Container(
          height: height,
          width: width,
          color: Colors.grey[100],
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, color: Colors.red),
              Text('Bad Base64', style: TextStyle(fontSize: 10, color: Colors.red)),
            ],
          ),
        );
      }
    }

    return FutureBuilder<Uint8List>(
      future: _fetchImage(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: height,
            width: width,
            color: Colors.grey[100],
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          final errorParams = snapshot.error.toString();
          debugPrint('Error loading image for $url: $errorParams');
          return Container(
            height: height,
            width: width,
            color: Colors.grey[100],
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    errorParams,
                    style: const TextStyle(color: Colors.red, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            height: height,
            width: width,
            fit: BoxFit.cover,
          );
        }

        return Container(height: height, width: width, color: Colors.grey[100]);
      },
    );
  }

  Future<Uint8List> _fetchImage(String url) async {
    try {
      debugPrint('Attempting standard fetch for: $url');
      final uri = Uri.parse(url.trim());
      // Add headers to mimic a browser
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      });
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        debugPrint('Standard fetch failed with status: ${response.statusCode}');
        // If 400+, throw to trigger catch block which tries fallback
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Standard fetch exception: $e. Trying fallback...');
      try {
        // Fallback: Use dart:io HttpClient which allows ignoring bad certificates
        // This often fixes SSL Handshake issues on Windows
        final client = HttpClient()
          ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);
        final request = await client.getUrl(Uri.parse(url.trim()));
        // Add headers to fallback too
        request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36');
        
        final response = await request.close();
        
        if (response.statusCode == 200) {
          final bytes = await consolidateHttpClientResponseBytes(response);
          return bytes;
        } else {
           throw Exception('Fallback HTTP ${response.statusCode}');
        }
      } catch (fallbackError) {
        debugPrint('Fallback fetch failed: $fallbackError');
        // Throw the original error to show in UI
        throw Exception('Failed: $e\nFallback: $fallbackError');
      }
    }
  }
}