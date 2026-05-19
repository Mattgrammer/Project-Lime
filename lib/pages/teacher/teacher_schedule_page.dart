import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../widgets/guide_pointer.dart';
import '../../widgets/schedule_tour.dart';

class TeacherSchedulePage extends StatefulWidget {
  final bool startScheduleTour;
  final Stream<List<DocumentSnapshot>>? sectionsStream;
  const TeacherSchedulePage({super.key, this.startScheduleTour = false, this.sectionsStream});

  @override
  State<TeacherSchedulePage> createState() => TeacherSchedulePageState();
}

class TeacherSchedulePageState extends State<TeacherSchedulePage> {
  bool _isLoading = true;
  bool _isDemoMode = false;
  String _selectedDay = 'Monday';
  int _selectedSemester = 1;
  List<Map<String, dynamic>> _mySchedule = [];
  final List<String> _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday', 'TBA'];
  final GlobalKey _titleKey = GlobalKey();
  final GlobalKey _firstCardKey = GlobalKey();
  final GlobalKey _semesterSwitcherKey = GlobalKey();
  final GlobalKey _dayStripKey = GlobalKey();
  final GlobalKey _emptyStateKey = GlobalKey();

  StreamSubscription? _sectionsSub;

  @override
  void initState() {
    super.initState();
    // Set initial day to today
    final int weekday = DateTime.now().weekday; // 1-7
    if (weekday <= 7) {
      _selectedDay = _days[weekday - 1];
    }

    // Auto-detect semester based on month (Roughly: Aug-Dec = 1, Jan-Jun = 2)
    final int month = DateTime.now().month;
    _selectedSemester = (month >= 8 && month <= 12) ? 1 : 2;

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
            
            if (isMySubject) {
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

      // If the currently selected day has no demo items, switch to the first demo day
      final hasSelectedDay = _mySchedule.any((e) => (e['day']?.toString() ?? '') == _selectedDay);
      if (!hasSelectedDay && _mySchedule.isNotEmpty) {
        _selectedDay = _mySchedule.first['day']?.toString() ?? _selectedDay;
      }

      _isLoading = false;
    });
  }

  // Public method to trigger schedule tour with demo data
  void startScheduleTour() {
    _loadDemoSchedule();
    
    // Slight delay to allow UI to rebuild with demo data before showing guide
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use the ScheduleTour helper so the seen-flag is persisted and steps are built consistently
      ScheduleTour.startForced(
        context,
        keys: [_titleKey, _semesterSwitcherKey, _dayStripKey, _firstCardKey, _emptyStateKey],
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
  // Get sorted entries for selected day and semester
  List<Map<String, dynamic>> _getScheduleForSelectedDay() {
    final List<Map<String, dynamic>> filtered = _mySchedule
        .where((entry) => 
            (entry['day']?.toString() ?? 'TBA') == _selectedDay &&
            (entry['semester'] is int ? entry['semester'] : int.tryParse(entry['semester']?.toString() ?? '1') ?? 1) == _selectedSemester
        )
        .toList();
    
    filtered.sort((a, b) {
      final tA = _parseStartTime(a['time']);
      final tB = _parseStartTime(b['time']);
      return tA.compareTo(tB);
    });
    
    return filtered;
  }

  Gradient _getSubjectGradient(String subject) {
    final lower = subject.toLowerCase();
    if (lower.contains('math')) {
      return LinearGradient(
        colors: [HexColor("#4CAF50"), HexColor("#81C784")], // Nature Green
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (lower.contains('science')) {
      return LinearGradient(
        colors: [HexColor("#009688"), HexColor("#4DB6AC")], // Teal Energy
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (lower.contains('english')) {
      return LinearGradient(
        colors: [HexColor("#2E7D32"), HexColor("#43A047")], // Deep Leaf
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (lower.contains('filipino')) {
      return LinearGradient(
        colors: [HexColor("#689F38"), HexColor("#9CCC65")], // Lime Grass
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (lower.contains('history')) {
      return LinearGradient(
        colors: [HexColor("#33691E"), HexColor("#558B2F")], // Avocado
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (lower.contains('physics')) {
      return LinearGradient(
        colors: [HexColor("#1B5E20"), HexColor("#388E3C")], // Forest
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (lower.contains('chem')) {
      return LinearGradient(
        colors: [HexColor("#00695C"), HexColor("#00897B")], // Dark Teal
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (lower.contains('bio')) {
      return LinearGradient(
        colors: [HexColor("#2E7D32"), HexColor("#4CAF50")], // Jungle
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    return LinearGradient(
      colors: [HexColor("#43A047"), HexColor("#66BB6A")], // Default LIME Green
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  IconData _getSubjectIcon(String subject) {
    final lower = subject.toLowerCase();
    if (lower.contains('math')) return Icons.calculate_outlined;
    if (lower.contains('science')) return Icons.science_outlined;
    if (lower.contains('english')) return Icons.menu_book_outlined;
    if (lower.contains('filipino')) return Icons.translate_outlined;
    if (lower.contains('history')) return Icons.history_edu_outlined;
    if (lower.contains('physics')) return Icons.biotech_outlined;
    if (lower.contains('chem')) return Icons.science;
    if (lower.contains('bio')) return Icons.eco_outlined;
    if (lower.contains('sport') || lower.contains('pe')) return Icons.sports_basketball_outlined;
    if (lower.contains('art')) return Icons.palette_outlined;
    if (lower.contains('music')) return Icons.music_note_outlined;
    return Icons.book_outlined;
  }

  IconData _getDayIcon(String day) {
    switch (day) {
      case 'Monday': return Icons.wb_sunny_outlined;
      case 'Tuesday': return Icons.auto_awesome_outlined;
      case 'Wednesday': return Icons.waves_outlined;
      case 'Thursday': return Icons.bolt_outlined;
      case 'Friday': return Icons.celebration_outlined;
      case 'Saturday': return Icons.weekend_outlined;
      case 'Sunday': return Icons.wb_twilight_outlined;
      default: return Icons.calendar_today_outlined;
    }
  }

  int _parseStartTime(String? timeRange) {
    if (timeRange == null || timeRange == 'TBA') return 9999;
    try {
      // Expected format "8:00 AM - 9:00 AM" or similar
      final startPart = timeRange.split('-')[0].trim();
      final spaceParts = startPart.split(' ');
      final timeParts = spaceParts[0].split(':');
      int hour = int.parse(timeParts[0]);
      int minute = int.parse(timeParts[1]);
      final isPM = spaceParts.length > 1 && spaceParts[1].toUpperCase() == 'PM';
      
      if (isPM && hour != 12) hour += 12;
      if (!isPM && hour == 12) hour = 0;
      
      return hour * 60 + minute;
    } catch (e) {
      return 9999; 
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final scheduleItems = _getScheduleForSelectedDay();

    return Container(
      decoration: BoxDecoration(
        color: HexColor("#9EAC8D"), // Dusted Matcha Base
        gradient: LinearGradient(
          colors: [
            HexColor("#9EAC8D"),
            HexColor("#B5C2A6"),
            HexColor("#9EAC8D"),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Background Decorative Orbs
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: HexColor("#EFEDE0").withValues(alpha: 0.1), // Cream Silk Glow
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 40, 28, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Class Schedule',
                            key: _titleKey,
                            style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              color: HexColor("#111111"), // Forest Espresso
                              letterSpacing: -1.5,
                            ),
                          ),
                          Text(
                            'Focus on your current classes',
                            style: TextStyle(
                              fontSize: 20,
                              color: HexColor("#111111"), 
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // attach key to semester switcher so tour can highlight it
                    Container(key: _semesterSwitcherKey, child: _buildSemesterSwitcher()),
                  ],
                ),
              ),
              
              // attach key to day strip wrapper
              Container(key: _dayStripKey, child: _buildDayStrip()),

              const SizedBox(height: 10),

              Expanded(
                child: scheduleItems.isEmpty
                    ? Container(key: _emptyStateKey, child: _buildEmptyState())
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
                        child: _buildBentoMixGrid(scheduleItems),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBentoMixGrid(List<Map<String, dynamic>> items) {
    // We'll manually group them into rows of 1 or 2 to simulate a bento grid
    List<Widget> rows = [];
    int i = 0;
    while (i < items.length) {
      if (i == 0) {
        // First item is always a Large Wide Card (attach key to first card)
        rows.add(_buildModernBentoCard(items[i], BentoSize.wide, key: _firstCardKey));
        i++;
      } else if (i + 1 < items.length && i % 2 != 0) {
        // Pair up next two as regular cards
        rows.add(Row(
          children: [
            Expanded(child: _buildModernBentoCard(items[i], BentoSize.small)),
            const SizedBox(width: 16),
            Expanded(child: _buildModernBentoCard(items[i+1], BentoSize.small)),
          ],
        ));
        i += 2;
      } else {
        // Standard wide card
        rows.add(_buildModernBentoCard(items[i], BentoSize.wide));
        i++;
      }
      rows.add(const SizedBox(height: 16));
    }
    return Column(children: rows);
  }

  Widget _buildSemesterSwitcher() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: HexColor("#EFEDE0").withValues(alpha: 0.6), // Dimmed Cream Switcher
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: HexColor("#111111").withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [1, 2].map((s) {
          final isSelected = _selectedSemester == s;
          return GestureDetector(
            onTap: () => setState(() => _selectedSemester = s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? HexColor("#EFEDE0") : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                boxShadow: isSelected 
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]
                  : [],
              ),
              child: Text(
                "SEM $s",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? HexColor("#111111") : HexColor("#111111").withValues(alpha: 0.4),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDayStrip() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: _days.map((day) {
          final isSelected = _selectedDay == day;
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: InkWell(
              onTap: () => setState(() => _selectedDay = day),
              borderRadius: BorderRadius.circular(24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                decoration: BoxDecoration(
                  color: isSelected ? HexColor("#EFEDE0") : HexColor("#EFEDE0").withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: isSelected 
                    ? [
                      BoxShadow(
                        color: HexColor("#111111").withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ]
                    : [],
                  border: Border.all(
                    color: isSelected ? HexColor("#111111").withValues(alpha: 0.8) : HexColor("#111111").withValues(alpha: 0.3),
                    width: 2.0,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      day.substring(0, 3).toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? HexColor("#111111") : HexColor("#111111").withValues(alpha: 0.4),
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Icon(_getDayIcon(day), color: isSelected ? HexColor("#111111") : HexColor("#111111").withValues(alpha: 0.2), size: 22),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: HexColor("#EFEDE0"), // Solid Dimmed Cream (Paper Silk)
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: HexColor("#111111").withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10)),
              ],
            ),
            child: Icon(Icons.calendar_month_outlined, size: 80, color: HexColor("#111111").withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 32),
          Text(
            "NO CLASSES SCHEDULED",
            style: TextStyle(
              fontSize: 14, 
              color: HexColor("#111111").withValues(alpha: 0.6), 
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Relax! Enjoy your $_selectedDay",
            style: TextStyle(
              fontSize: 26, 
              color: HexColor("#111111"), 
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  // Allow callers to pass an optional key so the tour can target the widget
  Widget _buildModernBentoCard(Map<String, dynamic> data, BentoSize size, {Key? key}) {
    final title = data['subject'] ?? 'Untitled';
    final section = data['section'] ?? 'Unknown Section';
    final timeStr = data['time'] ?? 'TBA';
    final sem = data['semester'] ?? 1;
    final subjectGradient = _getSubjectGradient(title);
    final subjectIcon = _getSubjectIcon(title);
    final primaryColor = subjectGradient.colors.first;
    
    final bool isWide = size == BentoSize.wide;
    final double cardHeight = isWide ? 140 : 180;

    return Container(
      key: key,
      height: cardHeight,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: HexColor("#EFEDE0"), // Dimmed Cream Side Card
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: HexColor("#111111").withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            // Dynamic Pillar Accent
            Positioned(
              left: 0,
              top: 30,
              bottom: 30,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  gradient: subjectGradient,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
            // Floating Watermark Icon
            Positioned(
              right: -20,
              bottom: -20,
              child: Opacity(
                opacity: 0.04,
                child: Icon(subjectIcon, size: isWide ? 140 : 100, color: HexColor("#C0FF00")), // Brand tinted watermark
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 20, 20),
              child: isWide 
                ? _buildWideContent(title, section, timeStr, sem, subjectIcon, subjectGradient, primaryColor)
                : _buildCompactContent(title, section, timeStr, sem, subjectIcon, subjectGradient, primaryColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideContent(String title, String section, String time, int sem, IconData icon, Gradient gradient, Color color) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                time.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: HexColor("#111111"), letterSpacing: 1),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: HexColor("#111111"), letterSpacing: -0.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                section,
                style: TextStyle(fontSize: 14, color: HexColor("#111111"), fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text("S$sem", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: HexColor("#111111"))),
        ),
      ],
    );
  }

  Widget _buildCompactContent(String title, String section, String time, int sem, IconData icon, Gradient gradient, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color.withValues(alpha: 0.7), size: 24),
            ),
            Text("S$sem", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: HexColor("#111111"))),
          ],
        ),
        const Spacer(),
        Text(
          time,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: HexColor("#111111")),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: HexColor("#111111"), letterSpacing: -0.5, height: 1.1),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          section,
          style: TextStyle(fontSize: 12, color: HexColor("#111111"), fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

enum BentoSize { wide, small }
