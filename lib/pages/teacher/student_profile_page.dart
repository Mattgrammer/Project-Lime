import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/student.dart';
import '../../widgets/guide_pointer.dart';
import '../../utils/notification_helper.dart';
import '../../services/fcm_service.dart';
import 'dart:convert';
import 'dart:async';

class StudentProfilePage extends StatefulWidget {
  final Student student;
  final String? sectionName;
  final Function(String subject, String quarter, double? grade) onUpdate;
  final VoidCallback? onAddSubject;
  final bool startGradeTour;

  const StudentProfilePage({
    super.key,
    required this.student,
    this.sectionName,
    required this.onUpdate,
    this.onAddSubject,
    this.startGradeTour = false,
  });

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> {
  late Map<String, Map<String, double>> _grades;
  bool _isAdviser = false;
  Set<String> _mySubjects = {};
  bool _isLoadingPermissions = true;
  Map<String, dynamic> _releaseDates = {};
  List<String> _allSubjects = [];
  Map<String, int> _subjectSemesters = {};
  StreamSubscription? _gradesSub;

  @override
  void initState() {
    super.initState();
    _grades = widget.student.grades.map((k, v) => MapEntry(k, Map<String, double>.from(v)));
    _loadPermissions();
    _listenToGradeRelease();
    _listenToGrades();
  }

  @override
  void dispose() {
    _gradesSub?.cancel();
    super.dispose();
  }

  final GlobalKey _dialogInputKey = GlobalKey();
  final GlobalKey _tableContainerKey = GlobalKey();
  final GlobalKey _firstAvgCellKey = GlobalKey(); // Key for Average Update tutorial
  final GlobalKey _gpaKey = GlobalKey();
  final GlobalKey _pillsKey = GlobalKey(); // Key for focusing on the badges
  final GlobalKey _firstGradeCellKey = GlobalKey();
  final GlobalKey _avgColumnKey = GlobalKey();
  
  // Tutorial state
  bool _isTourInputStep = false;
  bool _tourInputComplete = false;

  void _startGradeTour() {
    GuidePointer.show(
      context,
      steps: [
        GuideStep(
          targetKey: _tableContainerKey, 
          title: "Step 2: Grade Table", 
          content: "This is the quarterly grades table. Each row is a subject, and columns show grades for each quarter plus the average."
        ),
        GuideStep(
          targetKey: _pillsKey, 
          title: "Step 3: Averages and GPA", 
          content: "These badges show the calculated averages (Semester & Final). They update automatically as you enter grades below."
        ),
        GuideStep(
          targetKey: _firstGradeCellKey, 
          title: "Step 4: Input a Grade", 
          content: "Tap this cell to input a grade. Try entering '90' to see how it updates!",
          hideButton: true,
          isBlocking: true,
        ),
      ],
      totalStepsOverride: 5, // Expanded to 5 steps for better flow
      initialStepOffset: 1, // Start at Tip 2
      onComplete: () {
        // After Step 4 (tap cell), set flag for input validation
        if (mounted) {
          setState(() => _isTourInputStep = true);
        }
      },
    );
  }
  

  Future<void> _loadPermissions() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingPermissions = false);
      return;
    }
    
    try {
      final firestore = FirebaseFirestore.instance;

      if (widget.sectionName == null || widget.sectionName!.isEmpty) {
        if (mounted) setState(() => _isLoadingPermissions = false);
        return;
      }

      // Handle Tutorial Mode
      if (widget.sectionName == "[TUTORIAL] Demo Class") {
        if (mounted) {
          setState(() {
            _isAdviser = true;
            _mySubjects = {'Math_1', 'Math_2', 'Science_1', 'Science_2'};
            _allSubjects = ['Math', 'Science', 'English', 'Filipino', 'History', 'PE', 'Arts', 'Values'];
            _subjectSemesters = {
              'Math': 1, 'Science': 1, 'English': 1, 'Filipino': 1, 
              'History': 1, 'PE': 1, 'Arts': 1, 'Values': 1
            };
            _isLoadingPermissions = false;
          });
          if (widget.startGradeTour) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _startGradeTour());
          }
        }
        return;
      }

      final sectionDoc = await firestore.collection('sections').doc(widget.sectionName).get();
      
      final Set<String> mySubs = {};
      final Set<String> subjects = {};
      final Map<String, int> subSems = {};
      String? adviserUid;

      if (sectionDoc.exists) {
        final data = sectionDoc.data()!;
        adviserUid = data['adviserUid'] as String?;
        final List<dynamic> schedule = data['schedule'] as List<dynamic>? ?? [];
        final String myUid = user.uid;
        
        for (var item in schedule) {
          if (item is Map) {
            final String? sub = item['subject'] as String?;
            final int sem = item['semester'] as int? ?? 1;
            if (sub != null) {
              subjects.add(sub);
              subSems[sub] = sem;
              if (item['teacherUid'] == myUid) mySubs.add('${sub}_$sem');
            }
          }
        }
      }

      // Hydrate with existing grades even if section doesn't exist/didn't have them
      for (var sub in _grades.keys) {
        if (!subjects.contains(sub)) {
          subjects.add(sub);
          subSems[sub] = (_grades[sub]?.containsKey('q3') ?? false) ? 2 : 1;
        }
      }

      if (mounted) {
        setState(() {
          _isAdviser = (adviserUid == user.uid);
          _mySubjects = mySubs;
          _allSubjects = subjects.toList()..sort();
          _subjectSemesters = subSems;
          _isLoadingPermissions = false;
        });
        if (widget.startGradeTour) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _startGradeTour());
        }
      }
    } catch (e) {
      debugPrint("Error loading permissions: $e");
      if (mounted) setState(() => _isLoadingPermissions = false);
    }
  }

  void _listenToGradeRelease() {
    FirebaseFirestore.instance.collection('app_config').doc('grades').snapshots().listen((snap) {
      if (snap.exists && mounted) {
        setState(() => _releaseDates = snap.data()!['releaseDates'] as Map<String, dynamic>? ?? {});
      }
    });
  }

  void _listenToGrades() {
    if (widget.sectionName == null || widget.student.uid == null || widget.sectionName == "[TUTORIAL] Demo Class") return;
    
    _gradesSub?.cancel();
    _gradesSub = FirebaseFirestore.instance
        .collection('sections')
        .doc(widget.sectionName)
        .collection('studentGrades')
        .doc(widget.student.uid)
        .snapshots()
        .listen((snap) {
          if (snap.exists && mounted) {
            final data = snap.data();
            final rawGrades = data?['grades'] as Map?;
            if (rawGrades != null) {
              final Map<String, Map<String, double>> parsedGrades = {};
              rawGrades.forEach((sub, qMap) {
                if (qMap is Map) {
                  parsedGrades[sub.toString()] = qMap.map(
                    (k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0)
                  );
                }
              });
              setState(() {
                _grades = parsedGrades;
              });
            }
          }
        });
  }

  bool _isLocked(String q) {
    final qData = _releaseDates[q] as Map<String, dynamic>?;
    final ts = qData?['date'] as Timestamp?;
    return ts != null && ts.toDate().isAfter(DateTime.now());
  }

  bool _canEdit(String sub, String q) {
    // Both advisers and subject teachers must be assigned to the subject in the correct semester
    int sem = (q == 'q1' || q == 'q2') ? 1 : 2;
    return _mySubjects.contains('${sub}_$sem');
  }

  void _editGrade(String sub, String q) {
    if (!_canEdit(sub, q)) { NotificationHelper.showError(context, 'Not authorized'); return; }

    // Manual Tour Advance: If user taps cell while tour is active (Step 3), dismiss bubble and enable input mode
    if (widget.startGradeTour && !_isTourInputStep) {
      GuidePointer.dismiss();
      setState(() => _isTourInputStep = true);
    }

    final double current = _grades[sub]?[q] ?? 0;
    final controller = TextEditingController(text: current > 0 ? current.toString() : '');
    
    // Tutorial mode: pre-fill 90 hint
    final bool isTutorialStep = _isTourInputStep && !_tourInputComplete;
    
    showDialog(context: context, builder: (ctx) => AlertDialog(
      key: _dialogInputKey,
      title: Text(sub),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller, 
            keyboardType: TextInputType.number, 
            autofocus: true,
            decoration: isTutorialStep 
              ? const InputDecoration(hintText: 'Enter 90')
              : null,
          ),
          if (isTutorialStep)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Tutorial: Enter "90" and tap Save to continue.',
                style: TextStyle(fontSize: 13, color: HexColor("#116754"), fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.yellow[700],
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[700],
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: () {
            setState(() { if (_grades.containsKey(sub)) _grades[sub]?.remove(q); });
            widget.onUpdate(sub, q, 0);
            Navigator.pop(ctx);
          },
          child: const Text('Clear'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: HexColor("#116754"),
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: () {
            final text = controller.text.trim();
            if (text.isEmpty) {
              NotificationHelper.showError(context, 'Grade cannot be empty. Use "Clear" to remove or enter 0.');
              return;
            }

            final double? val = double.tryParse(text);
            if (val == null || val < 0 || val > 100) {
              NotificationHelper.showError(context, 'Please enter a valid grade between 0 and 100');
              return;
            }
            
            // Tutorial validation: must be 90
            if (isTutorialStep && val.round() != 90) {
              NotificationHelper.showError(context, 'Tutorial: Please enter exactly "90" to continue.');
              return;
            }

            setState(() { 
              _grades.putIfAbsent(sub, () => {}); 
              _grades[sub]![q] = val; 
            });
            widget.onUpdate(sub, q, val);
            Navigator.pop(ctx);
            
            // Tutorial: Show Step 5 (Averages) after valid input
            if (isTutorialStep) {
              setState(() => _tourInputComplete = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                 // No delay needed for smoother transition, or minimal delay
                 if (mounted) _showAverageUpdateExplanation();
              });
            } else if (widget.student.uid != null && !_isLocked(q)) {
              FCMService.sendNotification(
                recipientUid: widget.student.uid!, 
                title: 'Grade Updated', 
                body: '$sub updated', 
                data: {'type': 'grade_update'}
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    ));
  }


  double? _calculateSubjectAvg(String sub, {int? sem}) {
    final Map<String, double>? qs = _grades[sub];
    if (qs == null) return null;
    final List<double> vals = [];
    if (sem == 1) { 
      if ((qs['q1'] ?? 0) > 0) vals.add(qs['q1']!); 
      if ((qs['q2'] ?? 0) > 0) vals.add(qs['q2']!); 
    } else if (sem == 2) { 
      if ((qs['q3'] ?? 0) > 0) vals.add(qs['q3']!); 
      if ((qs['q4'] ?? 0) > 0) vals.add(qs['q4']!); 
    } else { 
      for (var v in qs.values) { if (v > 0) vals.add(v); } 
    }
    return vals.isEmpty ? null : vals.reduce((a, b) => a + b) / vals.length;
  }

  double? _calculateOverallAvg() {
    if (_grades.isEmpty) return null;
    final List<double> avgs = _grades.keys.map((s) => _calculateSubjectAvg(s)).whereType<double>().toList();
    return avgs.isEmpty ? null : avgs.reduce((a, b) => a + b) / avgs.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: HexColor("#116754"),
        foregroundColor: Colors.white,
        title: Text(widget.student.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoadingPermissions
          ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildInfoSection(key: _gpaKey),
                  const SizedBox(height: 24),
                  _buildQuarterlyGradesTitle(),
                  const SizedBox(height: 20),
                  Container(
                    key: _tableContainerKey,
                    child: _buildSemesterBlock(1),
                  ),
                  const SizedBox(height: 28),
                  _buildSemesterBlock(2),

                  const SizedBox(height: 28),
                  _buildOverallAverage(),
                  const SizedBox(height: 32),
                ],
              ),

    );
  }


  Widget _buildInfoSection({Key? key}) {
    final double? gpa = _calculateOverallAvg();
    final double? sem1Avg = _calculateSemesterAvg(1);
    final double? sem2Avg = _calculateSemesterAvg(2);
    
    return Container(
      key: key,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[400]!, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: CircleAvatar(
              radius: 40, // Increased from 30
              backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
              backgroundImage: widget.student.profileImageThumbnail != null
                  ? MemoryImage(base64Decode(widget.student.profileImageThumbnail!))
                  : null,
              child: widget.student.profileImageThumbnail == null
                  ? Icon(Icons.person, color: HexColor("#116754"), size: 40) // Increased icon size
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.student.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                if (widget.sectionName != null)
                  Text('${widget.student.studentId.isNotEmpty ? "${widget.student.studentId} - " : ""}${widget.sectionName}', 
                       style: TextStyle(fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  key: _pillsKey,
                  spacing: 8,
                  children: [
                    if (sem2Avg != null) 
                      _buildAvgPill('Sem 2: ${sem2Avg.round()}')
                    else if (sem1Avg != null)
                      _buildAvgPill('Sem 1: ${sem1Avg.round()}'),
                    if (gpa != null) _buildAvgPill('Final: ${gpa.round()}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvgPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500)),
    );
  }

  double? _calculateSemesterAvg(int sem) {
    final subs = _allSubjects.where((s) => (_subjectSemesters[s] ?? 0) == sem).toList();
    if (subs.isEmpty) return null;
    final avgs = subs.map((s) => _calculateSubjectAvg(s, sem: sem)).whereType<double>().toList();
    return avgs.isEmpty ? null : avgs.reduce((a, b) => a + b) / avgs.length;
  }

  Widget _buildQuarterlyGradesTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quarterly Grades', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: HexColor("#116754"))),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.edit_note, size: 16, color: Colors.grey[500]),
            const SizedBox(width: 4),
            Text('Tap any cell to add or edit grades', style: TextStyle(fontSize: 15, color: Colors.grey[600], fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildSemesterBlock(int sem) {
    final List<String> subs = _allSubjects.where((s) => (_subjectSemesters[s] ?? 0) == sem).toList();
    if (subs.isEmpty && !_isAdviser) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: HexColor("#116754"), size: 18),
            const SizedBox(width: 8),
            Text(
              sem == 1 ? "1ST SEMESTER" : "2ND SEMESTER",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: HexColor("#116754"),
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Grid Table
        Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder.all(color: Colors.grey[400]!, width: 1.5),
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2),
            3: FlexColumnWidth(2),
          },
          children: [
            // Header Row
            TableRow(
              decoration: BoxDecoration(color: Colors.grey[100]),
              children: [
              _buildCell(const Text("SUBJECT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), alignLeft: true),
                _buildCell(Text(sem == 1 ? "1ST QTR" : "3RD QTR", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                _buildCell(Text(sem == 1 ? "2ND QTR" : "4TH QTR", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                _buildCell(const Text("AVG", key: null, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), key: (sem == 1) ? _avgColumnKey : null),
              ],
            ),
            // Data Rows
            ...subs.map((s) {
               final grades = _grades[s];
               final q1Key = sem == 1 ? 'q1' : 'q3';
               final q2Key = sem == 1 ? 'q2' : 'q4';
               final double? qA = grades?[q1Key];
               final double? qB = grades?[q2Key];
               final double? sAvg = _calculateSubjectAvg(s, sem: sem);
               
               final avgColors = sAvg != null ? _getGradeColors(sAvg) : null;

               return TableRow(
                 decoration: const BoxDecoration(color: Colors.white),
                 children: [
                   _buildCell(
                      Text(s.toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)), 
                      alignLeft: true
                   ),
                   _buildGradeButton(s, q1Key, qA, key: (sem == 1 && s == subs.first) ? _firstGradeCellKey : null),
                   _buildGradeButton(s, q2Key, qB),
                   _buildCell(
                     Text(
                       sAvg != null ? sAvg.round().toString() : '-',
                       style: TextStyle(
                         fontWeight: FontWeight.bold, 
                         color: avgColors != null ? avgColors['txt'] : Colors.black, 
                         fontSize: 16,
                       ),
                     ),
                     bgColor: avgColors?['bg'],
                     key: (sem == 1 && s == subs.first) ? _firstAvgCellKey : null,
                   ),
                 ],
               );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildCell(Widget child, {bool alignLeft = false, Color? bgColor, Key? key}) {
    return Container(
      key: key,
      height: 64,
      width: double.infinity,
      color: bgColor,
      padding: alignLeft ? const EdgeInsets.symmetric(horizontal: 16) : EdgeInsets.zero,
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: child,
    );
  }



  Widget _buildGradeButton(String sub, String q, double? g, {Key? key}) {
    final bool canEditSub = _canEdit(sub, q);
    final bool hasGrade = g != null && g > 0;

    if (hasGrade) {
      final colors = _getGradeColors(g);
      final Color bg = colors['bg']!;
      final Color txt = colors['txt']!;

      return SizedBox(
        key: key,
        width: double.infinity,
        height: 64,
        child: InkWell(
          onTap: canEditSub ? () => _editGrade(sub, q) : null,
          child: Container(
            decoration: BoxDecoration(color: bg),
            child: Center(
              child: Text(
                g.round().toString(),
                style: TextStyle(fontWeight: FontWeight.bold, color: txt, fontSize: 16),
              ),
            ),
          ),
        ),
      );
    }

    if (!canEditSub) {
      return Container(
        width: double.infinity,
        height: 64,
        alignment: Alignment.center,
        child: const Text('-', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
      );
    }

    return Container(
      key: key,
      width: double.infinity,
      height: 64,
      color: HexColor("#116754").withValues(alpha: 0.05),
      child: TextButton(
        onPressed: () => _editGrade(sub, q),
        style: TextButton.styleFrom(
          foregroundColor: HexColor("#116754"),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 20, color: HexColor("#116754")),
            const SizedBox(width: 8),
            Text('Add', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: HexColor("#116754"))),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallAverage() {
    final gpa = _calculateOverallAvg();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: HexColor("#116754").withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('OVERALL FINAL AVERAGE', style: TextStyle(fontWeight: FontWeight.bold, color: HexColor("#116754"), fontSize: 16)),
          Text(gpa != null ? gpa.round().toString() : '-', style: TextStyle(fontWeight: FontWeight.bold, color: HexColor("#116754"), fontSize: 18)),
        ],
      ),
    );
  }

  Map<String, Color> _getGradeColors(double g) {
    if (g <= 0) return {'bg': Colors.transparent, 'txt': Colors.black};
    if (g < 75) {
      return {'bg': Colors.red.withValues(alpha: 0.15), 'txt': Colors.red};
    } else if (g < 80) {
      return {'bg': Colors.yellow.withValues(alpha: 0.3), 'txt': Colors.yellow[900]!};
    } else if (g < 90) {
      return {'bg': Colors.blue.withValues(alpha: 0.15), 'txt': Colors.blue[700]!};
    } else {
      return {'bg': HexColor("#116754").withValues(alpha: 0.15), 'txt': HexColor("#116754")};
    }
  }

  void _showAverageUpdateExplanation() {
     WidgetsBinding.instance.addPostFrameCallback((_) {
      GuidePointer.show(
        context,
        steps: [
          GuideStep(
            targetKey: _firstAvgCellKey,
            title: "Step 5: Automatic Updates",
            content: "See? The average automatically updates whenever you input a grade.",
            buttonLabel: "Finish",
          ),
        ],
        totalStepsOverride: 5,
        initialStepOffset: 4,
        onComplete: () {},
      );
    });
  }
}
