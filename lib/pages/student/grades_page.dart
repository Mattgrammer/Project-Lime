import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GradesPage extends StatefulWidget {
  const GradesPage({super.key});

  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  bool _isLoading = true;
  double _gpa = 0.0;
  late final String _academicYear;
  int _activeSemester = 1; // 1 or 2
  List<Map<String, dynamic>> _allGrades = [];
  List<Map<String, dynamic>> _filteredGrades = [];

  String _calculateSemester() {
    final now = DateTime.now();
    final currentYear = now.year;
    // Academic year typically starts in June/July
    // If current month is June or later, use current year as start
    // Otherwise use previous year as start
    final startYear = now.month >= 6 ? currentYear : currentYear - 1;
    final endYear = startYear + 1;
    return '$startYear-$endYear';
  }

  @override
  void initState() {
    super.initState();
    _academicYear = _calculateSemester();
    _loadGrades();
  }

  Future<void> _loadGrades() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Live listener for real-time updates
      FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .snapshots()
          .listen((doc) async {
        if (!doc.exists) return;

        final data = doc.data();
        if (data == null) return;

        final gradesMap = data['grades'] as Map<String, dynamic>?;
        final sections = List<String>.from(data['sections'] ?? []);
        
        // Fetch all subjects from schedules
        Map<String, Map<String, dynamic>> allSubjects = {};
        
        for (final sectionName in sections) {
          try {
            final sectionDoc = await FirebaseFirestore.instance
                .collection('sections')
                .doc(sectionName)
                .get();
            
            if (sectionDoc.exists && sectionDoc.data()?['schedule'] != null) {
              final schedule = sectionDoc.data()!['schedule'] as List<dynamic>;
              
              for (var item in schedule) {
                if (item is Map<String, dynamic>) {
                  final subject = item['subject'] as String?;
                  final sem = item['semester'] as int? ?? 1;
                  if (subject != null) {
                    allSubjects[subject] = {
                      'subject': subject,
                      'section': sectionName,
                      'semester': sem,
                      'grade': null,
                      'remarks': 'Not graded yet',
                    };
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('Error loading schedule for section $sectionName: $e');
          }
        }
        
        // Merge with actual grades
        if (gradesMap != null) {
          gradesMap.forEach((subject, gradeVal) {
            double? grade;
            
            if (gradeVal is Map) {
              // New format: {q1: 85, q2: 90}
              // Calculate average of existing quarters
              final quarters = gradeVal.values.whereType<num>();
              if (quarters.isNotEmpty) {
                final sum = quarters.fold(0.0, (a, b) => a + b.toDouble());
                grade = sum / quarters.length;
              }
            } else if (gradeVal is num) {
              // Legacy format: 85
              grade = gradeVal.toDouble();
            }

            if (grade != null) {
              // Round to 2 decimal places
              grade = double.parse(grade.toStringAsFixed(2));
              
              if (allSubjects.containsKey(subject)) {
                allSubjects[subject]!['grade'] = grade;
                allSubjects[subject]!['remarks'] = _getRemarks(grade);
              } else {
                // Grade exists but not in schedule (legacy data)
                allSubjects[subject] = {
                  'subject': subject,
                  'section': '',
                  'grade': grade,
                  'remarks': _getRemarks(grade),
                };
              }
            }
          });
        }
        
        List<Map<String, dynamic>> loadedGrades = allSubjects.values.toList();
        
        if (mounted) {
          setState(() {
            _allGrades = loadedGrades;
            _applyFilter();
            _isLoading = false;
          });
        }
      });
      
    } catch (e) {
      debugPrint('Error loading grades: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    // Filter subjects for the active semester
    _filteredGrades = _allGrades.where((g) => g['semester'] == _activeSemester).toList();
    
    // Calculate GPA for the active semester
    double avg = 0.0;
    final gradedSubjects = _filteredGrades.where((g) => g['grade'] != null).toList();
    if (gradedSubjects.isNotEmpty) {
      final total = gradedSubjects.fold(0.0, (acc, item) => acc + (item['grade'] as double));
      avg = total / gradedSubjects.length;
      avg = double.parse(avg.toStringAsFixed(2));
    }
    _gpa = avg;
  }

  String _getRemarks(double grade) {
    if (grade >= 95) return 'Excellent';
    if (grade >= 90) return 'Very Good';
    if (grade >= 85) return 'Good';
    if (grade >= 80) return 'Satisfactory';
    if (grade >= 75) return 'Passed';
    return 'Failed';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _loadGrades,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Grades',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: HexColor("#0F4C7F"),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'View your academic performance',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),

              // Semester Toggle
              LayoutBuilder(
                builder: (context, constraints) {
                  final isSmall = constraints.maxWidth < 360;
                  return Center(
                    child: SegmentedButton<int>(
                      segments: [
                        ButtonSegment(
                          value: 1, 
                          label: Text(isSmall ? 'Sem 1' : '1st Semester'), 
                          icon: isSmall ? null : const Icon(Icons.looks_one),
                        ),
                        ButtonSegment(
                          value: 2, 
                          label: Text(isSmall ? 'Sem 2' : '2nd Semester'), 
                          icon: isSmall ? null : const Icon(Icons.looks_two),
                        ),
                      ],
                      selected: {_activeSemester},
                      onSelectionChanged: (Set<int> newSelection) {
                        setState(() {
                          _activeSemester = newSelection.first;
                          _applyFilter();
                        });
                      },
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        backgroundColor: Colors.white,
                        selectedBackgroundColor: HexColor("#0F4C7F"),
                        selectedForegroundColor: Colors.white,
                        padding: isSmall ? EdgeInsets.zero : null,
                      ),
                    ),
                  );
                }
              ),
              const SizedBox(height: 24),

              // GPA Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      HexColor("#0F4C7F"),
                      HexColor("#1e824c"),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: HexColor("#0F4C7F").withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'General Average',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _gpa.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_academicYear • ${_activeSemester == 1 ? "1st" : "2nd"} Semester',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.star,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              Text(
                'Subject Grades',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: HexColor("#0F4C7F"),
                ),
              ),
              const SizedBox(height: 16),

              if (_filteredGrades.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.grade_outlined,
                          size: 60,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No subjects for this semester',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // Grade Cards
                for (var g in _filteredGrades) ...[
                  _buildGradeCard(
                    g['subject'] ?? '', 
                    g['grade'] as double?, 
                    g['remarks'] ?? '', 
                    g['section'] ?? ''
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradeCard(String subject, double? grade, String remarks, String section) {
    Color gradeColor;
    if (grade == null) {
      gradeColor = Colors.grey; // Not graded yet
    } else if (grade >= 90) {
      gradeColor = HexColor("#1e824c"); // Green
    } else if (grade >= 85) {
      gradeColor = HexColor("#0F4C7F"); // Blue
    } else if (grade >= 75) {
      gradeColor = HexColor("#d4af37"); // Gold
    } else {
      gradeColor = HexColor("#e63946"); // Red
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$section • $remarks',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: gradeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: gradeColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              grade.toString(),
              style: TextStyle(
                color: gradeColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
