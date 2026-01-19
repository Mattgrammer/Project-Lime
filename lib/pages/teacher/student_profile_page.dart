import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/student.dart';
import '../../widgets/guide_pointer.dart';

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
    this.startGradeTour = false,
  });

  final bool startGradeTour;

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

  final GlobalKey _demoGradeCellKey = GlobalKey();
  final GlobalKey _gpaKey = GlobalKey();

  void _startGradeTour() {
    GuidePointer.show(
      context,
      steps: [
        GuideStep(
           targetKey: _demoGradeCellKey,
           title: "Step 2: The Grade Table",
           content: "This is the grade sheet. Subjects are grouped by semester, and you can see quarterly grades and averages here.",
           buttonLabel: "Got it! Next Tip",
           isBlocking: true, // NEW: Prevent clicking the cell during the info tip
        ),
        GuideStep(
          targetKey: _demoGradeCellKey,
          title: "Step 3: Try Entering a Grade",
          content: "Go ahead and try it! Tap this highlighted cell to open the grade entry dialog. The tour will advance automatically.",
          isBlocking: false,
        ),
        GuideStep(
           targetKey: _gpaKey,
           title: "Step 4: Real-time Averages",
           content: "Notice how the GPA updates automatically as soon as you save a grade. Perfect for tracking performance!",
           isBlocking: false,
        ),
        GuideStep(
           targetKey: _demoGradeCellKey,
           title: "Step 5: Subject Teacher Limits",
           content: "Final Tip: As a Subject Teacher, you can ONLY edit grades for your assigned subjects (Math & Science here). Others remain read-only.",
           buttonLabel: "Finish Tour",
           isBlocking: false,
        ),
      ],
      totalStepsOverride: 5,
      initialStepOffset: 1,
      onComplete: () {},
    );
  }

  Future<void> _loadPermissions() async {
    // Demo Mode Bypass
    if (widget.startGradeTour) {
      if (mounted) {
        setState(() {
          // SUBJECT TEACHER DEMO: Only Math and Science are editable
          _isAdviser = false;
          _mySubjects = {
            'Math_1', 'Science_1',  // Only these are editable!
            'Math_2', 'Science_2',
          };
          _allSubjects = ['Math', 'Science', 'English', 'Filipino', 'History', 'PE', 'Arts', 'Values'];
          _subjectSemesters = {
            'Math': 1, 'Science': 1, 'English': 1, 'Filipino': 1, 'History': 1, 'PE': 1, 'Arts': 1, 'Values': 1
          }; 
          // Note: Subject Teacher demo - only Math & Science editable, rest read-only.
          _isLoadingPermissions = false;
        });
        
        // Fix: Trigger tour after UI updates with demo data
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startGradeTour();
        });
      }
      return;
    }

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
        final mySubs = <String>{}; // subject_semester
        final subjects = <String>{};
        final subSems = <String, int>{};
        
        for (var item in schedule) {
          if (item is Map<String, dynamic>) {
            final sub = item['subject'] as String?;
            final sem = item['semester'] as int? ?? 1;
            final tUid = item['teacherUid'] as String?;
            
            if (sub != null) {
              subjects.add(sub);
              subSems[sub] = sem;
              final key = '${sub}_$sem';
              
              if (tUid == myUid) {
                mySubs.add(key);
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

  bool _canEditSubject(String subject, String quarter) {
    // Determine semester from quarter
    int semester = (quarter == 'q1' || quarter == 'q2') ? 1 : 2;
    final key = '${subject}_$semester';
    
    // Both advisers and subject teachers must be assigned to the subject in the correct semester
    if (_mySubjects.contains(key)) return true;
    
    return false;
  }

  void _showEditGradeDialog(String subject, String quarter) {
    if (!_canEditSubject(subject, quarter)) {
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
            child: Text('Cancel', style: TextStyle(color: HexColor("#116754"), fontWeight: FontWeight.bold)),
          ),
          if (currentGrade != null && currentGrade > 0)
            TextButton(
              onPressed: () {
                setState(() {
                  _grades[subject]?.remove(quarter);
                });
                widget.onUpdate(subject, quarter, null);
                Navigator.pop(context);
              },
              child: const Text('Clear', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: HexColor("#116754"),
              foregroundColor: Colors.white, // Ensure white text
            ),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
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
    final color = isPrimary ? HexColor("#116754") : Colors.grey[700]!;
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
    
    return LayoutBuilder(
      builder: (context, constraints) {


        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: HexColor("#116754"),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              widget.student.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            centerTitle: true,
          ),
          body: Column(
            children: [
            Expanded(
              child: _isLoadingPermissions 
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
                      backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                      child: Icon(
                        Icons.person,
                        size: 40,
                        color: HexColor("#116754"),
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                                  key: _gpaKey,
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
                  color: HexColor("#116754"),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (_isAdviser || _mySubjects.isNotEmpty) 
                      ? HexColor("#116754").withValues(alpha: 0.05) 
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      (_isAdviser || _mySubjects.isNotEmpty) ? Icons.edit_note : Icons.visibility_outlined,
                      size: 20,
                      color: (_isAdviser || _mySubjects.isNotEmpty) ? HexColor("#116754") : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isAdviser 
                          ? 'Tap any cell to add or edit grades' 
                          : _mySubjects.isNotEmpty 
                              ? 'Tap highlighted cells to manage grades'
                              : 'View-only mode: grades cannot be edited',
                      style: TextStyle(
                        color: (_isAdviser || _mySubjects.isNotEmpty) ? HexColor("#116754") : Colors.grey[600],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
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
                              color: HexColor("#116754").withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: HexColor("#116754").withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'OVERALL FINAL AVERAGE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: HexColor("#116754"),
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                Text(
                                  overallAvg.toStringAsFixed(2),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: HexColor("#116754"),
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
            ),
          ],
          ),
        );
      },
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
              Icon(Icons.calendar_today, size: 18, color: HexColor("#116754")),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: HexColor("#116754"),
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              if (widget.onAddSubject != null && _isAdviser)
                IconButton(
                  icon: const Icon(Icons.add_circle, size: 24),
                  color: HexColor("#116754"),
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
                      headingRowColor: WidgetStateProperty.all(HexColor("#116754").withValues(alpha: 0.05)),
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
                      DataColumn(
                        label: Expanded(
                          child: Center(
                            child: Text('${quarterLabels['q${quarters[0]}']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Center(
                            child: Text('${quarterLabels['q${quarters[1]}']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Center(
                            child: Text(
                              'S$semesterNum Avg', 
                              style: TextStyle(fontWeight: FontWeight.bold, color: HexColor("#1e824c")),
                            ),
                          ),
                        ),
                      ),
                    ],
                    rows: _allSubjects
                        .where((subject) => _subjectSemesters[subject] == semesterNum)
                        .map((subject) {
                      final semAvg = _calculateSubjectAverage(subject, semester: semesterNum);
                      final canEdit = _canEditSubject(subject, 'q${quarters[0]}'); // Permission is per-semester now, but check against a quarter within it
                      
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
                                  // Removed EDIT badge as per user request
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
    
    // Attach key to Math Q1 for tour
    final isDemoTarget = widget.startGradeTour && subject == 'Math' && q == 'q1';

    return DataCell(
      Center(
        child: InkWell(
          key: isDemoTarget ? _demoGradeCellKey : null,
          onTap: canEdit ? () => _showEditGradeDialog(subject, q) : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            constraints: const BoxConstraints(minWidth: 60),
            decoration: BoxDecoration(
              color: hasGrade 
                  ? _getGradeColor(grade).withValues(alpha: 0.1)
                  : (canEdit ? Colors.white : Colors.grey[50]),
              borderRadius: BorderRadius.circular(8),
              border: canEdit ? Border.all(
                color: hasGrade 
                  ? _getGradeColor(grade).withValues(alpha: 0.3)
                  : HexColor("#116754").withValues(alpha: 0.3),
                width: 1.5,
              ) : null,
              boxShadow: canEdit && !hasGrade ? [
                BoxShadow(
                  color: HexColor("#116754").withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (canEdit && !hasGrade)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.add_circle_outline, size: 14, color: HexColor("#116754")),
                  ),
                Text(
                  hasGrade ? grade.toStringAsFixed(0) : (canEdit ? 'Add' : '-'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: hasGrade ? FontWeight.bold : FontWeight.w700,
                    color: hasGrade ? _getGradeColor(grade) : (canEdit ? HexColor("#116754") : Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DataCell _buildAvgCell(double? avg, {bool isFinal = false}) {
    return DataCell(
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(minWidth: 60),
          decoration: BoxDecoration(
            color: avg != null 
                ? _getGradeColor(avg).withValues(alpha: isFinal ? 0.2 : 0.1)
                : Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
            border: isFinal ? Border.all(color: _getGradeColor(avg ?? 0).withValues(alpha: 0.3)) : null,
          ),
          child: Text(
            avg != null ? avg.toStringAsFixed(2) : '-',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: avg != null ? _getGradeColor(avg) : Colors.grey[500],
            ),
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
