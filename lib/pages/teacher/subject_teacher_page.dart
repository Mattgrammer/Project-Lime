import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SubjectTeacherPage extends StatefulWidget {
  final String teacherUid;
  final String teacherName;

  const SubjectTeacherPage({super.key, required this.teacherUid, required this.teacherName});

  @override
  State<SubjectTeacherPage> createState() => _SubjectTeacherPageState();
}

class _SubjectTeacherPageState extends State<SubjectTeacherPage> {
  String? _teacherType;
  List<String> _sections = [];
  List<String> _ownedSections = [];

  final Map<String, List<Map<String, dynamic>>> _teacherSubjects = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final firestore = FirebaseFirestore.instance;

    try {
      // 1. Fetch teacher metadata and sections from Firestore
      final teacherDoc = await firestore.collection('teachers').doc(widget.teacherUid).get();
      if (teacherDoc.exists) {
        final data = teacherDoc.data()!;
        _teacherType = data['teacherType'] as String?;
        _sections = List<String>.from(data['sections'] ?? []);
        _ownedSections = List<String>.from(data['ownedSections'] ?? []);
      }

      // 2. For each section, fetch the schedule to find assigned subjects
      for (var sectionName in _sections) {
        final sectionDoc = await firestore.collection('sections').doc(sectionName).get();
        if (sectionDoc.exists) {
           final data = sectionDoc.data()!;
           final List<dynamic> schedule = data['schedule'] ?? [];
           
           final List<Map<String, dynamic>> subjects = [];
           for (var item in schedule) {
             final entry = item as Map<String, dynamic>;
             if (entry['teacherUid'] == widget.teacherUid) {
                subjects.add(entry);
             }
           }
           _teacherSubjects[sectionName] = subjects;
        }
      }
    } catch (e) {
      debugPrint('Error loading data from Firestore: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _removeSubjectGroup(String sectionName, String subject, int semester) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Subject'),
        content: Text('Are you sure you want to remove $subject from $sectionName? This will remove all scheduled times for this subject.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: HexColor("#116754"), fontWeight: FontWeight.bold))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Remove', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final docRef = firestore.collection('sections').doc(sectionName);
      
      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;

        final startSchedule = List<Map<String, dynamic>>.from(
          (snapshot.data()?['schedule'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map))
        );

        startSchedule.removeWhere((s) => 
            s['subject'] == subject && 
            s['semester'] == semester && 
            s['teacherUid'] == widget.teacherUid
        );

        transaction.update(docRef, {'schedule': startSchedule});
      });

      setState(() {
         final currentList = _teacherSubjects[sectionName];
         if (currentList != null) {
            currentList.removeWhere((s) => s['subject'] == subject && s['semester'] == semester);
         }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subject removed successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error removing subject: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Failed to remove subject: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth <= 600;

        return Scaffold(
          backgroundColor: Colors.white,
          body: Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(8, isMobile ? 8 : 16, 16, 8),
              color: Colors.white,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                    color: HexColor("#116754"),
                  ),
                  Expanded(
                    child: Text(
                      widget.teacherName,
                      style: TextStyle(
                        fontSize: isMobile ? 24 : 32,
                        fontWeight: FontWeight.bold,
                        color: HexColor("#116754"),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.black, width: 2.0),
                                    ),
                                    child: CircleAvatar(
                                      radius: 36,
                                      backgroundColor: HexColor('#116754').withValues(alpha: 0.1),
                                      child: Icon(Icons.person, color: HexColor('#116754')),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(widget.teacherName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        Text(_teacherType ?? 'Teacher', style: TextStyle(color: Colors.grey[700])),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text('Sections', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: HexColor('#116754'))),
                            const SizedBox(height: 12),
                            if (_sections.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text('No sections found for this teacher.', style: TextStyle(color: Colors.grey[600])),
                              )
                            else
                              ..._sections.map((section) {
                                final isOwned = _ownedSections.contains(section);
                                final subjects = _teacherSubjects[section] ?? [];
                                
                                final uniqueSubjects = <String, Map<String, dynamic>>{};
                                for (var s in subjects) {
                                  final name = s['subject'] as String? ?? 'Unknown';
                                  final sem = s['semester'] as int? ?? 1;
                                  final key = '${name}_$sem';
                                  if (!uniqueSubjects.containsKey(key)) {
                                     uniqueSubjects[key] = s;
                                  }
                                }
                                final displaySubjects = uniqueSubjects.values.toList();

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.grey[300]!),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(section, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                                  const SizedBox(height: 4),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: (isOwned ? HexColor("#116754") : Colors.green).withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      isOwned ? 'Adviser' : 'Subject Teacher',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: isOwned ? HexColor("#116754") : Colors.green[700],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(Icons.arrow_forward_ios, size: 16, color: HexColor('#116754')),
                                          ],
                                        ),
                                      ),
                                      
                                      if (displaySubjects.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'ASSIGNED SUBJECTS:',
                                                style: TextStyle(
                                                  fontSize: 12, 
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              ...displaySubjects.map((entry) {
                                                final subjName = entry['subject'] as String? ?? 'Unknown';
                                                final sem = entry['semester'] as int? ?? 1;
                                                return Padding(
                                                  padding: const EdgeInsets.only(bottom: 4),
                                                  child: Row(
                                                      children: [
                                                          Icon(Icons.book_outlined, size: 16, color: HexColor("#116754")), 
                                                          const SizedBox(width: 8),
                                                          Expanded(
                                                            child: Text(
                                                              '$subjName (Sem $sem)', 
                                                              style: TextStyle(color: Colors.grey[800], fontSize: 14)
                                                            ),
                                                          ),
                                                          if (!isOwned)
                                                            IconButton(
                                                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                                              onPressed: () => _removeSubjectGroup(section, subjName, sem),
                                                              tooltip: 'Remove Subject',
                                                              padding: EdgeInsets.zero,
                                                              constraints: const BoxConstraints(),
                                                            ),
                                                      ],
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        )
                                      else if (!isOwned)
                                         Padding(
                                           padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                                           child: Text(
                                             'No subjects assigned in this section', 
                                             style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic, fontSize: 13)
                                           ),
                                         )
                                    ],
                                  ),
                                );
                              }),
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
}
