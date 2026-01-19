import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class GradesPage extends StatefulWidget {
  final Stream<QuerySnapshot>? sectionsStream;
  const GradesPage({super.key, this.sectionsStream});

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

  @override
  void initState() {
    super.initState();
    _initListeners();
  }

  @override
  void dispose() {
    _gradesSub?.cancel();
    _sectionsSub?.cancel();
    super.dispose();
  }

  void _initListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Listen to Profile for Grades map
    setState(() => _isLoading = true);
    _gradesSub = FirebaseFirestore.instance
        .collection('students')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      _updateGradesView(data: doc.data());
    });

    // 2. Listen to Sections for Schedule (Subject info)
    if (widget.sectionsStream != null) {
      _sectionsSub = widget.sectionsStream!.listen((snapshot) {
        _updateGradesView(sectionsSnapshot: snapshot);
      });
    } else {
      _sectionsSub = FirebaseFirestore.instance
          .collection('sections')
          .where('studentUids', arrayContains: user.uid)
          .snapshots()
          .listen((snapshot) {
        _updateGradesView(sectionsSnapshot: snapshot);
      });
    }
  }

  // Cached data to avoid partial updates flashing
  Map<String, dynamic>? _lastProfileData;
  QuerySnapshot? _lastSectionsSnapshot;

  void _updateGradesView({Map<String, dynamic>? data, QuerySnapshot? sectionsSnapshot}) {
    if (data != null) _lastProfileData = data;
    if (sectionsSnapshot != null) _lastSectionsSnapshot = sectionsSnapshot;

    if (_lastProfileData == null || _lastSectionsSnapshot == null) return;

    final gradesMap = _lastProfileData!['grades'] as Map<String, dynamic>?;
    final Map<String, Map<String, dynamic>> allSubjects = {};

    // 1. Get subjects from Sections
    for (var doc in _lastSectionsSnapshot!.docs) {
      final sectionData = doc.data() as Map<String, dynamic>?;
      if (sectionData?['schedule'] != null) {
        final schedule = sectionData!['schedule'] as List<dynamic>;
        for (var item in schedule) {
          if (item is Map<String, dynamic>) {
            final subject = item['subject'] as String?;
            final sem = item['semester'] as int? ?? 1;
            if (subject != null) {
              allSubjects[subject] = {
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

    // 2. Hydrate with Grades
    if (gradesMap != null) {
      gradesMap.forEach((subject, gradeVal) {
         if (!allSubjects.containsKey(subject)) {
           allSubjects[subject] = {
             'subject': subject,
             'section': 'Unknown',
             'semester': 1,
             'q1': null, 'q2': null, 'q3': null, 'q4': null, 'final': null
           };
         }
         
         final entry = allSubjects[subject]!;
         if (gradeVal is Map) {
           entry['q1'] = gradeVal['q1'];
           entry['q2'] = gradeVal['q2'];
           entry['q3'] = gradeVal['q3'];
           entry['q4'] = gradeVal['q4'];

           List<num> scores = [];
           for (var k in ['q1','q2','q3','q4']) {
             if (entry[k] is num) scores.add(entry[k]);
           }
           if (scores.isNotEmpty) {
             final avg = scores.reduce((a, b) => a + b) / scores.length;
             entry['final'] = double.parse(avg.toStringAsFixed(2));
           }
         } else if (gradeVal is num) {
           entry['final'] = gradeVal.toDouble();
           entry['q1'] = gradeVal; 
         }
      });
    }

    // 3. Calculate GPAs
    final g1 = allSubjects.values.where((e) => e['semester'] == 1 && e['final'] != null).map((e) => e['final'] as double).toList();
    final g2 = allSubjects.values.where((e) => e['semester'] == 2 && e['final'] != null).map((e) => e['final'] as double).toList();

    if (mounted) {
      setState(() {
        _allGrades = allSubjects.values.toList();
        _gpaSem1 = g1.isEmpty ? 0.0 : double.parse((g1.reduce((a,b)=>a+b)/g1.length).toStringAsFixed(2));
        _gpaSem2 = g2.isEmpty ? 0.0 : double.parse((g2.reduce((a,b)=>a+b)/g2.length).toStringAsFixed(2));
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

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
              'Tap any header to view details',
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
        initiallyExpanded: semester == 1, // Open 1st sem by default
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
                   'GPA: $gpa',
                   style: TextStyle(fontWeight: FontWeight.bold, color: HexColor("#116754")),
                 ),
              )
          ],
        ),
        children: [
          const SizedBox(height: 12),
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text("Subject", style: const TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Center(child: Text(h1, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                Expanded(child: Center(child: Text(h2, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                Expanded(child: Center(child: Text("Avg", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: HexColor("#116754"))))),
              ],
            ),
          ),
          
          if (subjects.isEmpty)
             Container(
               padding: const EdgeInsets.all(24),
               width: double.infinity,
               color: Colors.grey[50],
               child: Center(child: Text("No subjects enrolled", style: TextStyle(color: Colors.grey[500]))),
             )
          else
            ...subjects.map((s) {
              // Assuming teacher enters q1/q2 for Sem 1 and q3/q4 for Sem 2.
              final displayQ1 = semester == 1 ? s['q1'] : s['q3'];
              final displayQ2 = semester == 1 ? s['q2'] : s['q4'];
              
              return _buildGradeRow(
                s['subject'],
                displayQ1,
                displayQ2,
                s['final'],
              );
            }),
            
           // Footer spacing
           const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildGradeRow(String subject, dynamic q1, dynamic q2, dynamic finalGrade) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Expanded(
            flex: 3, 
            child: Text(subject, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Center(child: _gradeBox(q1))),
          Expanded(child: Center(child: _gradeBox(q2))),
          Expanded(child: Center(child: _gradeBox(finalGrade, isFinal: true))),
        ],
      ),
    );
  }

  Widget _gradeBox(dynamic grade, {bool isFinal = false}) {
    if (grade == null) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
        child: const Text("-", style: TextStyle(color: Colors.grey)),
      );
    }
    return Text(
      grade.toString(),
      style: TextStyle(
        fontWeight: isFinal ? FontWeight.bold : FontWeight.normal,
        color: isFinal ? HexColor("#116754") : Colors.black87,
      ),
    );
  }
}

