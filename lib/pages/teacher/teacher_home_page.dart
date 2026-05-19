import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
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
          const SizedBox(height: 32),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEventsList(),
                    const SizedBox(height: 24),
                    _buildAcademicCalendar(),
                  ],
                );
              } else {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildEventsList()),
                    const SizedBox(width: 24),
                    Expanded(child: _buildAcademicCalendar()),
                  ],
                );
              }
            },
          ),
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

  Widget _buildNetworkImage(String url, {double? height, double? width}) {
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
      final uri = Uri.parse(url.trim());
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      });
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      try {
        final client = HttpClient()
          ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);
        final request = await client.getUrl(Uri.parse(url.trim()));
        request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36');
        
        final response = await request.close();
        
        if (response.statusCode == 200) {
          final bytes = await consolidateHttpClientResponseBytes(response);
          return bytes;
        } else {
           throw Exception('Fallback HTTP ${response.statusCode}');
        }
      } catch (fallbackError) {
        throw Exception('Failed: $e');
      }
    }
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
