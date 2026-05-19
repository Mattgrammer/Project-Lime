import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../../services/fcm_service.dart';

class RequestSectionPage extends StatefulWidget {
  const RequestSectionPage({super.key});

  @override
  State<RequestSectionPage> createState() => _RequestSectionPageState();
}

class _RequestSectionPageState extends State<RequestSectionPage> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _allSections = [];
  List<String> _filteredSections = [];
  Set<String> _pendingRequests = {};
  Set<String> _assignedSections = {};
  final Map<String, String?> _sectionThumbnails = {};
  final Map<String, String?> _sectionImageUrls = {};
  final Map<String, String> _sectionOwners = {};

  bool _isLoading = true;
  bool _showDemoSections = false;
  StreamSubscription? _studentSubscription;

  @override
  void initState() {
    super.initState();
    _loadDemoSectionsFlag();
    _loadData(); // Initial load for sections list
    _listenToStudentData(); // Real-time listener for requests/assignments
    _searchController.addListener(_filterSections);
    // Safety timeout to prevent infinite spinner
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  void dispose() {
    _studentSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _listenToStudentData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _studentSubscription?.cancel();
    _studentSubscription = FirebaseFirestore.instance
        .collection('students')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;

      final data = doc.data()!;

      // Sync Pending Requests from Cloud
      final cloudPending = List<String>.from(data['pendingRequests'] ?? []);

      // Sync Assigned Sections from Cloud
      final cloudAssigned = List<String>.from(data['sections'] ?? []);

      setState(() {
        _pendingRequests = Set<String>.from(cloudPending);
        _assignedSections = Set<String>.from(cloudAssigned);
      });
    });
  }

  Future<void> _loadDemoSectionsFlag() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showDemoSections = prefs.getBool('show_demo_sections') ?? false;
      });
    }
  }

  Future<void> _loadData() async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Fetch all sections directly to get thumbnails and adviser info
      final sectionsSnapshot = await firestore
          .collection('sections')
          .get();

      final Set<String> sections = {};
      _sectionOwners.clear();
      _sectionThumbnails.clear();
      _sectionImageUrls.clear();

      for (var doc in sectionsSnapshot.docs) {
        final sectionName = doc.id;
        
        // Skip demo sections unless explicitly showing them
        if (sectionName.contains('[TUTORIAL]') || sectionName.contains('Demo Section')) {
          if (!_showDemoSections) {
            continue;
          }
        }

        final data = doc.data();
        sections.add(sectionName);
        
        final adviserUid = data['adviserUid'] as String?;
        if (adviserUid != null) {
          _sectionOwners[sectionName] = adviserUid;
        }
        
        _sectionThumbnails[sectionName] = data['sectionImageThumbnail'] as String?;
        _sectionImageUrls[sectionName] = data['sectionImageUrl'] as String?;
      }

      if (mounted) {
        setState(() {
          _allSections = sections.toList()..sort();
          _filteredSections = List.from(_allSections);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading sections: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterSections() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredSections = List.from(_allSections);
      } else {
        _filteredSections = _allSections
            .where((section) => section.toLowerCase().contains(query))
            .toList();
      }
    });
  }


  Future<String?> _addAdviserNotification(
    String adviserUid,
    String studentName,
    String sectionName,
    String studentUid,
  ) async {
    try {
      final docRef = await FirebaseFirestore.instance
          .collection('teachers')
          .doc(adviserUid)
          .collection('inbox')
          .add({
        'title': 'Join Request',
        'message': '$studentName requested to join section: $sectionName',
        'timestamp': DateTime.now().toIso8601String(),
        'read': false,
        'type': 'join_request',
        'studentUid': studentUid,
        'studentName': studentName,
        'sectionName': sectionName,
      });

      // NEW: Trigger Push Notification
      FCMService.sendNotification(
        recipientUid: adviserUid,
        title: 'New Join Request',
        body: '$studentName requested to join section: $sectionName',
        data: {'type': 'join_request', 'studentUid': studentUid},
      );
      return docRef.id;
    } catch (e) {
      debugPrint('Error sending notification to teacher: $e');
      rethrow; // Pass error up to handle UI feedback
    }
  }

  Future<void> _cancelRequest(String sectionName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request?'),
        content: Text('Do you want to cancel your request to join $sectionName? This will allow you to send a new request.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final firestore = FirebaseFirestore.instance;
      final studentDoc = await firestore.collection('students').doc(user.uid).get();
      final studentData = studentDoc.data() ?? {};
      final studentName = studentData['name'] ?? 'Student';
      final adviserUid = _sectionOwners[sectionName];
      
      // Try to get tracked Message ID from Firestore
      final requestIds = studentData['requestIds'] as Map<String, dynamic>?;
      final msgId = requestIds?[sectionName] as String?;
      bool notified = false;

      // 1. Notify Teacher
      if (adviserUid != null) {
        try {
          if (msgId != null) {
             // STRATEGY A: Direct Target (Best)
             final docRef = FirebaseFirestore.instance
                .collection('teachers')
                .doc(adviserUid)
                .collection('inbox')
                .doc(msgId);
                
             final docSnapshot = await docRef.get();
             if (docSnapshot.exists) {
                await docRef.update({
                  'title': 'Request Cancelled',
                  'message': '$studentName cancelled their request to join $sectionName.',
                  'type': 'general', // Removes Accept/Deny buttons
                  'read': false,     // Marks as unread so teacher sees it
                  'timestamp': DateTime.now().toIso8601String(),
                });
                notified = true;
                debugPrint('Cancelled using ID tracking');
             }
          }

          if (!notified) {
             // STRATEGY B: Fallback Query (Legacy)
             final query = await FirebaseFirestore.instance
                .collection('teachers')
                .doc(adviserUid)
                .collection('inbox')
                .where('studentUid', isEqualTo: user.uid)
                .where('sectionName', isEqualTo: sectionName)
                .where('type', isEqualTo: 'join_request')
                .get();

            if (query.docs.isNotEmpty) {
              for (var doc in query.docs) {
                await doc.reference.update({
                  'title': 'Request Cancelled',
                  'message': '$studentName cancelled their request to join $sectionName.',
                  'type': 'general', 
                  'read': false,    
                  'timestamp': DateTime.now().toIso8601String(),
                });
              }
              notified = true;
            } else {
               // Strategy C: Create New Notification if original missing
               await FirebaseFirestore.instance
                .collection('teachers')
                .doc(adviserUid)
                .collection('inbox')
                .add({
                  'title': 'Request Cancelled',
                  'message': '$studentName cancelled their request to join $sectionName.',
                  'timestamp': DateTime.now().toIso8601String(),
                  'read': false,
                  'type': 'general',
                  'studentUid': user.uid,
                  'sectionName': sectionName,
                });
               notified = true;

               // NEW: Trigger Push Notification
               FCMService.sendNotification(
                 recipientUid: adviserUid,
                 title: 'Request Cancelled',
                 body: '$studentName cancelled their request to join $sectionName.',
                 data: {'type': 'request_cancelled'},
               );
            }
          }
        } catch (e) {
          debugPrint('Error notifying teacher of cancellation: $e');
        }
      } else {
         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Warning: Could not notify adviser (Adviser info missing).')),
            );
         }
      }

      // 2. Clear Cloud Pending Status & ID
      await FirebaseFirestore.instance.collection('students').doc(user.uid).update({
        'pendingRequests': FieldValue.arrayRemove([sectionName]),
        'requestIds.$sectionName': FieldValue.delete(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(notified 
              ? 'Request for $sectionName cancelled. Adviser notified.'
              : 'Request for $sectionName cancelled locally.' // Fallback msg
           )),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Section'),
        backgroundColor: HexColor("#116754"),
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isMobile = width <= 600;
          final isDesktop = width > 900;

          return RefreshIndicator(
            onRefresh: _loadData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 16 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title Row removed as it's now in AppBar
                    Text(
                      'Search and request to join an adviser\'s section',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search sections...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_filteredSections.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 80,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _allSections.isEmpty
                                    ? 'No sections available'
                                    : 'No sections found',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (isDesktop)
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 100,
                        ),
                        itemCount: _filteredSections.length,
                        itemBuilder: (context, index) => _buildSectionItem(_filteredSections[index], width),
                      )
                    else
                      Column(
                        children: _filteredSections.map((section) => _buildSectionItem(section, width)).toList(),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionItem(String section, double screenWidth) {
    final isPending = _pendingRequests.contains(section);
    final isAssigned = _assignedSections.contains(section);
    final isMobile = screenWidth < 600;

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
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                  backgroundImage: _sectionThumbnails[section] != null
                      ? MemoryImage(base64Decode(_sectionThumbnails[section]!))
                      : (_sectionImageUrls[section] != null
                          ? NetworkImage(_sectionImageUrls[section]!)
                          : null) as ImageProvider?,
                  child: (_sectionThumbnails[section] == null && _sectionImageUrls[section] == null)
                      ? Icon(Icons.class_, color: HexColor("#116754"), size: 24)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    section,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isAssigned)
                    Text(
                      'Already assigned',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.green[700],
                      ),
                    )
                  else if (isPending)
                    Text(
                      'Request pending',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.orange[700],
                      ),
                    ),
                ],
              ),
            ),
            if (!isAssigned && !isPending)
              ElevatedButton(
                onPressed: () => _sendRequest(section, screenWidth),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HexColor("#116754"),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Request'),
              )
            else if (isPending)
              TextButton(
                onPressed: () => _cancelRequest(section),
                child: Text(
                  isMobile ? 'Cancel' : 'Pending (Tap to Cancel)',
                  style: TextStyle(color: Colors.orange[700], fontSize: 13),
                  textAlign: TextAlign.end,
                ),
              )
            else
              TextButton(
                onPressed: null,
                child: Text(
                  'Assigned',
                  style: TextStyle(color: Colors.green[700]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendRequest(String sectionName, double screenWidth) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firestore = FirebaseFirestore.instance;
    final studentDoc = await firestore.collection('students').doc(user.uid).get();
    final studentName = studentDoc.data()?['name'] ?? 'Student';

    // Identify owner from our map
    final String? sectionOwnerUid = _sectionOwners[sectionName];

    if (sectionOwnerUid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Could not find teacher for this section')),
        );
      }
      return;
    }
    
    // Check if student already has a pending request
    if (_pendingRequests.isNotEmpty) {
      if (mounted) {
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
                  border: Border.all(color: Colors.orange.shade200, width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.info_outline, size: 48, color: Colors.orange.shade700),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Request Pending',
                      style: TextStyle(
                        fontSize: 22, 
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'You can only have one pending request at a time.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please cancel your existing request if you want to join a different section.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
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
      }
      return;
    }

    // Check if student is already assigned to ANY section
    if (_assignedSections.isNotEmpty) {
      if (mounted) {
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
                     'Already Assigned',
                     style: TextStyle(
                       fontSize: 22, 
                       fontWeight: FontWeight.bold,
                       color: Colors.amber.shade900,
                     ),
                   ),
                   const SizedBox(height: 16),
                   const Text(
                     'You cannot join a new section because you are currently assigned to one.',
                     textAlign: TextAlign.center,
                     style: TextStyle(fontSize: 16, height: 1.5),
                   ),
                   const SizedBox(height: 8),
                   Text(
                     'Please ask your adviser to unassign you first.',
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
          )
        );
      }
      return;
    }

    // Check if request already exists (locally is fine for blocking spam)
    if (_pendingRequests.contains(sectionName)) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request already sent')),
        );
      }
      return;
    }

    try {
      // 1. Send to Teacher's Firestore Inbox
      final msgId = await _addAdviserNotification(sectionOwnerUid, studentName, sectionName, user.uid);

      // 2. Persist Pending Status and Message ID in Cloud
      await FirebaseFirestore.instance.collection('students').doc(user.uid).set({
        'pendingRequests': FieldValue.arrayUnion([sectionName]),
        if (msgId != null) 'requestIds': {sectionName: msgId}
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request sent to $sectionName')),
        );
      }
    } catch (e) {
      debugPrint('Error sending request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send request. Try again.')),
        );
      }
    }
  }
}

