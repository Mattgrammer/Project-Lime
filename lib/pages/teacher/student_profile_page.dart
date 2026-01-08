import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/student.dart';

class StudentProfilePage extends StatefulWidget {
  final Student student;
  final String? sectionName;
  final Function(String subject, String quarter, double? grade) onUpdate;
  final VoidCallback? onAddSubject;

  const StudentProfilePage({
    super.key,
    required this.student,
    this.sectionName,
    required this.onUpdate,
    this.onAddSubject,
  });

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> {
  late Map<String, Map<String, double>> _grades;
  bool _isAdviser = false;
  Set<String> _mySubjects = {};
  bool _isLoadingPermissions = true;
  List<String> _allSubjects = [];
  Map<String, int> _subjectSemesters = {};

  static const Map<String, String> quarterLabels = {
    'q1': '1st',
    'q2': '2nd', 
    'q3': '3rd',
    'q4': '4th',
  };

  @override
  void initState() {
    super.initState();
    _grades = Map<String, Map<String, double>>.from(
      widget.student.grades.map((k, v) => MapEntry(k, Map<String, double>.from(v)))
    );
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final sectionDoc = await firestore.collection('sections').doc(widget.sectionName).get();
      
      if (sectionDoc.exists) {
        final data = sectionDoc.data()!;
        final adviserUid = data['adviserUid'] as String?;
        final schedule = data['schedule'] as List<dynamic>? ?? [];

        final myUid = user.uid;
        final mySubs = <String>{};
        final subjects = <String>{};
        final subSems = <String, int>{};
        
        for (var item in schedule) {
          if (item is Map<String, dynamic>) {
            final sub = item['subject'] as String?;
            final sem = item['semester'] as int? ?? 1;
            if (sub != null) {
              subjects.add(sub);
              subSems[sub] = sem;
              if (item['teacherUid'] == myUid) {
                mySubs.add(sub);
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _isAdviser = adviserUid == myUid;
            _mySubjects = mySubs;
            _allSubjects = subjects.toList()..sort();
            _subjectSemesters = subSems;
            _isLoadingPermissions = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading permissions: $e');
      if (mounted) setState(() => _isLoadingPermissions = false);
    }
  }

  bool _canEditSubject(String subject) {
    return _isAdviser || _mySubjects.contains(subject);
  }

  void _showEditGradeDialog(String subject, String quarter) {
    if (!_canEditSubject(subject)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only edit grades for subjects you teach')),
      );
      return;
    }

    final currentGrade = _grades[subject]?[quarter];
    final controller = TextEditingController(
      text: currentGrade != null && currentGrade > 0 ? currentGrade.toString() : ''
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$subject - ${quarterLabels[quarter]} Quarter'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Grade',
            border: OutlineInputBorder(),
            hintText: 'Enter grade (0-100)',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (currentGrade != null && currentGrade > 0)
            TextButton(
              onPressed: () {
                setState(() {
                  _grades[subject]?[quarter] = 0;
                });
                widget.onUpdate(subject, quarter, null);
                Navigator.pop(context);
              },
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            onPressed: () {
              final grade = double.tryParse(controller.text.trim());
              if (grade != null && grade >= 0 && grade <= 100) {
                setState(() {
                  _grades.putIfAbsent(subject, () => {});
                  _grades[subject]![quarter] = grade;
                });
                widget.onUpdate(subject, quarter, grade);
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid grade (0-100)')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: HexColor("#0F4C7F")),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  double? _calculateOverallAverage({int? semester}) {
    if (_grades.isEmpty) return null;
    
    final averages = <double>[];
    for (final subject in _grades.keys) {
      final avg = _calculateSubjectAverage(subject, semester: semester);
      if (avg != null) averages.add(avg);
    }
    
    if (averages.isEmpty) return null;
    return averages.reduce((a, b) => a + b) / averages.length;
  }

  double? _calculateSubjectAverage(String subject, {int? semester}) {
    final quarters = _grades[subject];
    if (quarters == null || quarters.isEmpty) return null;

    final values = <double>[];
    if (semester == 1) {
      if ((quarters['q1'] ?? 0) > 0) values.add(quarters['q1']!);
      if ((quarters['q2'] ?? 0) > 0) values.add(quarters['q2']!);
    } else if (semester == 2) {
      if ((quarters['q3'] ?? 0) > 0) values.add(quarters['q3']!);
      if ((quarters['q4'] ?? 0) > 0) values.add(quarters['q4']!);
    } else {
      for (final v in quarters.values) {
        if (v > 0) values.add(v);
      }
    }

    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  Widget _buildGPABadge(String label, double? gpa, {bool isPrimary = false}) {
    if (gpa == null) return const SizedBox.shrink();
    final color = isPrimary ? HexColor("#0F4C7F") : Colors.grey[700]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        '$label: ${gpa.toStringAsFixed(2)}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overallAvg = _calculateOverallAverage();
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.student.name),
        backgroundColor: HexColor("#0F4C7F"),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoadingPermissions 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Student Info Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
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
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: HexColor("#0F4C7F").withValues(alpha: 0.1),
                      child: Icon(
                        Icons.person,
                        size: 40,
                        color: HexColor("#0F4C7F"),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.student.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (widget.student.studentId.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'ID: ${widget.student.studentId}',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            widget.sectionName ?? '',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (overallAvg != null) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _buildGPABadge('Sem 1', _calculateOverallAverage(semester: 1)),
                                _buildGPABadge('Sem 2', _calculateOverallAverage(semester: 2)),
                                _buildGPABadge('Final', overallAvg, isPrimary: true),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Grades Table Header
              Text(
                'Quarterly Grades',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: HexColor("#0F4C7F"),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isAdviser 
                    ? 'Tap any cell to edit grades' 
                    : _mySubjects.isNotEmpty 
                        ? 'Tap cells in your subjects to edit grades'
                        : 'View-only mode',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 16),
              
              // Grades Table
              if (_allSubjects.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(Icons.grade, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No subjects scheduled',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (_allSubjects.isEmpty) return const SizedBox.shrink();
                    
                    return Column(
                      children: [
                        _buildSemesterPanel('1st Semester', [1, 2], 1, constraints),
                        const SizedBox(height: 24),
                        _buildSemesterPanel('2nd Semester', [3, 4], 2, constraints),
                        const SizedBox(height: 24),
                        
                        // Final Average Card (Optional extra)
                        if (overallAvg != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: HexColor("#0F4C7F").withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: HexColor("#0F4C7F").withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'OVERALL FINAL AVERAGE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: HexColor("#0F4C7F"),
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                Text(
                                  overallAvg.toStringAsFixed(2),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: HexColor("#0F4C7F"),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  }
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSemesterPanel(String title, List<int> quarters, int semesterNum, BoxConstraints constraints) {
    final isSmallScreen = constraints.maxWidth < 600;
    final dynamicSpacing = isSmallScreen ? 16.0 : (constraints.maxWidth - 250) / 4;
    final spacing = dynamicSpacing < 24.0 ? 24.0 : dynamicSpacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 18, color: HexColor("#0F4C7F")),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: HexColor("#0F4C7F"),
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              if (widget.onAddSubject != null)
                IconButton(
                  icon: const Icon(Icons.add_circle, size: 24),
                  color: HexColor("#0F4C7F"),
                  onPressed: widget.onAddSubject,
                  tooltip: 'Add Subject',
                ),
            ],
          ),
        ),
        Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dataTableTheme: DataTableThemeData(
                      headingRowColor: WidgetStateProperty.all(HexColor("#0F4C7F").withValues(alpha: 0.05)),
                      dataRowMinHeight: 56,
                      dataRowMaxHeight: 56,
                    ),
                  ),
                  child: DataTable(
                    columnSpacing: spacing,
                    border: TableBorder(
                      verticalInside: BorderSide(color: Colors.grey[300]!, width: 1),
                      horizontalInside: BorderSide(color: Colors.grey[100]!, width: 0.5),
                    ),
                    columns: [
                      const DataColumn(
                        label: SizedBox(
                          width: 200,
                          child: Text('Subject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      ),
                      DataColumn(label: Text('${quarterLabels['q${quarters[0]}']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('${quarterLabels['q${quarters[1]}']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(
                        label: Text(
                          'S$semesterNum Avg', 
                          style: TextStyle(fontWeight: FontWeight.bold, color: HexColor("#1e824c")),
                        ),
                      ),
                    ],
                    rows: _allSubjects
                        .where((subject) => _subjectSemesters[subject] == semesterNum)
                        .map((subject) {
                      final semAvg = _calculateSubjectAverage(subject, semester: semesterNum);
                      final canEdit = _canEditSubject(subject);
                      
                      return DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 200,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Expanded(
                                    child: Text(
                                      subject, 
                                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (canEdit)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Icon(Icons.edit, size: 14, color: Colors.grey[400]),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          _buildGradeCell(subject, 'q${quarters[0]}', canEdit),
                          _buildGradeCell(subject, 'q${quarters[1]}', canEdit),
                          _buildAvgCell(semAvg, isFinal: false),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  DataCell _buildGradeCell(String subject, String q, bool canEdit) {
    final grade = _grades[subject]?[q];
    final hasGrade = grade != null && grade > 0;
    
    return DataCell(
      InkWell(
        onTap: canEdit ? () => _showEditGradeDialog(subject, q) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: hasGrade 
                ? _getGradeColor(grade).withValues(alpha: 0.1)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            hasGrade ? grade.toStringAsFixed(0) : '-',
            style: TextStyle(
              fontSize: 15,
              fontWeight: hasGrade ? FontWeight.bold : FontWeight.normal,
              color: hasGrade ? _getGradeColor(grade) : Colors.grey[400],
            ),
          ),
        ),
      ),
    );
  }

  DataCell _buildAvgCell(double? avg, {bool isFinal = false}) {
    return DataCell(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: avg != null 
              ? _getGradeColor(avg).withValues(alpha: isFinal ? 0.2 : 0.1)
              : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: isFinal ? Border.all(color: _getGradeColor(avg ?? 0).withValues(alpha: 0.3)) : null,
        ),
        child: Text(
          avg != null ? avg.toStringAsFixed(2) : '-',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: avg != null ? _getGradeColor(avg) : Colors.grey[500],
          ),
        ),
      ),
    );
  }

  Color _getGradeColor(double grade) {
    if (grade >= 90) return HexColor("#1e824c"); // Green
    if (grade >= 85) return HexColor("#0F4C7F"); // Blue
    if (grade >= 75) return HexColor("#d4af37"); // Gold
    return HexColor("#e63946"); // Red
  }
}
