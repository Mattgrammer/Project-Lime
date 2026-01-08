import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TeacherHomePage extends StatefulWidget {
  final Function(int index)? onNavigate;
  
  const TeacherHomePage({super.key, this.onNavigate});

  @override
  State<TeacherHomePage> createState() => _TeacherHomePageState();
}

class _TeacherHomePageState extends State<TeacherHomePage> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('teachers').doc(user.uid).snapshots(),
      builder: (context, teacherSnapshot) {
        if (!teacherSnapshot.hasData || !teacherSnapshot.data!.exists) {
          return const Center(child: CircularProgressIndicator());
        }

        final teacherData = teacherSnapshot.data!.data() as Map<String, dynamic>;
        final List<String> ownedSections = List<String>.from(teacherData['sections'] ?? []);

        // Flatten the rest using a combined builder or less aggressive nested streams
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('sections').snapshots(),
          builder: (context, sectionsSnapshot) {
            final Set<String> allMySections = Set.from(ownedSections);
            final Map<String, List<String>> sectionToStudents = {};
            
            if (sectionsSnapshot.hasData) {
              for (var doc in sectionsSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final schedule = data['schedule'] as List<dynamic>? ?? [];
                final studentUids = List<String>.from(data['studentUids'] ?? []);
                
                final isSubjectTeacher = schedule.any((item) => 
                  item is Map && item['teacherUid'] == user.uid
                );
                
                if (isSubjectTeacher || allMySections.contains(doc.id)) {
                  allMySections.add(doc.id);
                  sectionToStudents[doc.id] = studentUids;
                }
              }
            }

            final int classesCount = allMySections.length;

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('students').snapshots(),
              builder: (context, studentsSnapshot) {
                // 1. Get unread messages count (we'll keep this as a separate future or part of a combined stream if we wanted full reactivity)
                // For now, let's just make the student count/list reactive
                
                final allAssignedStudentUids = sectionToStudents.values.expand((uids) => uids).toSet();
                
                int studentCount = 0;
                List<Map<String, dynamic>> myStudentsList = [];
                
                if (studentsSnapshot.hasData) {
                  for (var doc in studentsSnapshot.data!.docs) {
                    if (allAssignedStudentUids.contains(doc.id)) {
                      final data = doc.data() as Map<String, dynamic>;
                      final studentSections = List<String>.from(data['sections'] ?? []);
                      final matches = studentSections.where((s) => allMySections.contains(s)).toList();
                      
                      if (matches.isNotEmpty) {
                        studentCount++;
                        myStudentsList.add({
                          'name': data['name'] ?? 'Unknown',
                          'sections': matches.join(', '),
                          'uid': doc.id,
                        });
                      }
                    }
                  }
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('teachers')
                      .doc(user.uid)
                      .collection('inbox')
                      .where('read', isEqualTo: false)
                      .snapshots(),
                  builder: (context, inboxSnapshot) {
                    final unreadCount = inboxSnapshot.data?.docs.length ?? 0;

                    return SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome Back!',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: HexColor("#0F4C7F"),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Here is your dashboard overview',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 24),

                            LayoutBuilder(
                              builder: (context, constraints) {
                                return Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    _buildStatCard(
                                      'Active Classes',
                                      classesCount.toString(),
                                      Icons.class_,
                                      Colors.blue,
                                      constraints.maxWidth,
                                      onTap: () => widget.onNavigate?.call(2), // My Classes
                                    ),
                                    _buildStatCard(
                                      'Total Students',
                                      studentCount.toString(), 
                                      Icons.people,
                                      Colors.orange,
                                      constraints.maxWidth,
                                      onTap: () => _showStudentsListDialog(context, myStudentsList),
                                    ),
                                    _buildStatCard(
                                      'Unread Messages',
                                      unreadCount.toString(),
                                      Icons.message,
                                      Colors.red,
                                      constraints.maxWidth,
                                      onTap: () => widget.onNavigate?.call(3), // Inbox
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    );
                  }
                );
              }
            );
          },
        );
      },
    );
  }

  // _fetchDashboardStats is no longer used but kept for historical reasons or removed

  void _showStudentsListDialog(BuildContext context, List<Map<String, dynamic>> students) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('My Students'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SizedBox(
            width: double.maxFinite,
          child: students.isEmpty
              ? const Center(child: Text('No students found in your sections.'))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: students.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final s = students[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: HexColor("#0F4C7F").withValues(alpha: 0.1),
                        child: Text(
                          s['name'][0].toUpperCase(),
                          style: TextStyle(color: HexColor("#0F4C7F"), fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Sections: ${s['sections']}'),
                    );
                  },
                ),
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, double maxWidth, {VoidCallback? onTap}) {
    // Responsive width calculation
    double width = (maxWidth - 32) / 3; // 3 cards per row
    if (width < 140) width = (maxWidth - 16) / 2; // 2 cards
    if (width < 140) width = maxWidth; // 1 card

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 30),
                if (onTap != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'View', 
                      style: TextStyle(
                        color: Colors.white, 
                        fontSize: 10, 
                        fontWeight: FontWeight.bold
                      )
                    ),
                  )
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
