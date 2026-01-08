import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = true;
  int _enrolledCount = 0;
  int _upcomingClasses = 0;
  double _averageGrade = 0.0;

  int _unreadMessages = 0;

  List<String> _sections = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Listen to student document for sections and grades
        FirebaseFirestore.instance
            .collection('students')
            .doc(user.uid)
            .snapshots()
            .listen((doc) async {
          if (!doc.exists) return;
          final data = doc.data();
          if (data == null) return;

          // 1. Enrolled Count
          final sections = List<String>.from(data['sections'] ?? []);

          // 2. Average Grade
          double avg = 0.0;
          final gradesMap = data['grades'] as Map<String, dynamic>?;
          if (gradesMap != null && gradesMap.isNotEmpty) {
            double sum = 0;
            int count = 0;
            gradesMap.forEach((_, val) {
               if (val is Map) {
                 // Quarterly grades: calculate average of quarters
                 final quarters = val.values.whereType<num>();
                 if (quarters.isNotEmpty) {
                   final qSum = quarters.fold(0.0, (a, b) => a + b.toDouble());
                   sum += qSum / quarters.length;
                   count++;
                 }
               } else if (val is num) {
                 // Legacy format
                 sum += val.toDouble();
                 count++;
               }
            });
            if (count > 0) {
              avg = sum / count;
              avg = double.parse(avg.toStringAsFixed(1));
            }
          }

          // 3. Upcoming Classes (Need to fetch section schedules)
          int upcoming = 0;
          for (final sectionName in sections) {
             try {
                final sectionDoc = await FirebaseFirestore.instance.collection('sections').doc(sectionName).get();
                if (sectionDoc.exists) {
                   final schedule = sectionDoc.data()?['schedule'] as List?;
                   if (schedule != null) {
                     upcoming += schedule.length;
                   }
                }
             } catch (e) {
               debugPrint('Error fetching section schedule for stats: $e');
             }
          }

          // 4. Unread Messages from Firestore
          int unread = 0;
          try {
             final inboxSnapshot = await FirebaseFirestore.instance
                 .collection('students')
                 .doc(user.uid)
                 .collection('inbox')
                 .where('read', isEqualTo: false)
                 .get();
             unread = inboxSnapshot.docs.length;
          } catch (_) {}

          if (mounted) {
            setState(() {
              _enrolledCount = sections.length;
              _upcomingClasses = upcoming;
              _averageGrade = avg;
              _unreadMessages = unread;
              _sections = sections;
              _isLoading = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading home stats: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = width < 600;

        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Back!',
                  style: TextStyle(
                    fontSize: isMobile ? 28 : 36,
                    fontWeight: FontWeight.bold,
                    color: HexColor("#0F4C7F"),
                  ),
                ),
                const SizedBox(height: 24),

                Builder(
                  builder: (context) {
                    // Calculate card width based on available space
                    int crossAxisCount = 4;
                    if (width < 600) {
                      crossAxisCount = 2;
                    } else if (width < 900) {
                      crossAxisCount = 3;
                    }

                    final double spacing = 16;
                    final totalSpacing = spacing * (crossAxisCount - 1);
                    final cardWidth = (width - (isMobile ? 32 : 48) - totalSpacing) / crossAxisCount;

                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _buildStatCard(
                            'Enrolled Subjects',
                            _enrolledCount.toString(),
                            Icons.book,
                            HexColor("#0F4C7F"),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildStatCard(
                            'Upcoming Classes',
                            _upcomingClasses.toString(),
                            Icons.schedule,
                            HexColor("#1e824c"),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildStatCard(
                            'Average Grade',
                            _averageGrade.toString(),
                            Icons.grade,
                            HexColor("#d4af37"),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _buildStatCard(
                            'Unread Messages',
                            _unreadMessages.toString(),
                            Icons.mail,
                            HexColor("#e63946"),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 32),

                // My Classes Section
                if (_sections.isNotEmpty) ...[
                  Text(
                    'My Classes',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: HexColor("#0F4C7F"),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (width > 900)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 12,
                        mainAxisExtent: 80,
                      ),
                      itemCount: _sections.length,
                      itemBuilder: (context, index) => _buildClassCard(_sections[index]),
                    )
                  else
                    Column(
                      children: _sections.map((section) => _buildClassCard(section)).toList(),
                    ),
                  const SizedBox(height: 32),
                ],

              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildClassCard(String sectionName) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: HexColor("#0F4C7F").withValues(alpha: 0.1),
          child: Icon(Icons.class_, color: HexColor("#0F4C7F")),
        ),
        title: Text(
          sectionName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: const Text('Enrolled'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
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
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

}