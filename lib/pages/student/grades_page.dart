import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class GradesPage extends StatefulWidget {
  final Stream<QuerySnapshot>? sectionsStream;
  final Map<String, dynamic>? initialData;
  final QuerySnapshot? initialSectionsSnapshot;

  final int? initialSemester;
  const GradesPage({
    super.key,
    this.sectionsStream,
    this.initialData,
    this.initialSectionsSnapshot,
    this.initialSemester,
  });

  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  StreamSubscription? _gradesSub;
  StreamSubscription? _sectionsSub;
  List<Map<String, dynamic>> _allGrades = [];
  double _gpaSem1 = 0.0;
  double _gpaSem2 = 0.0;
  bool _isLoading = true;
  Map<String, dynamic> _releaseDates = {};
  
  // sectionID -> {subject -> {quarter -> grade}}
  final Map<String, Map<String, Map<String, double>>> _sectionGradesData = {};
  final Map<String, StreamSubscription> _sectionGradesSubs = {};

  @override
  void initState() {
    super.initState();
    
    // If we have initial data, use it immediately
    if (widget.initialData != null) {
      _lastProfileData = widget.initialData;
      _lastSectionsSnapshot = widget.initialSectionsSnapshot;
      _updateGradesView();
      
      // If we got data, we don't need independent listeners for now
      // as the parent will rebuild us if data changes.
      if (_lastSectionsSnapshot != null) {
        _isLoading = false;
      }
    }
    
    // Support external stream if provided (e.g. from another flow)
    if (widget.sectionsStream != null) {
       _sectionsSub = widget.sectionsStream!.listen((snapshot) {
         _updateGradesView(sectionsSnapshot: snapshot);
       });
    } else if (widget.initialData == null) {
       // Fallback for isolated usage (rare)
       _initListeners();
    }
    
    _listenToGradeRelease();

    // Safety timeout: stop spinner after 2 seconds if streams hang
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant GradesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh view if new data is passed from parent (Real-time sync)
    if (widget.initialData != oldWidget.initialData || 
        widget.initialSectionsSnapshot != oldWidget.initialSectionsSnapshot) {
      _lastProfileData = widget.initialData;
      _lastSectionsSnapshot = widget.initialSectionsSnapshot;
      _updateGradesView();
      if (_lastSectionsSnapshot != null) {
        _isLoading = false;
      }
    }
  }

  @override
  void dispose() {
    _gradesSub?.cancel();
    _sectionsSub?.cancel();
    for (var sub in _sectionGradesSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }

  // Track current section IDs to avoid unnecessary re-subscriptions
  List<String> _currentSectionIds = [];

  void _initListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 1. Listen to Profile for Grades map AND Section IDs
    // Only show loading if we didn't get initial data
    if (_lastProfileData == null) {
      setState(() => _isLoading = true);
    }
    
    // 1. Listen to Sections (Always needed to know which subcollections to listen to)
    if (widget.sectionsStream != null) {
      _sectionsSub = widget.sectionsStream!.listen((snapshot) {
        _updateGradesView(sectionsSnapshot: snapshot);
        _refreshSectionGradesListeners(snapshot.docs.map((d) => d.id).toList());
      });
    } else {
      // If no sections stream, we need to find the student's sections first
      _gradesSub = FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .snapshots()
          .listen((doc) {
        if (doc.exists) {
          final data = doc.data()!;
          _lastProfileData = data;
          final sections = List<String>.from(data['sections'] ?? []);
          _updateSectionsSubscription(sections);
        }
      });
    }
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


  void _updateSectionsSubscription(List<String> newSectionIds) {
    if (_areListsEqual(_currentSectionIds, newSectionIds)) {
      // Vital fix: If lists match but we are still loading (e.g. empty list or first load completed), clear spinner
      if (_isLoading) {
         // If list is empty, we must clear loading. 
         // If list is NOT empty, we assume the previous subscription handles it, 
         // BUT if it's stuck, the timeout will catch it. 
         // Best to force clear if empty.
         if (newSectionIds.isEmpty) {
           if (mounted) setState(() => _isLoading = false);
         } else if (_lastSectionsSnapshot != null) {
           // If we already have snapshot from initial data, just clear loading
           if (mounted) setState(() => _isLoading = false);
         }
      }
      return;
    }
    _currentSectionIds = newSectionIds;
    
    _sectionsSub?.cancel();

    if (newSectionIds.isEmpty) {
      // Clear sections data if no sections
      _lastSectionsSnapshot = null; 
      // Trigger update with null snapshot effectively clearing section-derived subjects
      // But we need to keep grade-derived subjects, so just call update
      if (mounted) _updateGradesView(); 
      return;
    }

    // Firestore 'whereIn' is limited to 10. 
    // We take the top 10 to be safe and avoid crashes.
    // Filter valid IDs
    final idsToQuery = newSectionIds.where((id) => id.isNotEmpty).take(10).toList();
    
    if (idsToQuery.isEmpty) {
        // Just rely on profile grades if no valid sections
       if (mounted) _updateGradesView(); 
       return;
    }

    _sectionsSub = FirebaseFirestore.instance
        .collection('sections')
        .where(FieldPath.documentId, whereIn: idsToQuery)
        .snapshots()
        .listen((snapshot) {
      _updateGradesView(sectionsSnapshot: snapshot);
      _refreshSectionGradesListeners(snapshot.docs.map((d) => d.id).toList());
    }, onError: (e) {
      debugPrint("Error loading sections in Grades: $e");
      // Even if sections fail, show what we have
      if (mounted) _updateGradesView(); 
    });
  }

  void _refreshSectionGradesListeners(List<String> sectionIds) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Remove listeners for sections we are no longer in
    final removed = _sectionGradesSubs.keys.where((id) => !sectionIds.contains(id)).toList();
    for (var id in removed) {
      _sectionGradesSubs[id]?.cancel();
      _sectionGradesSubs.remove(id);
      _sectionGradesData.remove(id);
    }

    // Add listeners for new sections
    for (var id in sectionIds) {
      if (!_sectionGradesSubs.containsKey(id)) {
        _sectionGradesSubs[id] = FirebaseFirestore.instance
            .collection('sections')
            .doc(id)
            .collection('studentGrades')
            .doc(user.uid)
            .snapshots()
            .listen((doc) {
          if (doc.exists) {
            final data = doc.data()!;
            final rawGrades = data['grades'] as Map?;
            if (rawGrades != null) {
              final Map<String, Map<String, double>> parsedGrades = {};
              rawGrades.forEach((sub, qMap) {
                if (qMap is Map) {
                  parsedGrades[sub.toString()] = qMap.map(
                    (k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0)
                  );
                }
              });
              _sectionGradesData[id] = parsedGrades;
              if (mounted) _updateGradesView();
            }
          }
        });
      }
    }
  }

  bool _areListsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Cached data to avoid partial updates flashing
  Map<String, dynamic>? _lastProfileData;
  QuerySnapshot? _lastSectionsSnapshot;

  void _hydrateSubjectEntry(Map<String, dynamic> entry, dynamic gradeVal) {
    if (gradeVal is Map) {
      entry['q1'] = gradeVal['q1'];
      entry['q2'] = gradeVal['q2'];
      entry['q3'] = gradeVal['q3'];
      entry['q4'] = gradeVal['q4'];

      List<num> scores = [];
      for (var k in ['q1', 'q2', 'q3', 'q4']) {
        if (entry[k] is num) scores.add(entry[k]);
      }
      if (scores.isNotEmpty) {
        final avg = scores.reduce((a, b) => a + b) / scores.length;
        entry['final'] = avg.roundToDouble();
      }
    } else if (gradeVal is num) {
      entry['final'] = gradeVal.roundToDouble();
      entry['q1'] = gradeVal.roundToDouble();
    }
  }

  void _updateGradesView({Map<String, dynamic>? data, QuerySnapshot? sectionsSnapshot}) {
    if (data != null) _lastProfileData = data;
    if (sectionsSnapshot != null) _lastSectionsSnapshot = sectionsSnapshot;

    if (_lastProfileData == null) return;

    final Map<String, Map<String, dynamic>> allSubjects = {};

    // 1. Get subjects from Sections
    if (_lastSectionsSnapshot != null) {
      for (var doc in _lastSectionsSnapshot!.docs) {
        final sectionData = doc.data() as Map<String, dynamic>?;
        if (sectionData?['schedule'] != null) {
          final schedule = sectionData!['schedule'] as List<dynamic>;
          for (var item in schedule) {
            if (item is Map<String, dynamic>) {
              final subject = item['subject'] as String?;
              final sem = item['semester'] as int? ?? 1;
              if (subject != null) {
                final key = "${doc.id}_${subject}_$sem";
                allSubjects[key] = {
                  'subject': subject,
                  'section': doc.id,
                  'semester': sem,
                  'q1': null, 'q2': null, 'q3': null, 'q4': null, 
                  'final': null,
                };
              }
            }
          }
        }
      }
    }

    // 2. Hydrate with Grades from all sections
    _sectionGradesData.forEach((sectionId, gradesMap) {
      gradesMap.forEach((subject, gradeVal) {
        // Find corresponding scheduled subject for this section
        bool found = false;
        // Search in allSubjects for a match with this section and subject
        for (var entry in allSubjects.values) {
          if (entry['section'] == sectionId && entry['subject'] == subject) {
            _hydrateSubjectEntry(entry, gradeVal);
            found = true;
          }
        }

        if (!found) {
          // Subject exists in grades but not in current schedule for this section
          // (Maybe it was removed from schedule but grades remained)
          int inferredSem = 1;
          if (gradeVal.containsKey('q3') || gradeVal.containsKey('q4')) {
            inferredSem = 2;
          }
          
          final key = "${sectionId}_${subject}_$inferredSem";
          allSubjects[key] = {
            'subject': subject,
            'section': sectionId,
            'semester': inferredSem,
            'q1': null, 'q2': null, 'q3': null, 'q4': null, 'final': null
          };
          _hydrateSubjectEntry(allSubjects[key]!, gradeVal);
        }
      });
    });

    // 3. Calculate GPAs
    final g1 = allSubjects.values.where((e) => e['semester'] == 1 && e['final'] != null).map((e) => e['final'] as double).toList();
    final g2 = allSubjects.values.where((e) => e['semester'] == 2 && e['final'] != null).map((e) => e['final'] as double).toList();

    if (mounted) {
      setState(() {
        _allGrades = allSubjects.values.toList();
        _gpaSem1 = g1.isEmpty ? 0.0 : (g1.reduce((a,b)=>a+b)/g1.length).roundToDouble();
        _gpaSem2 = g2.isEmpty ? 0.0 : (g2.reduce((a,b)=>a+b)/g2.length).roundToDouble();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // Unified view: show table always, mask specific quarters
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(
              'Quarterly Grades',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: HexColor("#116754"),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'View your academic performance for each semester.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            
            _buildSemesterSection(1, "1st Semester", _gpaSem1),
            const SizedBox(height: 24),
            _buildSemesterSection(2, "2nd Semester", _gpaSem2),
          ],
        ),
      ),
    );
  }


  Widget _buildSemesterSection(int semester, String title, double gpa) {
    final subjects = _allGrades.where((g) => g['semester'] == semester).toList();
    // Headers for table
    final h1 = semester == 1 ? "1st" : "3rd";
    final h2 = semester == 1 ? "2nd" : "4th";

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: semester == (widget.initialSemester ?? 1), // Open 1st sem by default
        tilePadding: EdgeInsets.zero,
        title: Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: HexColor("#116754"), size: 20),
            const SizedBox(width: 8),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: HexColor("#116754"),
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            if (gpa > 0)
              Container(
                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                 decoration: BoxDecoration(
                   color: HexColor("#116754").withValues(alpha: 0.1),
                   borderRadius: BorderRadius.circular(12),
                 ),
                 child: Text(
                   ['q${semester == 1 ? 1 : 3}', 'q${semester == 1 ? 2 : 4}'].any((q) => _isQuarterLocked(q))
                       ? 'GPA: 🔒'
                       : 'GPA: ${gpa.round()}',
                   style: TextStyle(
                     fontWeight: FontWeight.bold, 
                     color: gpa > 0 ? _getGradeColors(gpa)['txt'] : HexColor("#116754"),
                   ),
                 ),
              )
          ],
        ),
        children: [
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          Table(
            border: TableBorder.all(color: Colors.black, width: 1.0),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
            },
            children: [
              // Header Row
              TableRow(
                decoration: BoxDecoration(color: Colors.grey[100]),
                children: [
                  _buildCell(Text("Subject", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), alignLeft: true),
                  _buildCell(Center(child: Text(_isQuarterLocked('q${semester == 1 ? 1 : 3}') ? '🔒' : h1, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))),
                  _buildCell(Center(child: Text(_isQuarterLocked('q${semester == 1 ? 2 : 4}') ? '🔒' : h2, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))),
                  _buildCell(Center(child: Text("Avg", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: HexColor("#116754"))))),
                ],
              ),
              // Data Rows
              if (subjects.isEmpty)
                 TableRow(
                   children: [
                     _buildCell(
                        Center(child: Text("No subjects enrolled", style: TextStyle(color: Colors.grey[500]))), 
                        colSpan: 4
                     ),
                     const SizedBox(), const SizedBox(), const SizedBox() // Placeholders for validity if colSpan isn't supported directly (Flutter Table doesn't support colSpan nicely without external packages, so we use a different approach or just a single row)
                     // Actually, standard Table doesn't support colSpan. 
                     // fallback to a single cell in a row isn't possible. 
                     // We'll handle empty state outside the Table or just show empty cells.
                   ]
                 )
              else
                ...subjects.map((s) {
                  final q1Key = semester == 1 ? 'q1' : 'q3';
                  final q2Key = semester == 1 ? 'q2' : 'q4';
                  final displayQ1 = _isQuarterLocked(q1Key) ? '🔒' : s[q1Key];
                  final displayQ2 = _isQuarterLocked(q2Key) ? '🔒' : s[q2Key];
                  final isSemLocked = _isQuarterLocked(q1Key) || _isQuarterLocked(q2Key);
                  
                  return TableRow(
                    decoration: const BoxDecoration(color: Colors.white),
                    children: [
                       _buildCell(
                          Text(s['subject'].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                          alignLeft: true
                       ),
                       _buildCell(Center(child: _gradeBox(displayQ1))),
                       _buildCell(Center(child: _gradeBox(displayQ2))),
                       _buildCell(Center(child: _gradeBox(isSemLocked ? '🔒' : s['final'], isFinal: true))),
                    ],
                  );
                }),
            ],
          ),
          
          if (subjects.isEmpty)
             Container(
               padding: const EdgeInsets.all(24),
               width: double.infinity,
               decoration: BoxDecoration(
                 border: Border(
                   left: BorderSide(color: Colors.grey[300]!),
                   right: BorderSide(color: Colors.grey[300]!),
                   bottom: BorderSide(color: Colors.grey[300]!),
                 ),
                 color: Colors.grey[50],
               ),
               child: Center(child: Text("No subjects enrolled", style: TextStyle(color: Colors.grey[500]))),
             ),
             
           // Footer spacing
           const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildCell(Widget child, {bool alignLeft = false, int? colSpan}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Match original padding
      height: 60, // Consistent height
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: child,
    );
  }

  // _buildGradeRow is no longer needed, replaced by inline TableRow creation
  
  Widget _gradeBox(dynamic grade, {bool isFinal = false}) {
    if (grade == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
        child: const Center(child: Text("-", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
      );
    }
    
    if (grade == '🔒') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: const Icon(Icons.lock_rounded, size: 14, color: Colors.grey),
      );
    }

    final double val = (grade is num) ? grade.toDouble() : 0.0;
    final Map<String, Color> colors = _getGradeColors(val);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: val > 0 ? colors['bg'] : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          val > 0 ? val.round().toString() : "-",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: val > 0 ? colors['txt'] : Colors.black87,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Map<String, Color> _getGradeColors(double g) {
    if (g <= 0) return {'bg': Colors.transparent, 'txt': Colors.black};
    if (g < 75) {
      return {'bg': Colors.red.withValues(alpha: 0.1), 'txt': Colors.red};
    } else if (g < 80) {
      return {'bg': Colors.yellow.withValues(alpha: 0.25), 'txt': Colors.yellow[900]!};
    } else if (g < 90) {
      return {'bg': Colors.blue.withValues(alpha: 0.1), 'txt': Colors.blue[700]!};
    } else {
      return {'bg': HexColor("#116754").withValues(alpha: 0.1), 'txt': HexColor("#116754")};
    }
  }
}

