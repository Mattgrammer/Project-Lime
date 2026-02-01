import 'package:flutter/material.dart';
import 'dart:async';
import 'package:hexcolor/hexcolor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'student_profile_page.dart';
import '../../models/student.dart';
import '../../widgets/lime_dropdown.dart';

class StudentDirectoryPage extends StatefulWidget {
  const StudentDirectoryPage({super.key});

  @override
  State<StudentDirectoryPage> createState() => _StudentDirectoryPageState();
}

class _StudentDirectoryPageState extends State<StudentDirectoryPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  final TextEditingController _searchController = TextEditingController();

  List<String> _availableSections = [];
  List<String> _availableGradeLevels = [];
  String? _selectedSection;
  String? _selectedGradeLevel;
  Map<String, int> _sectionGradeLevels = {};

  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    _initListeners();
    _searchController.addListener(_filterStudents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _sectionsSub?.cancel();
    _adviserSectionsSub?.cancel();
    _teacherSub?.cancel();
    super.dispose();
  }

  StreamSubscription? _sectionsSub;
  StreamSubscription? _adviserSectionsSub;
  StreamSubscription? _teacherSub;

  void _initListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final firestore = FirebaseFirestore.instance;

    // Use two streams separately to avoid Filter.or potential index issues
    _sectionsSub = firestore.collection('sections')
        .where('teacherUids', arrayContains: user.uid)
        .snapshots()
        .listen((snap) {
      if (mounted) {
        _updateFromSections();
      }
    });

    _adviserSectionsSub = firestore.collection('sections') 
        .where('adviserUid', isEqualTo: user.uid)
        .snapshots()
        .listen((snap) {
      if (mounted) {
        _updateFromSections();
      }
    });

    _teacherSub = firestore.collection('teachers').doc(user.uid).snapshots().listen((snap) {
      if (mounted) {
        _updateFromSections();
      }
    });

    // Initial load
    _updateFromSections();
  }

  Future<void> _updateFromSections() async {
    if (_isFetching) {
      return;
    }
    _isFetching = true;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) {
      _isFetching = false;
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      
      if (!_isLoading) {
        setState(() => _isLoading = true);
      }

      // Step 0: Get sections from the teacher document (for legacy/completeness)
      final teacherDoc = await firestore.collection('teachers').doc(user.uid).get();
      final List<String> teacherSections = List<String>.from(teacherDoc.data()?['sections'] ?? []);

      // Step 1: Query sections collection for direct associations
      // Fetch where user is adviser OR subject teacher
      final adviserQuery = firestore.collection('sections').where('adviserUid', isEqualTo: user.uid).get();
      final teacherQuery = firestore.collection('sections').where('teacherUids', arrayContains: user.uid).get();

      final results = await Future.wait([adviserQuery, teacherQuery]);
      final adviserSnaps = results[0];
      final teacherSnaps = results[1];

      final Set<String> sectionIds = { ...teacherSections }; // Start with IDs from teacher doc
      final Map<String, int> sectionGrades = {};
      final Map<String, DocumentSnapshot> sectionDocs = {};

      void processDoc(DocumentSnapshot doc) {
        if (!doc.exists) return;
        sectionIds.add(doc.id);
        sectionDocs[doc.id] = doc;
        
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return;

        var gVal = data['gradeLevel'];
        int? g;

        if (gVal is int) {
          g = gVal;
        } else if (gVal is String) {
          // Parse "Grade 11", "11 - AMBER", etc.
          final digits = gVal.replaceAll(RegExp(r'[^0-9]'), '');
          if (digits.isNotEmpty) {
            g = int.tryParse(digits);
          }
        }
        
        // FALLBACK: Parse grade from section name if missing (e.g. "GRADE 11 - STEM")
        if (g == null || g == 0) {
          final name = doc.id.toUpperCase();
          if (name.contains('12')) {
            g = 12;
          } else if (name.contains('11')) {
            g = 11;
          } else if (name.contains('10')) {
            g = 10;
          } else if (name.contains('9')) {
            g = 9;
          } else if (name.contains('8')) {
            g = 8;
          } else if (name.contains('7')) {
            g = 7;
          }
        }
        
        if (g != null && g > 0) {
          sectionGrades[doc.id] = g;
        }
      }

      // Process query snapshots
      for (var doc in adviserSnaps.docs) {
        processDoc(doc);
      }
      for (var doc in teacherSnaps.docs) {
        processDoc(doc);
      }

      // Fetch any missing section details from the teacher doc list
      final List<String> missingIds = sectionIds.where((id) => !sectionDocs.containsKey(id)).toList();
      if (missingIds.isNotEmpty) {
        for (int i = 0; i < missingIds.length; i += 30) {
          final chunk = missingIds.sublist(i, (i + 30 > missingIds.length) ? missingIds.length : i + 30);
          final snaps = await firestore.collection('sections').where(FieldPath.documentId, whereIn: chunk).get();
          for (var doc in snaps.docs) {
            processDoc(doc);
          }
        }
      }

      if (sectionIds.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _allStudents = [];
            _filteredStudents = [];
            _availableSections = [];
            _availableGradeLevels = [];
          });
        }
        return;
      }

      // Step 2: Update section & grade dropdowns IMMEDIATELY
      if (mounted) {
        setState(() {
          _availableSections = sectionIds.toList()..sort();
          _sectionGradeLevels = sectionGrades;
          _availableGradeLevels = sectionGrades.values.toSet().toList()
            .map((g) => g.toString())
            .toList()
            ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
        });
      }

      // Step 4: Collect all student UIDs from section documents
      final Set<String> studentUids = {};
      for (var id in sectionIds) {
        final doc = sectionDocs[id];
        if (doc == null) continue;
        final data = doc.data() as Map<String, dynamic>;
        final List<dynamic> uids = data['studentUids'] as List<dynamic>? ?? [];
        for (var uid in uids) {
          if (uid is String) studentUids.add(uid);
        }
      }

      // If we found UIDs in sections, fetch them. Otherwise try querying by section array.
      if (studentUids.isNotEmpty) {
        // Fetch students in chunks of 30 (Firestore limit)
        final List<String> uidList = studentUids.toList();
        final List<Map<String, dynamic>> allStudentsData = [];
        
        for (int i = 0; i < uidList.length; i += 30) {
          final chunk = uidList.sublist(i, i + 30 > uidList.length ? uidList.length : i + 30);
          final snaps = await firestore.collection('students')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          for (var doc in snaps.docs) {
            final data = doc.data();
            data['uid'] = doc.id;
            allStudentsData.add(data);
          }
        }

        if (mounted) {
          setState(() {
            _allStudents = allStudentsData..sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
            _availableSections = sectionIds.toList()..sort();
            _sectionGradeLevels = sectionGrades;
            _availableGradeLevels = sectionGrades.values.toSet().toList().map((g) => g.toString()).toList()..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
            _isLoading = false;
          });
          _filterStudents();
        }
      } else {
        // Fallback: try querying by sections array (Legacy or if uids array is missing)
        final List<String> sections = sectionIds.toList();
        // Chunk sections if > 30
        final List<Map<String, dynamic>> fallbackStudents = [];
        for (int i = 0; i < sections.length; i += 30) {
          final chunk = sections.sublist(i, i + 30 > sections.length ? sections.length : i + 30);
          final snaps = await firestore.collection('students')
              .where('sections', arrayContainsAny: chunk)
              .get();
          for (var doc in snaps.docs) {
            final data = doc.data();
            data['uid'] = doc.id;
            if (!fallbackStudents.any((s) => s['uid'] == doc.id)) {
              fallbackStudents.add(data);
            }
          }
        }

        if (mounted) {
          setState(() {
            _allStudents = fallbackStudents..sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
            _availableSections = sections..sort();
            _sectionGradeLevels = sectionGrades;
            _availableGradeLevels = sectionGrades.values.toSet().toList().map((g) => g.toString()).toList()..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
            _isLoading = false;
          });
          _filterStudents();
        }
      }
    } catch (e) {
      debugPrint('Error loading directory data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } finally {
      _isFetching = false;
    }
  }

  void _filterStudents() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStudents = _allStudents.where((s) {
        // Search filter
        final name = (s['name'] ?? '').toString().toLowerCase();
        final email = (s['email'] ?? '').toString().toLowerCase();
        final matchesSearch = query.isEmpty || name.contains(query) || email.contains(query);

        // Section filter
        final List<dynamic> sSections = s['sections'] ?? [];
        final matchesSection = _selectedSection == null || sSections.contains(_selectedSection);

        // Grade Level filter
        bool matchesGrade = _selectedGradeLevel == null;
        if (_selectedGradeLevel != null) {
          final targetGrade = int.parse(_selectedGradeLevel!);
          // If we have section data, use it; otherwise, if user picked a grade, 
          // we might just want to show all students if we don't know their grade yet.
          // However, to be strict but safe:
          matchesGrade = sSections.any((sec) {
            final g = _sectionGradeLevels[sec];
            return g == null || g == targetGrade; // If unknown, include it in the grade filter
          });
        }

        return matchesSearch && matchesSection && matchesGrade;
      }).toList();
    });
  }

  List<String> get _displaySections {
    if (_selectedGradeLevel == null) {
      return _availableSections;
    }
    final int targetGrade = int.parse(_selectedGradeLevel!);
    return _availableSections.where((s) => _sectionGradeLevels[s] == targetGrade).toList();
  }

  List<String> get _displayGradeLevels {
    if (_selectedSection == null) {
      return _availableGradeLevels;
    }
    final int? g = _sectionGradeLevels[_selectedSection!];
    return g != null ? [g.toString()] : _availableGradeLevels;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Student Directory', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: HexColor("#116754"),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search students...',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                prefixIcon: Icon(Icons.search, color: HexColor("#116754"), size: 22),
                suffixIcon: _searchController.text.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18), 
                      onPressed: () {
                        _searchController.clear();
                        _filterStudents();
                      },
                    )
                  : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: HexColor("#116754"), width: 1.5),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: LIMEDropdown<String>(
                    label: 'Section',
                    hint: 'All Sections',
                    value: _selectedSection,
                    compact: true,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Sections')),
                      ..._displaySections.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedSection = val);
                      _filterStudents();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LIMEDropdown<String>(
                    label: 'Grade Level',
                    hint: 'All Grades',
                    value: _selectedGradeLevel,
                    compact: true,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Grades')),
                      ..._displayGradeLevels.map((g) => DropdownMenuItem(value: g, child: Text('Grade $g'))),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedGradeLevel = val);
                      _filterStudents();
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_filteredStudents.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text('No students found', style: TextStyle(color: Colors.grey[500])),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filteredStudents.length,
                itemBuilder: (context, index) {
                  final student = _filteredStudents[index];
                  final List<dynamic> sSections = student['sections'] ?? [];
                  final String sectionName = sSections.isNotEmpty ? sSections.first : 'Unknown';

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey[200]!, width: 1),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                      ),
                      child: ListTile(
                        onTap: () {
                          Navigator.push(
                            context, 
                            MaterialPageRoute(
                              builder: (context) => StudentProfilePage(
                                student: Student.fromJson(student),
                                sectionName: sectionName,
                                onUpdate: (sub, q, val) {},
                              ),
                            ),
                          );
                        },
                        leading: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 1.5),
                          ),
                          child: CircleAvatar(
                            backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                            backgroundImage: student['profileImageThumbnail'] != null
                                ? MemoryImage(base64Decode(student['profileImageThumbnail']))
                                : (student['profileImageUrl'] != null 
                                    ? NetworkImage(student['profileImageUrl']) 
                                    : null) as ImageProvider?,
                            child: (student['profileImageThumbnail'] == null && student['profileImageUrl'] == null)
                                ? Icon(Icons.person, color: HexColor("#116754"))
                                : null,
                          ),
                        ),
                        title: Text(
                          student['name'] ?? 'Unknown', 
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(student['email'] ?? ''),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

}

