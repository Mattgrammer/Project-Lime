import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'section_detail_page.dart';

class MyClassesPage extends StatefulWidget {
  const MyClassesPage({super.key});

  @override
  State<MyClassesPage> createState() => _MyClassesPageState();
}

class _MyClassesPageState extends State<MyClassesPage> {
  List<String> _sections = [];
  List<String> _ownedSections = [];
  bool _isLoading = true;
  String? _teacherType;
  String? _teacherName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final doc = await firestore.collection('teachers').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          final sections = List<String>.from(data['sections'] ?? []);
          List<String> ownedSections;
          
          if (data['ownedSections'] == null && (data['teacherType'] == 'Adviser')) {
            // Migration: treat all current sections as owned
            ownedSections = List<String>.from(sections);
            await firestore.collection('teachers').doc(user.uid).update({
              'ownedSections': ownedSections,
            });
            
            // Also ensure sections documents exist with adviserUid
            for (var sectionName in ownedSections) {
              await firestore.collection('sections').doc(sectionName).set({
                'adviserUid': user.uid,
              }, SetOptions(merge: true));
            }
          } else {
            ownedSections = List<String>.from(data['ownedSections'] ?? []);
          }

          if (mounted) {
            setState(() {
              _teacherType = data['teacherType'] as String?;
              _teacherName = data['name'] as String? ?? 'Teacher'; // Added _teacherName
              _sections = sections;
              _ownedSections = ownedSections;
              _isLoading = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error loading sections from Firestore: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSections() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('teachers').doc(user.uid).set(
        {
          'sections': _sections,
          'ownedSections': _ownedSections,
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Error syncing sections to Firestore: $e');
    }
  }

  void _showAddSectionDialog(double screenWidth) {
    if (_ownedSections.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: screenWidth < 600 ? screenWidth * 0.9 : 400,
            ),
            child: Container(
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: Colors.white,
                border: Border.all(color: Colors.amber.shade200, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Container(
                     padding: const EdgeInsets.all(16),
                     decoration: BoxDecoration(
                       color: Colors.amber.shade50,
                       shape: BoxShape.circle,
                     ),
                     child: Icon(Icons.warning_amber_rounded, size: 48, color: Colors.amber.shade700),
                   ),
                   const SizedBox(height: 24),
                   Text(
                     'Limit Reached',
                     style: TextStyle(
                       fontSize: 22, 
                       fontWeight: FontWeight.bold,
                       color: Colors.amber.shade900,
                     ),
                   ),
                   const SizedBox(height: 16),
                   const Text(
                     'You can only create and manage one section at a time.',
                     textAlign: TextAlign.center,
                     style: TextStyle(fontSize: 16, height: 1.5),
                   ),
                   const SizedBox(height: 8),
                   Text(
                     'Please delete your existing section if you wish to create a new one.',
                     textAlign: TextAlign.center,
                     style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                   ),
                   const SizedBox(height: 24),
                   SizedBox(
                     width: double.infinity,
                     child: ElevatedButton(
                       onPressed: () => Navigator.pop(context),
                       style: ElevatedButton.styleFrom(
                         backgroundColor: Colors.amber.shade700,
                         foregroundColor: Colors.white,
                         padding: const EdgeInsets.symmetric(vertical: 12),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                       ),
                       child: const Text('Understand', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                     ),
                   ),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }

    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Section'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Section Name',
            hintText: 'e.g., Grade 11 - STEM',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                final sectionName = controller.text.trim();
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) return;

                // CHECK: Ensure section name is unique
                final sectionDoc = await FirebaseFirestore.instance.collection('sections').doc(sectionName).get();
                if (sectionDoc.exists) {
                   if (context.mounted) {
                      showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                            maxWidth: screenWidth < 600 ? screenWidth * 0.9 : 400,
            ),
                            child: Container(
                              padding: const EdgeInsets.all(36),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                color: Colors.white,
                                border: Border.all(color: Colors.amber.shade200, width: 2),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                   Container(
                                     padding: const EdgeInsets.all(16),
                                     decoration: BoxDecoration(
                                       color: Colors.amber.shade50,
                                       shape: BoxShape.circle,
                                     ),
                                     child: Icon(Icons.error_outline_rounded, size: 48, color: Colors.amber.shade700),
                                   ),
                                   const SizedBox(height: 24),
                                   Text(
                                     'Name Taken',
                                     style: TextStyle(
                                       fontSize: 22, 
                                       fontWeight: FontWeight.bold,
                                       color: Colors.amber.shade900,
                                     ),
                                   ),
                                   const SizedBox(height: 16),
                                   Text(
                                     'The section name "$sectionName" has already been taken.',
                                     textAlign: TextAlign.center,
                                     style: const TextStyle(fontSize: 16, height: 1.5),
                                   ),
                                   const SizedBox(height: 8),
                                   Text(
                                     'Please choose a different name.',
                                     textAlign: TextAlign.center,
                                     style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                   ),
                                   const SizedBox(height: 24),
                                   SizedBox(
                                     width: double.infinity,
                                     child: ElevatedButton(
                                       onPressed: () => Navigator.pop(context),
                                       style: ElevatedButton.styleFrom(
                                         backgroundColor: Colors.amber.shade700,
                                         foregroundColor: Colors.white,
                                         padding: const EdgeInsets.symmetric(vertical: 12),
                                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                       ),
                                       child: const Text('Try Again', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                     ),
                                   ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                   }
                   return; // Stop creation
                }

                setState(() {
                  _sections.add(sectionName);
                  _ownedSections.add(sectionName);
                });
                await _saveSections();
                
                // Set adviserUid, adviserName, and studentUids in section document
                await FirebaseFirestore.instance.collection('sections').doc(sectionName).set({
                  'adviserUid': user.uid,
                  'adviserName': _teacherName,
                  'studentUids': [],
                }, SetOptions(merge: true));

                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: HexColor("#0F4C7F"),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _deleteSection(int index) async {
    final sectionName = _sections[index];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Section'),
        content: Text('Are you sure you want to delete "$sectionName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final sectionToDelete = _sections[index];
              setState(() {
                _sections.removeAt(index);
                _ownedSections.remove(sectionToDelete);
              });
              await _saveSections();

              // 1. Fetch section data (schedule and studentUids) before deleting
              try {
                final firestore = FirebaseFirestore.instance;
                final sectionDoc = await firestore.collection('sections').doc(sectionToDelete).get();
                
                List<String> studentUids = [];
                List<dynamic> schedule = [];
                
                if (sectionDoc.exists) {
                  final data = sectionDoc.data()!;
                  studentUids = List<String>.from(data['studentUids'] ?? []);
                  schedule = data['schedule'] as List<dynamic>? ?? [];
                }

                final List<String> subjectsInRoom = schedule
                    .whereType<Map<String, dynamic>>()
                    .map((item) => item['subject'] as String)
                    .toList();

                final batch = firestore.batch();

                // 2. Remove grades for subjects in this section from all students in studentUids
                for (var studentUid in studentUids) {
                  final updates = <String, dynamic>{};
                  for (var subject in subjectsInRoom) {
                    updates['grades.$subject'] = FieldValue.delete();
                  }
                  if (updates.isNotEmpty) {
                    batch.update(firestore.collection('students').doc(studentUid), updates);
                  }
                }

                // 3. Remove section name from any student who had it (fallback check)
                final studentsWithSection = await firestore
                    .collection('students')
                    .where('sections', arrayContains: sectionToDelete)
                    .get();

                for (var doc in studentsWithSection.docs) {
                  batch.update(doc.reference, {
                    'sections': FieldValue.arrayRemove([sectionToDelete])
                  });
                }

                // 4. Remove from all teachers' sections
                final teachersWithSection = await firestore
                    .collection('teachers')
                    .where('sections', arrayContains: sectionToDelete)
                    .get();
                for (var doc in teachersWithSection.docs) {
                  batch.update(doc.reference, {
                    'sections': FieldValue.arrayRemove([sectionToDelete]),
                    'ownedSections': FieldValue.arrayRemove([sectionToDelete]),
                  });
                }

                // 5. Delete the section document
                batch.delete(firestore.collection('sections').doc(sectionToDelete));

                await batch.commit();
                debugPrint('Permanently deleted $sectionToDelete and purged associated data');
              } catch (e) {
                debugPrint('Error during robust section deletion: $e');
              }

              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isAdviser = _teacherType == 'Adviser';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = width <= 600;
        final isDesktop = width > 900;
        
        final horizontalPadding = isMobile ? 16.0 : 24.0;
        final titleSize = isMobile ? 28.0 : 32.0;

        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Classes',
                            style: TextStyle(
                              fontSize: titleSize,
                              fontWeight: FontWeight.bold,
                              color: HexColor("#0F4C7F"),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isAdviser 
                                ? 'Manage your sections' 
                                : 'Manage your classes and students',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isAdviser)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: ElevatedButton.icon(
                          onPressed: () => _showAddSectionDialog(width),
                          icon: const Icon(Icons.add, size: 20),
                          label: Text(isMobile ? 'Create' : 'Create Section'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HexColor("#0F4C7F"),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 12 : 20, 
                              vertical: isMobile ? 8 : 12
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),

                if (_sections.isEmpty)
                  _buildEmptyState(isAdviser)
                else ...[
                  if (_ownedSections.isNotEmpty) ...[
                    Text(
                      'My Sections (Adviser)',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: HexColor("#0F4C7F"),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSectionGrid(_ownedSections, isOwned: true, isDesktop: isDesktop),
                    const SizedBox(height: 24),
                  ],
                  if (_sections.where((s) => !_ownedSections.contains(s)).isNotEmpty) ...[
                    Text(
                      'Assigned Classes (Subject Teacher)',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: HexColor("#0F4C7F"),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSectionGrid(
                      _sections.where((s) => !_ownedSections.contains(s)).toList(),
                      isOwned: false,
                      isDesktop: isDesktop
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionGrid(List<String> sections, {required bool isOwned, required bool isDesktop}) {
    if (isDesktop) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: 120, // Fixed height for cards
        ),
        itemCount: sections.length,
        itemBuilder: (context, index) => _buildSectionCard(sections[index], isOwned: isOwned),
      );
    }
    return Column(
      children: sections.map((section) => _buildSectionCard(section, isOwned: isOwned)).toList(),
    );
  }

  Widget _buildEmptyState(bool isAdviser) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.class_, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              isAdviser ? 'No sections created yet' : 'No classes available',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            if (isAdviser) ...[
              const SizedBox(height: 8),
              Text(
                'Click "Create" to get started',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(String section, {required bool isOwned}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SectionDetailPage(sectionName: section),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (isOwned ? HexColor("#0F4C7F") : Colors.green).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isOwned ? Icons.class_ : Icons.school,
                  color: isOwned ? HexColor("#0F4C7F") : Colors.green[700],
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  section,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isOwned)
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red[400]),
                  onPressed: () {
                    final idx = _sections.indexOf(section);
                    if (idx != -1) _deleteSection(idx);
                  },
                ),
              Icon(
                Icons.arrow_forward_ios,
                color: HexColor("#0F4C7F"),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

