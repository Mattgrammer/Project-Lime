import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'student_profile_page.dart';
import 'subject_teacher_page.dart';
import '../../models/student.dart';
import '../../widgets/lime_dropdown.dart';
import '../../widgets/time_range_selector.dart';

import 'dart:async';

class SectionDetailPage extends StatefulWidget {
  final String sectionName;

  const SectionDetailPage({
    super.key,
    required this.sectionName,
  });

  @override
  State<SectionDetailPage> createState() => _SectionDetailPageState();
}

class _SectionDetailPageState extends State<SectionDetailPage> with SingleTickerProviderStateMixin {
  List<Student> _students = [];
  bool _isLoading = true;
  bool _isAdviser = false;
  String? _sectionAdviserUid;
  List<Map<String, dynamic>> _schedule = [];
  int _currentTabIndex = 0;
  TabController? _tabController;

  StreamSubscription? _studentsSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController!.addListener(() {
      if (!_tabController!.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController!.index;
        });
      }
    });
    _listenToStudents();
    _loadSchedule();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _studentsSubscription?.cancel();
    super.dispose();
  }

  void _listenToStudents() {
    final firestore = FirebaseFirestore.instance;
    _studentsSubscription?.cancel();
    
    _studentsSubscription = firestore
        .collection('students')
        .where('sections', arrayContains: widget.sectionName)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      
      final List<Student> loadedStudents = snapshot.docs.map((doc) {
        final data = doc.data();
        data['uid'] = doc.id;
        return Student.fromJson(data);
      }).toList();

      setState(() {
        _students = loadedStudents;
        _isLoading = false;
      });
    }, onError: (e) {
      debugPrint('Error listening to students: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }


  Future<void> _loadSchedule() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('sections').doc(widget.sectionName).get();
      if (doc.exists) {
        final data = doc.data()!;
        _sectionAdviserUid = data['adviserUid'] as String?;
        final user = FirebaseAuth.instance.currentUser;
        
        setState(() {
          _isAdviser = user != null && _sectionAdviserUid == user.uid;
          if (data['schedule'] != null) {
            final List<dynamic> schedList = data['schedule'];
            _schedule = schedList
                .map((m) => Map<String, dynamic>.from(m as Map))
                .toList();
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading schedule: $e');
    }
  }

  Future<void> _saveSchedule() async {
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore.collection('sections').doc(widget.sectionName).set({
        'schedule': _schedule,
      }, SetOptions(merge: true));

      // Synchronize with teachers' sections list
      final Set<String> currentTeacherUids = _schedule
          .map((s) => s['teacherUid'] as String?)
          .where((uid) => uid != null && uid.isNotEmpty)
          .cast<String>()
          .toSet();

      for (var uid in currentTeacherUids) {
        await firestore.collection('teachers').doc(uid).update({
          'sections': FieldValue.arrayUnion([widget.sectionName])
        });
      }
    } catch (e) {
      debugPrint('Error saving schedule: $e');
    }
  }

  Future<void> _updateQuarterlyGrade(String studentUid, String subject, String quarter, double? grade) async {
    if (studentUid.isEmpty) return;
    try {
      final firestore = FirebaseFirestore.instance;
      if (grade == null) {
        // Delete the quarter grade
        await firestore.collection('students').doc(studentUid).update({
          'grades.$subject.$quarter': FieldValue.delete(),
        });
      } else {
        // Atomic update of a specific quarter grade
        await firestore.collection('students').doc(studentUid).update({
          'grades.$subject.$quarter': grade,
        });
      }
    } catch (e) {
      debugPrint('Error saving student grade to Firestore: $e');
    }
  }

  Future<void> _showAddStudentDialog() async {
    final firestore = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;
    List<Map<String, dynamic>> unassignedStudents = [];

    // Load all teacher UIDs to exclude them from students list
    Set<String> teacherUids = {};
    try {
      final teachersSnapshot = await firestore.collection('teachers').get();
      teacherUids = teachersSnapshot.docs.map((doc) => doc.id).toSet();
    } catch (e) {
      debugPrint('Error loading teachers: $e');
    }

    // Load unassigned students (students who have no sections or empty sections)
    try {
      final studentsSnapshot = await firestore
          .collection('students')
          .where('detailsSubmitted', isEqualTo: true)
          .get();

      for (var doc in studentsSnapshot.docs) {
        final data = doc.data();
        final uid = doc.id;

        // Skip current user to prevent adding yourself
        if (user != null && uid == user.uid) continue;

        // Skip teachers/advisers
        if (teacherUids.contains(uid)) continue;

        // Check if student is assigned to any section
        final sections = data['sections'] as List<dynamic>?;
        if (sections == null || sections.isEmpty) {
          unassignedStudents.add({
            'uid': uid,
            'name': data['name'] as String? ?? 'Unknown',
            'email': data['email'] as String? ?? '',
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading unassigned students: $e');
    }

    if (!mounted) return;
    
    await showDialog(
      context: context,
      builder: (context) => _AddStudentDialog(
        unassignedStudents: unassignedStudents,
        sectionName: widget.sectionName,
        onStudentAdded: () {
          // No need to manually call _loadStudents, the listener handles it!
        },
        assignStudent: _assignStudentToSection,
      ),
    );
  }

  Future<void> _assignStudentToSection(String studentUid, String studentName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Prevent adding yourself as a student
    if (studentUid == user.uid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot add yourself as a student')),
        );
      }
      return;
    }

    // Persist assignment to Firestore
    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      
      // Update student's sections
      batch.update(firestore.collection('students').doc(studentUid), {
        'sections': FieldValue.arrayUnion([widget.sectionName])
      });
      
      // Update section's studentUids
      batch.update(firestore.collection('sections').doc(widget.sectionName), {
        'studentUids': FieldValue.arrayUnion([studentUid])
      });
      
      await batch.commit();
      
      // Add notification to student's inbox
      await _addInboxNotification(studentUid, widget.sectionName, user.uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$studentName assigned to ${widget.sectionName}')),
        );
      }
    } catch (e) {
      debugPrint('Error updating Firestore for assignment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to assign student. Try again.')),
        );
      }
    }
  }

  Future<void> _addInboxNotification(String studentUid, String sectionName, String teacherUid) async {
    try {
      final firestore = FirebaseFirestore.instance;
      String teacherName = 'Teacher';
      
      // Fetch teacher name from Firestore
      final teacherDoc = await firestore.collection('teachers').doc(teacherUid).get();
      if (teacherDoc.exists) {
        teacherName = teacherDoc.data()?['name'] ?? 'Teacher';
      }

      await firestore.collection('students').doc(studentUid).collection('inbox').add({
        'title': 'Section Assignment',
        'message': 'You have been assigned to section: $sectionName by $teacherName',
        'timestamp': DateTime.now().toIso8601String(),
        'read': false,
        'type': 'assignment',
        'senderUid': teacherUid,
        'sectionName': sectionName,
      });
    } catch (e) {
      debugPrint('Error sending notification to student: $e');
    }
  }

  Future<void> _addTeacherNotification(String teacherUid, String title, String message) async {
    try {
      await FirebaseFirestore.instance.collection('teachers').doc(teacherUid).collection('inbox').add({
        'title': title,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
        'read': false,
        'type': 'general',
      });
    } catch (e) {
      debugPrint('Error sending notification to teacher: $e');
    }
  }

  Future<void> _showManageScheduleDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manage Schedule'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_schedule.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('No subjects scheduled'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _schedule.length,
                    itemBuilder: (context, index) {
                      final s = _schedule[index];
                      return ListTile(
                        onTap: () {
                          final teacherUid = s['teacherUid'];
                          final teacherName = s['teacherName'] ?? '';
                          if (teacherUid != null && teacherUid.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SubjectTeacherPage(teacherUid: teacherUid, teacherName: teacherName),
                              ),
                            );
                          }
                        },
                        title: Text(s['subject'] ?? ''),
                        subtitle: Text('${s['day'] ?? ''} ${s['time'] ?? ''} — ${s['teacherName'] ?? ''}\nSemester: ${s['semester'] ?? '1'}'),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red[400]),
                          onPressed: () async {
                            final teacherUid = s['teacherUid'];
                            setState(() {
                              _schedule.removeAt(index);
                            });
                            await _saveSchedule();
                            if (teacherUid != null && teacherUid.isNotEmpty) {
                              await _addTeacherNotification(
                                teacherUid,
                                'Removed from Schedule',
                                'You have been removed as teacher for ${s['subject']} in section ${widget.sectionName}',
                              );
                            }
                            if (context.mounted) Navigator.pop(context);
                            // Reopen to refresh
                            await _showManageScheduleDialog();
                          },
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _showAddSubjectDialog();
                },
                style: ElevatedButton.styleFrom(backgroundColor: HexColor("#0F4C7F")),
                child: const Text('Add Subject'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _showAddSubjectDialog({int? initialSemester}) async {
    final TextEditingController subjectCtrl = TextEditingController();
    String timeRange = '';
    String? selectedTeacherUid;
    String? selectedTeacherName;
    String? selectedDay;
    int? selectedSemester = initialSemester;
    final currentUser = FirebaseAuth.instance.currentUser;

    final List<String> days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

    List<Map<String, String>> teachers = [];
    try {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore.collection('teachers').get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = (data['name'] as String?) ?? '';
        final displayName = (currentUser != null && doc.id == currentUser.uid) 
            ? '$name (you)' 
            : name;
        teachers.add({'uid': doc.id, 'name': name, 'displayName': displayName});
      }
    } catch (e) {
      debugPrint('Error loading teachers: $e');
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Subject'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: subjectCtrl, 
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LIMEDropdown<String>(
                    label: 'Day',
                    value: selectedDay,
                    items: days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (v) => setDialogState(() => selectedDay = v),
                  ),
                  const SizedBox(height: 16),
                  TimeRangeSelector(
                    label: 'Time Range',
                    initialValue: timeRange,
                    onTimeChanged: (v) => setDialogState(() => timeRange = v),
                  ),
                  const SizedBox(height: 16),
                  LIMEDropdown<String>(
                    label: 'Teacher',
                    value: selectedTeacherUid,
                    items: teachers.map((t) => DropdownMenuItem(value: t['uid'], child: Text(t['displayName'] ?? ''))).toList(),
                    onChanged: (v) {
                      setDialogState(() {
                        selectedTeacherUid = v;
                        selectedTeacherName = teachers.firstWhere((t) => t['uid'] == v)['name'];
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  LIMEDropdown<int>(
                    label: 'Semester',
                    value: selectedSemester,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1st Semester')),
                      DropdownMenuItem(value: 2, child: Text('2nd Semester')),
                    ],
                    onChanged: (v) => setDialogState(() => selectedSemester = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final subj = subjectCtrl.text.trim();
                if (subj.isEmpty || timeRange.isEmpty || selectedTeacherUid == null || selectedDay == null || selectedSemester == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
                  return;
                }
                
                final entry = {
                  'subject': subj,
                  'day': selectedDay,
                  'time': timeRange,
                  'teacherUid': selectedTeacherUid!,
                  'teacherName': selectedTeacherName ?? '',
                  'semester': selectedSemester,
                };
                setState(() {
                  _schedule.add(entry);
                });
                await _saveSchedule();
                if (currentUser == null || selectedTeacherUid != currentUser.uid) {
                  await _addTeacherNotification(
                    selectedTeacherUid!,
                    'Assigned as Subject Teacher',
                    'You have been assigned to teach $subj for section ${widget.sectionName} in the ${selectedSemester == 1 ? "1st" : "2nd"} semester',
                  );
                }
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              style: ElevatedButton.styleFrom(
                backgroundColor: HexColor("#0F4C7F"),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeStudent(int index) async {
    final student = _students[index];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Student'),
        content: Text('Are you sure you want to remove ${student.name} from this section?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final studentUid = student.uid;
              if (studentUid == null) return;

              try {
                final firestore = FirebaseFirestore.instance;
                final batch = firestore.batch();

                // 1. Remove student from section's studentUids
                batch.update(firestore.collection('sections').doc(widget.sectionName), {
                  'studentUids': FieldValue.arrayRemove([studentUid])
                });

                // 2. Remove section from student's sections
                batch.update(firestore.collection('students').doc(studentUid), {
                  'sections': FieldValue.arrayRemove([widget.sectionName])
                });

                // 3. Purge grades for subjects in this section
                final subjectsInRoom = _schedule
                    .whereType<Map<String, dynamic>>()
                    .map((item) => item['subject'] as String)
                    .toList();

                if (subjectsInRoom.isNotEmpty) {
                  final updates = <String, dynamic>{};
                  for (var subject in subjectsInRoom) {
                    updates['grades.$subject'] = FieldValue.delete();
                  }
                  batch.update(firestore.collection('students').doc(studentUid), updates);
                }

                await batch.commit();

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${student.name} removed from section and grades purged')),
                  );
                }
              } catch (e) {
                debugPrint('Error removing student and purging grades: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to remove student. Try again.')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = width > 900;

        if (!_isAdviser) {
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.sectionName),
              backgroundColor: HexColor("#0F4C7F"),
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: _buildStudentsTab(isDesktop: isDesktop),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.sectionName),
            backgroundColor: HexColor("#0F4C7F"),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.schedule),
                tooltip: 'Manage Schedule',
                onPressed: _showManageScheduleDialog,
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
              indicatorColor: Colors.white,
              tabs: const [
                Tab(text: 'Students', icon: Icon(Icons.people)),
                Tab(text: 'Teachers', icon: Icon(Icons.school)),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _currentTabIndex == 0 ? _showAddStudentDialog : _showAddSubjectDialog,
            backgroundColor: HexColor("#0F4C7F"),
            tooltip: _currentTabIndex == 0 ? 'Add Student' : 'Add Subject/Teacher',
            child: const Icon(Icons.add, color: Colors.white),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildStudentsTab(isDesktop: isDesktop),
              _buildTeachersTab(isDesktop: isDesktop),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudentsTab({required bool isDesktop}) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_students.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text('No students in this section', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
              const SizedBox(height: 8),
              Text('Tap the + button to add a student', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Students (${_students.length})',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: HexColor("#0F4C7F")),
            ),
            const SizedBox(height: 16),
            if (isDesktop)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 90,
                ),
                itemCount: _students.length,
                itemBuilder: (context, index) => _buildStudentItem(_students[index], index),
              )
            else
              Column(
                children: _students.asMap().entries.map((entry) => _buildStudentItem(entry.value, entry.key)).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentItem(Student student, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StudentProfilePage(
                student: student,
                sectionName: widget.sectionName,
                onUpdate: (subject, quarter, grade) {
                  if (student.uid != null) {
                    _updateQuarterlyGrade(student.uid!, subject, quarter, grade);
                  }
                },
                onAddSubject: () => _showAddSubjectDialog(),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: HexColor("#0F4C7F").withValues(alpha: 0.1),
                child: Icon(Icons.person, color: HexColor("#0F4C7F")),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(student.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    if (student.studentId.isNotEmpty)
                      Text('ID: ${student.studentId}', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                  ],
                ),
              ),
              if (_isAdviser)
                IconButton(
                  icon: Icon(Icons.remove_circle, color: Colors.red[400]),
                  onPressed: () => _removeStudent(index),
                  tooltip: 'Remove from section',
                ),
              Icon(Icons.arrow_forward_ios, color: HexColor("#0F4C7F"), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeachersTab({required bool isDesktop}) {
    // Group teachers by semester
    final Map<int, Set<String>> semTeachers = {1: {}, 2: {}};
    final Map<String, List<String>> teacherSubjects = {};
    final Map<String, String> teacherNames = {};

    for (var s in _schedule) {
      final uid = s['teacherUid'] as String?;
      final name = s['teacherName'] as String?;
      final subject = s['subject'] as String?;
      final sem = s['semester'] as int? ?? 1;
      
      if (uid != null && uid.isNotEmpty) {
        teacherNames[uid] = name ?? 'Unknown';
        semTeachers[sem]?.add(uid);
        if (subject != null) {
          teacherSubjects.putIfAbsent(uid, () => []).add('$subject (Sem $sem)');
        }
      }
    }

    // Ensure Adviser is always included (if not already in a semester)
    if (_sectionAdviserUid != null && !teacherNames.containsKey(_sectionAdviserUid)) {
      teacherNames[_sectionAdviserUid!] = 'Adviser'; // Fallback name
      semTeachers[1]?.add(_sectionAdviserUid!);
      teacherSubjects[_sectionAdviserUid!] = ['No subjects assigned'];
      
      FirebaseFirestore.instance.collection('sections').doc(widget.sectionName).get().then((doc) {
        if (doc.exists && mounted) {
           final name = doc.data()?['adviserName'] as String?;
           if (name != null) {
              setState(() {
                teacherNames[_sectionAdviserUid!] = name;
              });
           }
        }
      });
    }

    if (teacherNames.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.school, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text('No teachers assigned yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
              const SizedBox(height: 8),
              if (_isAdviser)
                const Text('Tap the schedule icon above to assign teachers', style: TextStyle(fontSize: 14, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final List<Widget> children = [];
    for (int semester in [1, 2]) {
      if (semTeachers[semester]!.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '${semester == 1 ? "1st" : "2nd"} Semester Teachers',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: HexColor("#0F4C7F")),
            ),
          ),
        );
        
        if (isDesktop) {
          children.add(
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 12,
                mainAxisExtent: 130,
              ),
              itemCount: semTeachers[semester]!.length,
              itemBuilder: (context, index) {
                final uid = semTeachers[semester]!.toList()[index];
                return _buildTeacherItem(uid, teacherNames[uid] ?? 'Unknown', teacherSubjects[uid] ?? []);
              },
            )
          );
        } else {
          children.addAll(semTeachers[semester]!.map((uid) {
            return _buildTeacherItem(uid, teacherNames[uid] ?? 'Unknown', teacherSubjects[uid] ?? []);
          }));
        }
      }
    }

    if (_isAdviser) {
      children.add(const SizedBox(height: 20));
      children.add(
        Center(
          child: ElevatedButton.icon(
            onPressed: _showManageScheduleDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add/Assign Teacher'),
            style: ElevatedButton.styleFrom(
              backgroundColor: HexColor("#0F4C7F"),
              foregroundColor: Colors.white,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildTeacherItem(String uid, String name, List<String> subjects) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SubjectTeacherPage(teacherUid: uid, teacherName: name),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: HexColor("#0F4C7F").withValues(alpha: 0.1),
                child: Icon(Icons.school, color: HexColor("#0F4C7F")),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (uid == _sectionAdviserUid ? HexColor("#0F4C7F") : Colors.green).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        uid == _sectionAdviserUid ? 'Adviser' : 'Subject Teacher',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: uid == _sectionAdviserUid ? HexColor("#0F4C7F") : Colors.green[700],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Subjects: ${subjects.join(", ")}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: HexColor("#0F4C7F"), size: 20),
            ],
          ),
      ),
      )
    );
  }
}

// Dialog widget for adding students
class _AddStudentDialog extends StatefulWidget {
  final List<Map<String, dynamic>> unassignedStudents;
  final String sectionName;
  final VoidCallback onStudentAdded;
  final Future<void> Function(String uid, String name) assignStudent;

  const _AddStudentDialog({
    required this.unassignedStudents,
    required this.sectionName,
    required this.onStudentAdded,
    required this.assignStudent,
  });

  @override
  State<_AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<_AddStudentDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredStudents = [];

  @override
  void initState() {
    super.initState();
    _filteredStudents = List.from(widget.unassignedStudents);
    _searchController.addListener(_filterStudents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterStudents() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredStudents = List.from(widget.unassignedStudents);
      } else {
        _filteredStudents = widget.unassignedStudents.where((student) {
          final name = (student['name'] as String).toLowerCase();
          final email = (student['email'] as String).toLowerCase();
          return name.contains(query) || email.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Student from Unassigned'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or email...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: _filteredStudents.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        widget.unassignedStudents.isEmpty
                            ? 'No unassigned students'
                            : 'No students found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredStudents.length,
                      itemBuilder: (context, index) {
                        final student = _filteredStudents[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: HexColor("#0F4C7F").withValues(alpha: 0.1),
                            child: Icon(Icons.person, color: HexColor("#0F4C7F")),
                          ),
                          title: Text(student['name'] as String),
                          subtitle: Text(student['email'] as String),
                            trailing: IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () async {
                              await widget.assignStudent(
                                student['uid'] as String,
                                student['name'] as String,
                              );
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              widget.onStudentAdded();
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}



