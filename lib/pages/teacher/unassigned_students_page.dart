import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../../widgets/lime_dropdown.dart';

class UnassignedStudentsPage extends StatefulWidget {
  const UnassignedStudentsPage({super.key});

  @override
  State<UnassignedStudentsPage> createState() => _UnassignedStudentsPageState();
}

class _UnassignedStudentsPageState extends State<UnassignedStudentsPage> {
  List<UnassignedStudent> _allStudents = [];
  List<UnassignedStudent> _filteredStudents = [];
  final TextEditingController _searchController = TextEditingController();
  String? _selectedGradeLevel;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUnassignedStudents();
    _searchController.addListener(_filterStudents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUnassignedStudents() async {
    final firestore = FirebaseFirestore.instance;
    
    // Get only students from Firestore (exclude teachers)
    try {
      final studentsSnapshot = await firestore.collection('students').where('userType', isEqualTo: 'Student').get();

      final List<UnassignedStudent> students = [];

      for (var doc in studentsSnapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String? ?? 'Unknown';
        final uid = doc.id;

        // Check if student is assigned to any section in Firestore
        final sections = data['sections'] as List<dynamic>?;

        if (sections == null || sections.isEmpty) {
          final String? gVal = data['gradeLevel'] as String?;
          students.add(UnassignedStudent(
            uid: uid,
            name: name,
            email: data['email'] as String? ?? '',
            gradeLevel: gVal,
            profileImageThumbnail: data['profileImageThumbnail'] as String?,
            profileImageUrl: data['profileImageUrl'] as String?,
          ));
        }
      }
      
      setState(() {
        _allStudents = students;
        _filteredStudents = students;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading students: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterStudents() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStudents = _allStudents.where((student) {
        final matchesSearch = query.isEmpty || 
                             student.name.toLowerCase().contains(query) ||
                             student.email.toLowerCase().contains(query);
        
        final matchesGrade = _selectedGradeLevel == null || 
                            student.gradeLevel == _selectedGradeLevel;

        return matchesSearch && matchesGrade;
      }).toList();
    });
  }

  Future<void> _assignStudent(UnassignedStudent student) async {
    final user = FirebaseAuth.instance.currentUser;
    final firestore = FirebaseFirestore.instance;
    
    if (user == null) return;
    
    // Get teacher's sections from Firestore
    final teacherDoc = await firestore.collection('teachers').doc(user.uid).get();
    final sections = List<String>.from(teacherDoc.data()?['sections'] ?? []);
    
    if (sections.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please create a section first')),
        );
      }
      return;
    }

    if (!mounted) return;

    // Show dialog to select section
    String? selectedSection = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Section'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sections.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(sections[index]),
                onTap: () => Navigator.pop(context, sections[index]),
              );
            },
          ),
        ),
      ),
    );

    if (selectedSection == null) return;

    // Assignments are now Firestore-first, the SectionDetailPage listener will handle UI updates
    await firestore.collection('students').doc(student.uid).set(
      {'sections': FieldValue.arrayUnion([selectedSection])},
      SetOptions(merge: true),
    );
      
    // Remove from local unassigned list
    setState(() {
      _allStudents.removeWhere((s) => s.uid == student.uid);
      _filteredStudents = _allStudents;
    });

    // Notify student (Firestore first)
    await _addInboxNotification(student.uid, selectedSection, user.uid);
      
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${student.name} assigned to $selectedSection')),
      );
    }
  }

  Future<void> _addInboxNotification(String studentUid, String sectionName, String teacherUid) async {
    try {
      final teacherDoc = await FirebaseFirestore.instance.collection('teachers').doc(teacherUid).get();
      final teacherName = teacherDoc.data()?['name'] ?? 'Teacher';

      await FirebaseFirestore.instance.collection('students').doc(studentUid).collection('inbox').add({
        'title': 'Section Assignment',
        'message': 'You have been assigned to section: $sectionName by $teacherName',
        'timestamp': DateTime.now().toIso8601String(),
        'read': false,
        'type': 'assignment',
        'senderUid': teacherUid,
        'sectionName': sectionName,
      });
    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unassigned Students'),
        backgroundColor: HexColor("#116754"),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Search and assign students to your sections',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Search by name or email...',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[100],
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: LIMEDropdown<String>(
                              label: 'Grade Level',
                              hint: 'All Grades',
                              value: _selectedGradeLevel,
                              compact: true,
                              items: const [
                                DropdownMenuItem(value: null, child: Text('All Grades')),
                                DropdownMenuItem(value: 'Grade 11', child: Text('Grade 11')),
                                DropdownMenuItem(value: 'Grade 12', child: Text('Grade 12')),
                              ],
                              onChanged: (val) {
                                setState(() => _selectedGradeLevel = val);
                                _filterStudents();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _filteredStudents.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.people_outline,
                                  size: 80,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _allStudents.isEmpty
                                      ? 'No unassigned students'
                                      : 'No students found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredStudents.length,
                          itemBuilder: (context, index) {
                            final student = _filteredStudents[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
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
                                        backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                                        backgroundImage: student.profileImageThumbnail != null
                                            ? MemoryImage(base64Decode(student.profileImageThumbnail!))
                                            : (student.profileImageUrl != null
                                                ? NetworkImage(student.profileImageUrl!)
                                                : null) as ImageProvider?,
                                        child: (student.profileImageThumbnail == null && student.profileImageUrl == null)
                                            ? Icon(
                                                Icons.person,
                                                color: HexColor("#116754"),
                                              )
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            student.name,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (student.email.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              student.email,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () => _assignStudent(student),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Assign'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: HexColor("#116754"),
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
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

class UnassignedStudent {
  final String uid;
  final String name;
  final String email;
  final String? gradeLevel;
  final String? profileImageThumbnail;
  final String? profileImageUrl;

  UnassignedStudent({
    required this.uid,
    required this.name,
    required this.email,
    this.gradeLevel,
    this.profileImageThumbnail,
    this.profileImageUrl,
  });
}

