import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'student_profile_page.dart';
import 'subject_teacher_page.dart';
import '../../models/student.dart';
import '../../widgets/lime_dropdown.dart';
import '../../widgets/time_range_selector.dart';
import '../../widgets/guide_pointer.dart';
import '../../services/fcm_service.dart';
import '../../constants/demo_images.dart';
import '../../utils/image_compression_utils.dart';

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

class SectionDetailPage extends StatefulWidget {
  final String sectionName;
  final bool startGradeTour;
  final bool startClassesTour;
  final bool startTeachersTour;

  const SectionDetailPage({
    super.key,
    required this.sectionName,
    this.startGradeTour = false,
    this.startClassesTour = false,
    this.startTeachersTour = false,
  });

  @override
  State<SectionDetailPage> createState() => _SectionDetailPageState();
}

class _SectionDetailPageState extends State<SectionDetailPage> with SingleTickerProviderStateMixin {
  List<Student> _students = [];
  bool _isLoading = true;
  bool _isAdviser = false;
  String? _sectionAdviserUid;
  String? _sectionAdviserName;
  List<Map<String, dynamic>> _schedule = [];
  int _currentTabIndex = 0;
  TabController? _tabController;

  StreamSubscription? _studentsSubscription;
  StreamSubscription? _sectionSubscription;
  StreamSubscription? _teachersSubscription;
  StreamSubscription? _gradesSubscription;
  Map<String, Map<String, dynamic>> _teacherProfiles = {};
  Map<String, Map<String, Map<String, double>>> _studentGradesMap = {}; // uid -> {subject: {quarter: grade}}

  // Section Profile Picture State
  String? _sectionImageUrl;
  String? _sectionImageThumbnail;
  Uint8List? _sectionThumbnailBytes;
  File? _tempSectionImage;
  bool _isSavingSectionImage = false;
  
  // Tour Keys
  final GlobalKey _tourStudentKey = GlobalKey();
  final GlobalKey _studentsHeaderKey = GlobalKey();
  final GlobalKey _emptyStateKey = GlobalKey();
  final GlobalKey _tabBarKey = GlobalKey();
  final GlobalKey _fabKey = GlobalKey();
  final GlobalKey _teachersTabKey = GlobalKey();
  
  // Dialog Tour Keys (Adding them now for future steps)
  final GlobalKey _dialogSubjectKey = GlobalKey();
  final GlobalKey _dialogTeacherKey = GlobalKey();
  final GlobalKey _dialogDaysKey = GlobalKey();
  final GlobalKey _dialogSemesterKey = GlobalKey();
  final GlobalKey _dialogAddButtonKey = GlobalKey();
  final GlobalKey _dialogTbaKey = GlobalKey(); // NEW: Key for TBA checkbox
  final GlobalKey _dialogTimeKey = GlobalKey();
  
  // Dialog Tour State
  bool _dialogTourStarted = false;
  bool _dialogTourReady = false;
  bool _isSubjectConfirmed = false;
  bool isTba = false;

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

    // Demo modes
    if (widget.startGradeTour) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _initializeTourData();
        });
      });
    } else if (widget.startClassesTour) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _initializeClassesTourData();
        });
      });
    } else if (widget.startTeachersTour) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _initializeTeachersTourData();
        });
      });
    } else {
      _listenToStudents();
      _listenToGrades();
      _listenToSection();
    }
  }

  void _initializeClassesTourData() {
    // Demo data for Classes Tour - EMPTY STATE to show how to add items
    setState(() {
      _students = []; // Start empty
      _sectionAdviserUid = 'demo_adviser';
      _sectionAdviserName = 'Jennifer Thompson (Adviser)';
      _isAdviser = true;
      _schedule = []; // Start empty
      _isLoading = false;
    });

    // Start tour after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _startClassesTour();
      });
    });
  }

  void _startClassesTour() {
    GuidePointer.show(
      context,
      steps: [
        GuideStep(
          targetKey: _emptyStateKey,
          title: "Welcome to Your Section!",
          content: "This is '[TUTORIAL] Demo Section - Grade 10-A'. It's currently empty, so let's set it up.",
          buttonLabel: "Let's Go!",
        ),
        GuideStep(
          targetKey: _fabKey, // Highlights the FAB
          title: "Step 1: Add Students",
          content: "Tap this + button to add students. You can search for existing students or create new ones.",
          hideButton: true, // Force user to tap the actual button
        ),
      ],
      totalStepsOverride: 7,
      onComplete: () {
        // This onComplete will trigger if user manually closes, 
        // but since we hide the button for the last step, 
        // the flow continues when they tap FAB.
      },
    );
  }


  @override
  void dispose() {
    GuidePointer.dismiss();
    _tabController?.dispose();
    _studentsSubscription?.cancel();
    _sectionSubscription?.cancel();
    _teachersSubscription?.cancel();
    _gradesSubscription?.cancel();
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
        
        // Merge grades from our separate grades map
        final grades = _studentGradesMap[doc.id] ?? {};
        data['grades'] = grades;
        
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

  void _listenToGrades() {
    final firestore = FirebaseFirestore.instance;
    _gradesSubscription?.cancel();
    
    _gradesSubscription = firestore
        .collection('sections')
        .doc(widget.sectionName)
        .collection('studentGrades')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      
      final Map<String, Map<String, Map<String, double>>> allGrades = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final rawGrades = data['grades'] as Map?;
        if (rawGrades != null) {
          final Map<String, Map<String, double>> studentGrades = {};
          rawGrades.forEach((subject, qMap) {
            if (qMap is Map) {
              studentGrades[subject.toString()] = qMap.map(
                (k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0)
              );
            }
          });
          allGrades[doc.id] = studentGrades;
        }
      }
      
      setState(() {
        _studentGradesMap = allGrades;
        // Update existing students with new grades
        _students = _students.map((s) {
          if (s.uid != null && allGrades.containsKey(s.uid)) {
            return Student(
              name: s.name,
              studentId: s.studentId,
              grades: allGrades[s.uid!]!,
              uid: s.uid,
              profileImageThumbnail: s.profileImageThumbnail,
              profileImageUrl: s.profileImageUrl,
            );
          }
          return s;
        }).toList();
      });
    });
  }

  void _listenToSection() {
    _sectionSubscription?.cancel();
    _sectionSubscription = FirebaseFirestore.instance
        .collection('sections')
        .doc(widget.sectionName)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || !mounted) return;
      
      final data = snapshot.data()!;
      _sectionAdviserUid = data['adviserUid'] as String?;
      _sectionImageThumbnail = data['sectionImageThumbnail'] as String?;
      _sectionImageUrl = data['sectionImageUrl'] as String?;

      if (_sectionImageThumbnail != null) {
        _sectionThumbnailBytes = base64Decode(_sectionImageThumbnail!);
      } else {
        _sectionThumbnailBytes = null;
      }

      final user = FirebaseAuth.instance.currentUser;
      
      if (data['adviserName'] != null) {
        _sectionAdviserName = data['adviserName'];
      }

      setState(() {
        _isAdviser = user != null && _sectionAdviserUid == user.uid;
        if (data['schedule'] != null) {
          final List<dynamic> schedList = data['schedule'];
          _schedule = schedList
              .map((m) => Map<String, dynamic>.from(m as Map))
              .toList();
        } else {
          _schedule = [];
        }

        // Fetch profiles for all teachers in the schedule + adviser
        final List<String> allTeacherUids = _schedule
            .map((s) => s['teacherUid'] as String?)
            .where((uid) => uid != null && uid.isNotEmpty)
            .cast<String>()
            .toList();
        if (_sectionAdviserUid != null) allTeacherUids.add(_sectionAdviserUid!);
        
        if (allTeacherUids.isNotEmpty) {
          _listenToTeachers(allTeacherUids.toSet().toList());
        }
      });
      
      // Fetch adviser name if missing
       if (_sectionAdviserName == null && _sectionAdviserUid != null) {
          FirebaseFirestore.instance.collection('teachers').doc(_sectionAdviserUid).get().then((tDoc) {
             if (tDoc.exists && mounted) {
               setState(() {
                 _sectionAdviserName = tDoc.data()?['name'] ?? 'Adviser';
               });
             }
          });
        }
    }, onError: (e) {
       debugPrint('Error listening to section: $e');
    });
  }

  bool get _isCurrentUserAdviser {
    final user = FirebaseAuth.instance.currentUser;
    return user != null && _sectionAdviserUid == user.uid;
  }

  Future<void> _pickSectionImage() async {
    if (!_isCurrentUserAdviser) return;

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (image != null) {
      File imageToUse = File(image.path);
      
      try {
        final CroppedFile? croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Section Image',
              toolbarColor: HexColor("#116754"),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
            ),
            IOSUiSettings(
              title: 'Crop Section Image',
              aspectRatioLockEnabled: true,
            ),
          ],
        );

        if (croppedFile != null) {
          imageToUse = File(croppedFile.path);
        }
      } catch (e) {
        debugPrint('ImageCropper failed (likely not supported on this platform): $e');
      }

      setState(() {
        _tempSectionImage = imageToUse;
      });
      await _saveSectionImage();
    }
  }

  Future<String> _generateSectionThumbnail(File imageFile) async {
    try {
      // Use the improved smart compression utility
      return await ImageCompressionUtils.smartCompressImage(imageFile);
    } catch (e) {
      debugPrint('Error generating section thumbnail: $e');
      rethrow;
    }
  }

  Future<void> _saveSectionImage() async {
    if (_tempSectionImage == null || !_isCurrentUserAdviser || widget.sectionName.contains('[TUTORIAL]')) return;

    setState(() {
      _isSavingSectionImage = true;
    });

    try {
      final String thumbnail = await _generateSectionThumbnail(_tempSectionImage!);
      
      if (thumbnail.isEmpty) {
         throw Exception('Failed to generate thumbnail');
      }

      await FirebaseFirestore.instance
          .collection('sections')
          .doc(widget.sectionName)
          .update({
        'sectionImageThumbnail': thumbnail,
        // We only store thumbnail for now as per current profile pic logic
      });

      if (mounted) {
        setState(() {
          // Optimistically update local state to prevent flicker
          _sectionImageThumbnail = thumbnail;
          _sectionThumbnailBytes = base64Decode(thumbnail);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Section image updated successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving section image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update section image: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSectionImage = false;
          _tempSectionImage = null; // Clear temp after save
        });
      }
    }
  }

  void _listenToTeachers(List<String> uids) {
    if (uids.isEmpty) {
      if (mounted) setState(() => _teacherProfiles = {});
      return;
    }

    _teachersSubscription?.cancel();
    _teachersSubscription = FirebaseFirestore.instance
        .collection('teachers')
        .where(FieldPath.documentId, whereIn: uids)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final Map<String, Map<String, dynamic>> updatedProfiles = {};
      for (var doc in snapshot.docs) {
        updatedProfiles[doc.id] = doc.data();
      }
      setState(() {
        _teacherProfiles = updatedProfiles;
      });
    });
  }

  Future<void> _saveSchedule() async {
    // DEMO MODE: Skip Firestore save
    if (widget.startClassesTour || widget.sectionName.contains('[TUTORIAL]')) return;

    try {
      final firestore = FirebaseFirestore.instance;
      
      // Calculate teacherUids from schedule
      final Set<String> currentTeacherUids = _schedule
          .map((s) => s['teacherUid'] as String?)
          .where((uid) => uid != null && uid.isNotEmpty)
          .cast<String>()
          .toSet();

      // Always include adviser
      if (_sectionAdviserUid != null) currentTeacherUids.add(_sectionAdviserUid!);

      // Update the section document with the teacherUids array
      await firestore.collection('sections').doc(widget.sectionName).set({
        'schedule': _schedule,
        'teacherUids': currentTeacherUids.toList(),
      }, SetOptions(merge: true));

      // Synchronize with individual teachers' sections list (for redundancy)
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
    
    // DEMO MODE: Skip Firestore operations entirely
    if (widget.startGradeTour || widget.sectionName.contains('[TUTORIAL]')) {
      debugPrint('[DEMO] Skipping Firestore save for $subject ($quarter)');
      return;
    }
    
    // Permission check
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    // Both advisers and subject teachers must be assigned to the subject in the correct semester
    int semester = (quarter == 'q1' || quarter == 'q2') ? 1 : 2;
    bool canEdit = _schedule.any((s) => 
      s['subject'] == subject && 
      s['semester'] == semester && 
      s['teacherUid'] == user.uid
    );
    
    if (!canEdit) {
      debugPrint('Permission denied for teacher ${user.uid} to update $subject ($quarter)');
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      // Grades are now stored in the sections collection
      final gradeRef = firestore
          .collection('sections')
          .doc(widget.sectionName)
          .collection('studentGrades')
          .doc(studentUid);

      if (grade == null) {
        await gradeRef.set({
          'grades': {
            subject: {
              quarter: FieldValue.delete(),
            }
          }
        }, SetOptions(merge: true));
      } else {
        await gradeRef.set({
          'grades': {
            subject: {
              quarter: grade,
            }
          }
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error saving student grade to sections collection: $e');
    }
  }

  Future<void> _showAddStudentDialog() async {
    // DEMO MODE: Show dummy unassigned students
    if (widget.startClassesTour) {
      GuidePointer.dismiss(); // Dismiss the "Tap +" tooltip

      final dummyStudents = [
        {'uid': 'demo_new_1', 'name': 'Chris Evans', 'email': 'student1@demo.com'},
        {'uid': 'demo_new_2', 'name': 'Robert Downey', 'email': 'student2@demo.com'},
        {'uid': 'demo_new_3', 'name': 'Scarlett Johansson', 'email': 'student3@demo.com'},
      ];
      
      await showDialog(
        context: context,
        builder: (context) => _AddStudentDialog(
          unassignedStudents: dummyStudents,
          sectionName: widget.sectionName,
          onStudentAdded: () {},
          assignStudent: _assignStudentToSection,
          isTourMode: true,
        ),
      );
      
      // Continue tour after dialog closes
      if (mounted) {
         // Populate dummy data to simulate addition (if not already done by dialog logic logic, but here we do it explicitly to be safe for the demo)
        if (_students.isEmpty) return; // Only proceed if a student was actually added

        // Populate dummy schedule for context (optional, can be removed if confusing)
         setState(() {
           if (_schedule.isEmpty) {
             _schedule = [
               {'subject': 'Math', 'teacherName': 'John Doe', 'teacherUid': 'demo_t1', 'day': 'Monday', 'time': '8:00 AM - 9:00 AM', 'semester': 1},
               {'subject': 'Science', 'teacherName': 'Jane Smith', 'teacherUid': 'demo_t2', 'day': 'Tuesday', 'time': '10:00 AM - 11:00 AM', 'semester': 1},
             ];
           }
        });

         WidgetsBinding.instance.addPostFrameCallback((_) {
           Future.delayed(const Duration(milliseconds: 500), () {
             if (!mounted) return;
             GuidePointer.show(
                context,
                steps: [
                   GuideStep(
                      targetKey: _tourStudentKey,
                      title: "Step 2: Assign Student",
                      content: "The student has been added. You can tap them to manage their personal grades.",
                      buttonLabel: "Go to Grades Tutorial",
                   ),
                ],
                totalStepsOverride: 7,
                initialStepOffset: 2,
                onComplete: () {
                  _redirectToGradeTour();
                },
             );
           });
         });
      }
      return;
    }

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
            'profileImageThumbnail': data['profileImageThumbnail'] as String?,
            'profileImageUrl': data['profileImageUrl'] as String?,
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
    if (user == null && !widget.startClassesTour) return; // Allow null user in demo mode

    // DEMO MODE: Simulate adding student
    if (widget.startClassesTour || widget.sectionName.contains('[TUTORIAL]')) {
      if (!mounted) return;
      setState(() {
        _students.add(Student(
          uid: studentUid,
          name: studentName,
          studentId: '', // Dummy ID
          grades: {},
        ));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$studentName assigned to Demo Section')),
      );
      return;
    }

    // Prevent adding yourself as a student
    if (studentUid == user!.uid) {
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

      // NEW: Trigger Push Notification
      FCMService.sendNotification(
        recipientUid: studentUid,
        title: 'New Section Assignment',
        body: 'You have been added to $sectionName by $teacherName.',
        data: {'type': 'assignment', 'section': sectionName},
      );
    } catch (e) {
      debugPrint('Error sending notification to student: $e');
    }
  }

  Future<void> _addTeacherNotification(String teacherUid, String title, String message) async {
    if (widget.startClassesTour || widget.sectionName.contains('[TUTORIAL]')) return; // Skip in demo mode
    try {
      await FirebaseFirestore.instance.collection('teachers').doc(teacherUid).collection('inbox').add({
        'title': title,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
        'read': false,
        'type': 'general',
      });

      // NEW: Trigger Push Notification
      FCMService.sendNotification(
        recipientUid: teacherUid,
        title: title,
        body: message,
        data: {'type': 'subject_assignment'},
      );
    } catch (e) {
      debugPrint('Error sending notification to teacher: $e');
    }
  }

  Future<void> _showManageScheduleDialog() async {
    // Group schedule by subject + teacher
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (int i = 0; i < _schedule.length; i++) {
      final s = _schedule[i];
      final key = '${s['subject']}|${s['teacherUid']}|${s['teacherName']}|${s['semester']}';
      grouped.putIfAbsent(key, () => []).add({...s, '_index': i});
    }

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                      itemCount: grouped.length,
                      itemBuilder: (context, groupIndex) {
                        final entry = grouped.entries.elementAt(groupIndex);
                        final parts = entry.key.split('|');
                        final subject = parts[0];
                        final teacherUid = parts[1];
                        final teacherName = parts[2];
                        final semester = parts[3];
                        final slots = entry.value;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Subject header
                                InkWell(
                                  onTap: () {
                                    if (teacherUid.isNotEmpty) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => SubjectTeacherPage(teacherUid: teacherUid, teacherName: teacherName),
                                        ),
                                      );
                                    }
                                  },
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        subject,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        '$teacherName • Semester $semester',
                                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 16),
                                // Time slots
                                ...slots.map((slot) {
                                  final scheduleIndex = slot['_index'] as int;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Icon(Icons.schedule, size: 16, color: HexColor("#116754")),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            slot['time'] == 'TBA' ? 'TBA' : '${slot['day'] ?? ''} ${slot['time'] ?? ''}',
                                            style: TextStyle(fontSize: 14, color: HexColor("#116754")),
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.close, size: 18, color: Colors.red[400]),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () async {
                                            final removedSlot = _schedule[scheduleIndex];
                                            setState(() {
                                              _schedule.removeAt(scheduleIndex);
                                            });
                                            await _saveSchedule();
                                            
                                            final uid = removedSlot['teacherUid'];
                                            if (uid != null && uid.isNotEmpty) {
                                              await _addTeacherNotification(
                                                uid,
                                                'Schedule Updated',
                                                'A time slot for ${removedSlot['subject']} (${removedSlot['day']}) was removed from section ${widget.sectionName}',
                                              );
                                            }
                                            if (context.mounted) Navigator.pop(context);
                                            await _showManageScheduleDialog();
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HexColor("#116754"),
                    foregroundColor: Colors.white, // Fix contrast
                  ),
                  child: const Text('Add Subject', style: TextStyle(fontWeight: FontWeight.bold)), // Bold white
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: Text('Close', style: TextStyle(color: HexColor("#116754"), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchTeachers() async {
    final List<Map<String, dynamic>> teachers = [];
    final currentUser = FirebaseAuth.instance.currentUser;

    if (widget.startClassesTour || widget.startTeachersTour) {
      return [
        {'uid': 'demo_t1', 'name': 'John Smith', 'displayName': 'John Smith (Math)'},
        {'uid': 'demo_t2', 'name': 'Emily Brown', 'displayName': 'Emily Brown (Science)'},
        {'uid': 'demo_t3', 'name': 'Robert Garcia', 'displayName': 'Robert Garcia (English)'},
      ];
    }

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
    return teachers;
  }


  Future<void> _showAddSubjectDialog({String? initialTeacherUid, String? initialTeacherName, String? editSubject, String? editTeacherUid, int? editSemester}) async {
    final teachers = await _fetchTeachers();
    final TextEditingController subjectCtrl = TextEditingController();
    
    String? selectedTeacherUid = editTeacherUid ?? initialTeacherUid;
    String? selectedTeacherName = editTeacherUid != null 
        ? teachers.firstWhere((t) => t['uid'] == editTeacherUid, orElse: () => {'name': ''})['name']
        : initialTeacherName;
        
    int? selectedSemester = editSemester ?? 1; // Default to 1st sem
    
    // Map of Day -> Time Range String (e.g. 'Monday': '8:00 AM - 9:00 AM')
    final Map<String, String> dayTimeMap = {};
    bool isTba = false;

    // Pre-fill data if editing
    if (editSubject != null && editSemester != null && editTeacherUid != null) {
        subjectCtrl.text = editSubject;
        // Find existing schedule entries
        final entries = _schedule.where((s) => 
            s['subject'] == editSubject && 
            s['semester'] == editSemester &&
            s['teacherUid'] == editTeacherUid
        ).toList();

        if (entries.isNotEmpty) {
            final first = entries.first;
            // Check TBA
            if (first['day'] == 'TBA' || first['time'] == 'TBA') {
                isTba = true;
            } else {
                for (var e in entries) {
                    if (e['day'] != null && e['time'] != null) {
                        dayTimeMap[e['day']] = e['time'];
                    }
                }
            }
        }
    }
    final currentUser = FirebaseAuth.instance.currentUser;

    final List<String> days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

    // List<Map<String, String>> teachers = []; // This line is now redundant as teachers are fetched above
    // if (widget.startClassesTour || widget.startTeachersTour) { // This block is now redundant
    //   teachers = [
    //     {'uid': 'demo_t1', 'name': 'John Smith', 'displayName': 'John Smith (Math)'},
    //     {'uid': 'demo_t2', 'name': 'Emily Brown', 'displayName': 'Emily Brown (Science)'},
    //     {'uid': 'demo_t3', 'name': 'Robert Garcia', 'displayName': 'Robert Garcia (English)'},
    //   ];
    // } else {
    //   try {
    //     final firestore = FirebaseFirestore.instance;
    //     final snapshot = await firestore.collection('teachers').get();
    //     for (var doc in snapshot.docs) {
    //       final data = doc.data();
    //       final name = (data['name'] as String?) ?? '';
    //       final displayName = (currentUser != null && doc.id == currentUser.uid) 
    //           ? '$name (you)' 
    //           : name;
    //       teachers.add({'uid': doc.id, 'name': name, 'displayName': displayName});
    //     }
    //   } catch (e) {
    //     debugPrint('Error loading teachers: $e');
    //   }
    // }

    if (!mounted) return;
    
    // Reset flags
    _dialogTourStarted = false;
    _dialogTourReady = false;
    _isSubjectConfirmed = false;
    
    await showDialog(
      context: context,
      builder: (dialogContext) {
        if (widget.startTeachersTour && !_dialogTourStarted) {
          _dialogTourStarted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
             _startAddSubjectDialogTour(dialogContext);
          });
        }

        // Initialize state if editing
        // if (editSubject != null) { // This block is now handled at the top
        //   subjectCtrl.text = editSubject;
        // }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            
            return AlertDialog(
          title: Text(editSubject != null ? 'Edit Subject' : 'Add Subject'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   TextField(
                     key: _dialogSubjectKey,
                     controller: subjectCtrl,
                     textCapitalization: TextCapitalization.characters,
                     autofocus: widget.startTeachersTour,
                     onSubmitted: (val) {
                       if (widget.startTeachersTour) {
                         if (!_dialogTourReady) return;
                         
                         // Only advance if MATH
                         if (val.trim().toUpperCase() == 'MATH') {
                            if (!_isSubjectConfirmed) {
                                _isSubjectConfirmed = true;
                                GuidePointer.nextFor(_dialogSubjectKey);
                            }
                         } else {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Type "MATH" and press Enter to continue tour'))
                            );
                         }
                       }
                     },
                     decoration: const InputDecoration(
                       labelText: 'Subject',
                       border: OutlineInputBorder(),
                       hintText: 'e.g. MATH',
                     ),
                   ),
                   const SizedBox(height: 16),
                   LIMEDropdown<String>(
                     key: _dialogTeacherKey,
                     label: 'Teacher',
                     value: selectedTeacherUid,
                     items: teachers.map((t) => DropdownMenuItem<String>(value: t['uid'] as String, child: Text(t['displayName'] as String? ?? ''))).toList(),
                      onChanged: (v) {
                        setDialogState(() {
                          selectedTeacherUid = v;
                          selectedTeacherName = teachers.firstWhere((t) => t['uid'] == v)['name'];
                          
                          if (widget.startTeachersTour) {
                            if (v == 'demo_t1') {
                                GuidePointer.nextFor(_dialogTeacherKey);
                            }
                          }
                        });
                      },
                   ),
                  const SizedBox(height: 16),
                   // TBA Checkbox
                   CheckboxListTile(
                     key: _dialogTbaKey,
                     title: const Text('Time To Be Announced (TBA)'),
                     subtitle: const Text('Check this if the schedule is not yet finalized'),
                     value: isTba,
                     onChanged: (checked) {
                       setDialogState(() {
                         isTba = checked ?? false;
                         if (isTba) {
                           // Clear day/time selections when TBA is checked
                           dayTimeMap.clear();
                         }
                         if (widget.startTeachersTour && checked == true) {
                            GuidePointer.nextFor(_dialogTbaKey);
                         }
                       });
                     },
                     activeColor: HexColor("#116754"),
                   ),
                   const SizedBox(height: 16),
                   Column(
                     key: _dialogDaysKey,
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Text(
                         'Select Days & Times', 
                         style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                       ),
                       const SizedBox(height: 8),
                       ...days.map((day) {
                         final isSelected = dayTimeMap.containsKey(day);
                         return Padding(
                           padding: const EdgeInsets.only(bottom: 8),
                           child: Row(
                             children: [
                               SizedBox(
                                 width: 24,
                                 child: Checkbox(
                                   value: isSelected,
                                   onChanged: (checked) {
                                     setDialogState(() {
                                       if (checked == true) {
                                         dayTimeMap[day] = '';
                                         // Auto advance on first day check for tour
                                         if (widget.startTeachersTour && dayTimeMap.length == 1) {
                                            GuidePointer.nextFor(_dialogDaysKey);
                                         }
                                       } else {
                                         dayTimeMap.remove(day);
                                       }
                                     });
                                   },
                                   activeColor: HexColor("#116754"),
                                 ),
                               ),
                               const SizedBox(width: 8),
                               SizedBox(
                                 width: 80,
                                 child: Text(day.substring(0, 3), style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                               ),
                               if (isSelected)
                                 Expanded(
                                   child: TimeRangeSelector(
                                     containerKey: (widget.startTeachersTour && dayTimeMap.containsKey(day)) ? _dialogTimeKey : null,
                                     label: '',
                                     initialValue: dayTimeMap[day] ?? '',
                                     onTimeChanged: (v) {
                                        setDialogState(() => dayTimeMap[day] = v);
                                        if (widget.startTeachersTour) {
                                           GuidePointer.nextFor(_dialogTimeKey);
                                        }
                                     },
                                   ),
                                 ),
                             ],
                           ),
                         );
                       }),
                     ],
                   ),
                  const SizedBox(height: 16),
                    LIMEDropdown<int>(
                     key: _dialogSemesterKey,
                     label: 'Semester',
                     value: selectedSemester,
                     items: const [
                       DropdownMenuItem(value: 1, child: Text('1st Semester')),
                       DropdownMenuItem(value: 2, child: Text('2nd Semester')),
                     ],
                     onChanged: (v) {
                       setDialogState(() => selectedSemester = v);
                       if (widget.startTeachersTour) GuidePointer.nextFor(_dialogSemesterKey);
                     },
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
              key: _dialogAddButtonKey,
              onPressed: () async {
                final subj = subjectCtrl.text.trim().toUpperCase();
                
                // Validate
                if (subj.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a subject name')));
                  return;
                }
                // Only validate day/time if not TBA
                if (!isTba) {
                  if (dayTimeMap.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one day or check TBA')));
                    return;
                  }
                  // Check all selected days have times
                  final missingTimes = dayTimeMap.entries.where((e) => e.value.isEmpty).map((e) => e.key).toList();
                  if (missingTimes.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please set time for: ${missingTimes.join(", ")}')));
                    return;
                  }
                }
                if (selectedTeacherUid == null || selectedSemester == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select teacher and semester')));
                  return;
                }
                
                
                setState(() {
                  // If editing, remove old entries first (this is a replace operation)
                  if (editSubject != null && editSemester != null) {
                      _schedule.removeWhere((s) => 
                          s['subject'] == editSubject && 
                          s['semester'] == editSemester &&
                          s['teacherUid'] == editTeacherUid
                      );
                  }

                  // Create schedule entries
                  if (isTba) {
                    // For TBA, create a single entry with 'TBA' as time
                    _schedule.add({
                      'subject': subj,
                      'day': 'TBA',
                      'time': 'TBA',
                      'teacherUid': selectedTeacherUid!,
                      'teacherName': selectedTeacherName ?? '',
                      'semester': selectedSemester,
                    });
                  } else {
                    // Create one entry per day with its unique time
                    for (var entry in dayTimeMap.entries) {
                      _schedule.add({
                        'subject': subj,
                        'day': entry.key,
                        'time': entry.value,
                        'teacherUid': selectedTeacherUid!,
                        'teacherName': selectedTeacherName ?? '',
                        'semester': selectedSemester,
                      });
                    }
                  }
                });
                
                if (!widget.startClassesTour && !widget.startTeachersTour) {
                    await _saveSchedule();
                    if (currentUser == null || selectedTeacherUid != currentUser.uid) {
                        if (!selectedTeacherUid!.startsWith('demo_')) {
                            await _addTeacherNotification(
                                selectedTeacherUid!,
                                'Assigned as Subject Teacher',
                                'You have been assigned to teach $subj for section ${widget.sectionName} in the ${selectedSemester == 1 ? "1st" : "2nd"} semester',
                            );
                        }
                    }
                }
                if (widget.startTeachersTour) {
                   GuidePointer.dismiss(); // Clean up tour immediately
                }
                
                if (!context.mounted) return;
                
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);

                if (widget.startTeachersTour) {
                   // Optional: Show success message for tour completion
                   messenger.showSnackBar(
                      const SnackBar(content: Text('Great job! You added a subject. Tour Complete!'))
                   );
                }
              },

              icon: Icon(editSubject != null ? Icons.save : Icons.add, size: 18),
              label: Text(editSubject != null ? 'Update' : 'Add', style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: HexColor("#116754"),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
            );
          },
        );
      },
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
            child: Text('Cancel', style: TextStyle(color: HexColor("#116754"), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () async {
              final studentUid = student.uid;
              if (studentUid == null) return;

              try {
                final firestore = FirebaseFirestore.instance;

                // Get subjects to remove
                final List<String> subjectsInRoom = _schedule
                    .where((item) => item['subject'] != null)
                    .map((item) => item['subject'] as String)
                    .toList();

                // 1. Remove student from section's studentUids
                await firestore.collection('sections').doc(widget.sectionName).update({
                  'studentUids': FieldValue.arrayRemove([studentUid])
                });

                // 2. Read student document, modify grades, and write back
                final studentDoc = await firestore.collection('students').doc(studentUid).get();
                if (studentDoc.exists) {
                  final data = studentDoc.data()!;
                  final grades = Map<String, dynamic>.from(data['grades'] ?? {});
                  
                  // Remove grades for subjects in this section
                  for (var subject in subjectsInRoom) {
                    grades.remove(subject);
                  }
                  
                  // Update student with cleaned grades and removed section
                  await firestore.collection('students').doc(studentUid).update({
                    'sections': FieldValue.arrayRemove([widget.sectionName]),
                    'grades': grades,
                  });
                }

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


  Future<void> _removeTeacherFromSection(String teacherUid, String teacherName) async {
    // Find all subjects taught by this teacher in ONLY this section
    final teacherSubjects = _schedule
        .where((s) => s['teacherUid'] == teacherUid)
        .map((s) => s['subject'] as String)
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Teacher from Section'),
        content: Text('Are you sure you want to remove $teacherName from ${widget.sectionName}?\n\n'
            'This will permanently delete all grades entered by this teacher for: ${teacherSubjects.join(", ")}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Remove & Wipe Data'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Remove teacher's subjects from section schedule
      final newSchedule = _schedule.where((s) => s['teacherUid'] != teacherUid).toList();
      await firestore.collection('sections').doc(widget.sectionName).update({
        'schedule': newSchedule
      });

      // 2. For each student, read their grades, remove subjects, and write back
      for (var student in _students) {
        if (student.uid != null) {
          final studentDoc = await firestore.collection('students').doc(student.uid).get();
          if (studentDoc.exists) {
            final data = studentDoc.data()!;
            final grades = Map<String, dynamic>.from(data['grades'] ?? {});
            
            // Remove grades for subjects taught by this teacher
            for (var subject in teacherSubjects) {
              grades.remove(subject);
            }
            
            await firestore.collection('students').doc(student.uid).update({
              'grades': grades,
            });
          }
        }
      }

      // 3. Remove this section from the teacher's sections list if they are not the adviser
      if (teacherUid != _sectionAdviserUid && !teacherUid.startsWith('demo_')) {
        await firestore.collection('teachers').doc(teacherUid).update({
          'sections': FieldValue.arrayRemove([widget.sectionName])
        });
      }

      setState(() {
        _schedule = newSchedule;
      });

      if (!teacherUid.startsWith('demo_')) {
          await _addTeacherNotification(
            teacherUid,
            'Removed from Section',
            'You have been removed from section ${widget.sectionName} and your subject assignments have been cleared.',
          );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$teacherName removed and data purged successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error removing teacher: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Failed to remove teacher: $e')),
        );
      }
    }
  }

  void _initializeTourData() {
    // 1. Listen to section data for context (adviser name etc)
    _listenToSection();
    
    // 2. FORCE dummy data only. Do not fetch real students.
    List<Student> dummyStudents = [
      Student(
        uid: 'demo_student',
        name: 'Bill Gates',
        studentId: '',
        profileImageThumbnail: billGatesBase64,
         grades: {
          // Semester 1 Subjects (Q1, Q2)
          'Math': {'q1': 0, 'q2': 92}, // Q1 is 0 to allow user input in tutorial
          'Science': {'q1': 88, 'q2': 89},
          'English': {'q1': 91, 'q2': 90},
          'Filipino': {'q1': 85, 'q2': 87},
          'History': {'q1': 89, 'q2': 91},
          'PE': {'q1': 95, 'q2': 96},
          'Arts': {'q1': 93, 'q2': 92},
          'Values': {'q1': 88, 'q2': 88},
        },
      )
    ];


    if (mounted) {
      setState(() {
        _students = dummyStudents;
        _isLoading = false;
      });
      
      // 3. Start the tour
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _startHighlightTour();
        });
      });
    }
  }
  
  void _redirectToGradeTour() {
     showDialog(
       context: context,
       barrierDismissible: false,
       builder: (context) => AlertDialog(
         title: const Text('Next Step: Grades'),
         content: const Text('You will now be redirected to the Grades Tutorial to learn how to manage student grades.'),
         actions: [
           TextButton(
             onPressed: () {
               Navigator.pop(context); // Close dialog
               Navigator.pushReplacement(
                 context,
                 MaterialPageRoute(
                   builder: (context) => const SectionDetailPage(
                     sectionName: "[TUTORIAL] Demo Class",
                     startGradeTour: true,
                   ),
                 ),
               );
             },
             child: const Text('Continue'),
           ),
         ],
       ),
     );
  }

  void _startHighlightTour() {
    GuidePointer.show(
      context,
      steps: [
        GuideStep(
          targetKey: _tourStudentKey,
          title: "Step 1: View Grades",
          content: "Tap the student's name to open their grade sheet. Let's try it with Bill Gates.",
          hideButton: true, // Allow user to tap the spotlighted student directly
          isBlocking: true,
        ),
      ],
      totalStepsOverride: 4, // Standalone 4-step Grades tour
      initialStepOffset: 0,
      onComplete: () {},
    );
  }


  void _initializeTeachersTourData() {
    setState(() {
      _students = [
         Student(uid: 'demo_s1', name: 'Chris Evans', studentId: '101', grades: {}),
      ];
      _sectionAdviserUid = 'demo_adviser';
      _sectionAdviserName = 'Jennifer Thompson (Adviser)';
      _isAdviser = true;
      _schedule = []; // Start empty
      _isLoading = false;
      _currentTabIndex = 1;
      _tabController?.index = 1;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _startTeachersTour();
      });
    });
  }

  void _startTeachersTour() {
    GuidePointer.show(
      context,
      steps: [
        GuideStep(
           targetKey: _fabKey,
           title: "Step 1: Add Subjects",
           content: "Tap this + button to add a new subject and assign a teacher. Try adding 'MATH'!",
           hideButton: true,
           isBlocking: false, // Non-blocking so they can tap FAB
        ),
      ],
      totalStepsOverride: 8,
      onComplete: () {},
    );
  }

  void _startAddSubjectDialogTour(BuildContext dialogContext) {
    if (!mounted) return;
    
    // Set flag so we know tour is ready for interaction
    _dialogTourReady = true;

    GuidePointer.show(
      dialogContext,
      steps: [
        GuideStep(
           targetKey: _dialogSubjectKey,
           title: "Step 2: Enter Subject Name",
           content: "Type 'MATH' and press Enter/Return on your keyboard to continue.",
           hideButton: true,
           isBlocking: true, // Block interaction outside, but allow TextField
        ),
        GuideStep(
           targetKey: _dialogTeacherKey,
           title: "Step 3: Assign Teacher",
           content: "Select 'John Smith' from the list.",
           hideButton: true,
           isBlocking: true,
        ),
        GuideStep(
           targetKey: _dialogTbaKey,
           title: "Step 3.5: Time To Be Announced",
           content: "You can check this box if the schedule is not yet finalized. Tap 'Next' to skip.",
           hideButton: false, // Allow skipping
           buttonLabel: "Next",
           isBlocking: false,
        ),
        GuideStep(
           targetKey: _dialogDaysKey,
           title: "Step 4: Set Day",
           content: "Check 'Monday' box to set the class day.",
           hideButton: true,
           isBlocking: false,
        ),
        GuideStep(
           targetKey: _dialogTimeKey,
           title: "Step 5: Set Time",
           content: "Tap here to set the class time.",
           hideButton: true,
           isBlocking: false,
        ),
        GuideStep(
           targetKey: _dialogSemesterKey,
           title: "Step 6: Select Semester",
           content: "Select '1st Semester'.",
           hideButton: true,
           isBlocking: true,
        ),
        GuideStep(
           targetKey: _dialogAddButtonKey,
           title: "Step 7: Finish",
           content: "Tap 'Add' to save the class.",
           hideButton: true, 
           isBlocking: false,
        ),
      ],
      totalStepsOverride: 7,
      initialStepOffset: 1, // Start at Step 2 (0-indexed 1)
      onComplete: () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = width > 900;


        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: HexColor("#116754"),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              widget.sectionName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            centerTitle: true,
            actions: [
              if (_isAdviser && !widget.startGradeTour) // Hide actions during tour
                 IconButton(
                  icon: const Icon(Icons.schedule),
                  tooltip: 'Manage Schedule',
                  onPressed: _showManageScheduleDialog,
                ),
            ],
            bottom: (_isAdviser && !widget.startGradeTour) || widget.startClassesTour
                ? TabBar(
                    key: _tabBarKey,
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    indicatorColor: Colors.white,
                    tabs: [
                      const Tab(text: 'Students', icon: Icon(Icons.people)),
                      Tab(
                        key: _teachersTabKey,
                        text: 'Teachers', 
                        icon: const Icon(Icons.school),
                      ),
                    ],
                  )
                : null,
          ),
          floatingActionButton: (_isAdviser && !widget.startGradeTour) || widget.startClassesTour || widget.startTeachersTour
              ? FloatingActionButton(
                  key: _fabKey,
                  onPressed: _currentTabIndex == 0 ? _showAddStudentDialog : _showAddSubjectDialog,
                  backgroundColor: HexColor("#116754"),
                  tooltip: _currentTabIndex == 0 ? 'Add Student' : 'Add Subject/Teacher',
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : null,
          body: (_isAdviser && !widget.startGradeTour) || widget.startClassesTour
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    _buildStudentsTab(isDesktop: isDesktop),
                    _buildTeachersTab(isDesktop: isDesktop),
                  ],
                )
              : _buildStudentsTab(isDesktop: isDesktop),
        );
      },
    );
  }

  Widget _buildSectionHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: HexColor("#116754").withValues(alpha: 0.05),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                  backgroundImage: _sectionThumbnailBytes != null
                      ? MemoryImage(_sectionThumbnailBytes!)
                      : (_sectionImageUrl != null
                          ? NetworkImage(_sectionImageUrl!)
                          : null) as ImageProvider?,
                  child: (_sectionThumbnailBytes == null && _sectionImageUrl == null)
                      ? Icon(Icons.class_, size: 50, color: HexColor("#116754"))
                      : null,
                ),
              ),
              if (_isCurrentUserAdviser)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickSectionImage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: HexColor("#116754"),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: _isSavingSectionImage
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.sectionName,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: HexColor("#116754"),
            ),
          ),
          if (_sectionAdviserName != null)
            Text(
              'Adviser: $_sectionAdviserName',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: HexColor("#116754"),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStudentsTab({required bool isDesktop}) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSectionHeader(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _students.isEmpty 
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No students in this section',
                          key: _emptyStateKey,
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text('Tap the + button to add a student', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      key: _studentsHeaderKey,
                      'Students (${_students.length})',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: HexColor("#116754")),
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
                          mainAxisExtent: 150,
                        ),
                        itemCount: _students.length,
                        itemBuilder: (context, index) => _buildStudentItem(_students[index], index, key: index == 0 ? _tourStudentKey : null),
                      )
                    else
                      Column(
                        children: _students.asMap().entries.map((entry) => _buildStudentItem(entry.value, entry.key, key: entry.key == 0 ? _tourStudentKey : null)).toList(),
                      ),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentItem(Student student, int index, {Key? key}) {
    return Container(
      key: key,
      child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          if (widget.startClassesTour) {
             _redirectToGradeTour();
             return;
          }

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
                onAddSubject: _isAdviser ? () => _showAddSubjectDialog() : null,
                startGradeTour: widget.startGradeTour, // Pass the tour flag
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


// ... inside _buildStudentItem ...
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2.0),
                ),
                child: CircleAvatar(
                  radius: 30, // Increased size
                  backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                  backgroundImage: student.profileImageThumbnail != null
                      ? MemoryImage(base64Decode(student.profileImageThumbnail!))
                      : (student.profileImageUrl != null
                          ? NetworkImage(student.profileImageUrl!)
                          : null) as ImageProvider?,
                  child: (student.profileImageThumbnail == null && student.profileImageUrl == null)
                      ? Icon(Icons.person, color: HexColor("#116754"), size: 30)
                      : null,
                ),

              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      student.name, 
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), 
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (student.studentId.isNotEmpty)
                      Text(
                        // If it contains " - ", likely our demo or formatted string, so show as is. 
                        // Otherwise prefix with ID if needed, or just show raw. User asked to "change ID to section".
                        // Assuming new format "12 - BILL GATES" should be shown as is.
                        student.studentId.contains(' - ') ? student.studentId : 'ID: ${student.studentId}', 
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                  ],
                ),
              ),
              if (_isAdviser)
                IconButton(
                  icon: Icon(Icons.remove_circle, color: Colors.red[400]),
                  onPressed: () => _removeStudent(index),
                  tooltip: 'Remove from section',
                ),
              Icon(Icons.arrow_forward_ios, color: HexColor("#116754"), size: 20),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildTeachersTab({required bool isDesktop}) {
    // Group teachers by semester
    final Map<int, Set<String>> semTeachers = {1: {}, 2: {}};
    // Map<TeacherUID, List<Map<String, dynamic>>>
    final Map<String, List<Map<String, dynamic>>> teacherStructuredSubjects = {}; 
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
          teacherStructuredSubjects.putIfAbsent(uid, () => []);
          final existing = teacherStructuredSubjects[uid]!.any((s) => s['subject'] == subject && s['semester'] == sem);
          if (!existing) {
            teacherStructuredSubjects[uid]!.add({'subject': subject, 'semester': sem});
          }
        }
      }
    }

    final List<Widget> children = [];

    // 1. ADVISER SECTION
    if (_sectionAdviserUid != null) {
       children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Adviser',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: HexColor("#116754")),
          ),
        ),
      );

      // Adviser's subjects from schedule
      // final adviserSubjectsList = (teacherSubjects[_sectionAdviserUid] ?? <String>{}).toList();
      children.add(_buildTeacherItem(
        _sectionAdviserUid!, 
        _sectionAdviserName ?? 'Adviser', 
        teacherStructuredSubjects[_sectionAdviserUid] ?? [],
        isAdviserSection: true
      ));
    }

    // 2. SEMESTER SECTIONS
    for (int semester in [1, 2]) {
      if (semTeachers[semester]!.isNotEmpty) {
        children.add(
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: true,
              iconColor: HexColor("#116754"),
              collapsedIconColor: HexColor("#116754"),
              trailing: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: HexColor("#116754").withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.expand_more, color: HexColor("#116754"), size: 24),
              ),
              title: Text(
                '${semester == 1 ? "1st" : "2nd"} Semester Teachers',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: HexColor("#116754")),
              ),
              children: [
                if (isDesktop)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 180,
                    ),
                    itemCount: semTeachers[semester]!.length,
                    itemBuilder: (context, index) {
                      final uid = semTeachers[semester]!.toList()[index];
                      final allSubjects = teacherStructuredSubjects[uid] ?? [];
                      final semesterSubjects = allSubjects.where((s) => s['semester'] == semester).toList();
                      return _buildTeacherItem(
                        uid, 
                        teacherNames[uid] ?? 'Unknown', 
                        semesterSubjects,
                        defaultSemester: semester,
                      );
                    },
                  )
                else
                  ...semTeachers[semester]!.map((uid) {
                    final allSubjects = teacherStructuredSubjects[uid] ?? [];
                    final semesterSubjects = allSubjects.where((s) => s['semester'] == semester).toList();
                    return Column(
                      children: [
                        _buildTeacherItem(
                          uid, 
                          teacherNames[uid] ?? 'Unknown', 
                          semesterSubjects,
                          defaultSemester: semester,
                        ),
                        const SizedBox(height: 12),
                      ],
                    );
                  }),
              ],
            ),
          ),
        );
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
              backgroundColor: HexColor("#116754"),
              foregroundColor: Colors.white,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSectionHeader(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: children.isEmpty && _sectionAdviserUid == null
              ? Center(
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
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherItem(String uid, String name, List<Map<String, dynamic>> subjects, {bool isAdviserSection = false, int? defaultSemester}) {
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
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2.0),
                ),
                child: CircleAvatar(
                  radius: 30, // Increased size
                  backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                  backgroundImage: _teacherProfiles[uid]?['profileImageThumbnail'] != null
                      ? MemoryImage(base64Decode(_teacherProfiles[uid]!['profileImageThumbnail']))
                      : (_teacherProfiles[uid]?['profileImageUrl'] != null
                          ? NetworkImage(_teacherProfiles[uid]!['profileImageUrl'])
                          : null) as ImageProvider?,
                  child: (_teacherProfiles[uid]?['profileImageThumbnail'] == null && _teacherProfiles[uid]?['profileImageUrl'] == null)
                      ? Icon(Icons.school, color: HexColor("#116754"), size: 30)
                      : null,
                ),

              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (uid == _sectionAdviserUid ? HexColor("#116754") : Colors.green).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        uid == _sectionAdviserUid ? 'Adviser' : 'Subject Teacher',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: uid == _sectionAdviserUid ? HexColor("#116754") : Colors.green[700],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (subjects.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: subjects.map((subjData) {
                           final subjName = subjData['subject'] as String;
                           final sem = subjData['semester'] as int;
                           return InkWell(
                             onTap: _isAdviser ? () {
                                _showAddSubjectDialog(
                                    editSubject: subjName, 
                                    editTeacherUid: uid, 
                                    editSemester: sem
                                );
                             } : null,
                             child: Chip(
                               label: Text('${subjName.toUpperCase()} (Sem $sem)', style: const TextStyle(fontSize: 12)),
                               backgroundColor: Colors.grey[100],
                               padding: EdgeInsets.zero,
                               visualDensity: VisualDensity.compact,
                               deleteIcon: _isAdviser ? const Icon(Icons.edit, size: 14, color: Colors.blue) : null,
                               deleteButtonTooltipMessage: 'Edit',
                               onDeleted: _isAdviser ? () {
                                   _showAddSubjectDialog(
                                    editSubject: subjName, 
                                    editTeacherUid: uid, 
                                    editSemester: sem
                                );
                               } : null,
                             ),
                           );
                        }).toList(),
                      ),
                  ],
                ),
              ),
              if (_isAdviser) ...[
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.blue),
                  onPressed: () => _showAddSubjectDialog(initialTeacherUid: uid, initialTeacherName: name, editSemester: defaultSemester),
                  tooltip: 'Add schedule to this teacher',
                ),
                if (uid == _sectionAdviserUid)
                  // Adviser can manage their own subjects, but not remove themselves
                  IconButton(
                    icon: Icon(Icons.settings_outlined, size: 20, color: HexColor("#116754")),
                    onPressed: _showManageScheduleDialog,
                    tooltip: 'Manage your subjects',
                  )
                else
                  // Other teachers can be fully removed
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    onPressed: () => _removeTeacherFromSection(uid, name),
                    tooltip: 'Remove teacher from section',
                  ),
              ],
              Icon(Icons.arrow_forward_ios, color: HexColor("#116754"), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// Dialog widget for adding students
class _AddStudentDialog extends StatefulWidget {
  final List<Map<String, dynamic>> unassignedStudents;
  final String sectionName;
  final VoidCallback onStudentAdded;
  final Future<void> Function(String uid, String name) assignStudent;
  final bool isTourMode;

  const _AddStudentDialog({
    required this.unassignedStudents,
    required this.sectionName,
    required this.onStudentAdded,
    required this.assignStudent,
    this.isTourMode = false,
  });

  @override
  State<_AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<_AddStudentDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredStudents = [];
  final GlobalKey _addItemKey = GlobalKey();
  final GlobalKey _studentNameKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _filteredStudents = List.from(widget.unassignedStudents);
    _searchController.addListener(_filterStudents);

    if (widget.isTourMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        GuidePointer.show(
          context,
          steps: [
            GuideStep(
              targetKey: _studentNameKey,
              title: "Step 2: Found a Student!",
              content: "This student is looking for a class. You can see their name and details here.",
              buttonLabel: "Next",
            ),
            GuideStep(
              targetKey: _addItemKey,
              title: "Add to Class",
              content: "Tap the + icon to add them to your section.",
              hideButton: true,
            ),
          ],
          totalStepsOverride: 7,
          initialStepOffset: 1,
          onComplete: () {},
        );

      });
    }
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
                        return Container(
                          key: index == 0 ? _studentNameKey : null,
                          child: ListTile(
                            leading: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black, width: 2.0),
                              ),
                              child: CircleAvatar(
                                radius: 30, // Increased size
                                backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                                backgroundImage: student['profileImageThumbnail'] != null
                                    ? MemoryImage(base64Decode(student['profileImageThumbnail']))
                                    : (student['profileImageUrl'] != null
                                        ? NetworkImage(student['profileImageUrl'])
                                        : null) as ImageProvider?,
                                child: (student['profileImageThumbnail'] == null && student['profileImageUrl'] == null)
                                    ? Icon(Icons.person, color: HexColor("#116754"), size: 30)
                                    : null,
                              ),

                            ),
                            title: Text(student['name'] as String),
                            subtitle: Text(student['email'] as String),
                              trailing: IconButton(
                              key: index == 0 ? _addItemKey : null,
                              icon: const Icon(Icons.add),
                            onPressed: () async {
                              if (widget.isTourMode) GuidePointer.dismiss();
                              
                              await widget.assignStudent(
                                student['uid'] as String,
                                student['name'] as String,
                              );
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              widget.onStudentAdded();
                            },
                          ),
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



