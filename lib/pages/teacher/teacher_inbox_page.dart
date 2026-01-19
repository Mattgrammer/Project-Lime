import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../widgets/guide_pointer.dart';

class TeacherInboxPage extends StatefulWidget {
  const TeacherInboxPage({super.key});

  @override
  State<TeacherInboxPage> createState() => TeacherInboxPageState();
}

class TeacherInboxPageState extends State<TeacherInboxPage> {

  @override
  void dispose() {
    GuidePointer.dismiss();
    super.dispose();
  }


  Stream<List<InboxMessage>> _inboxStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('teachers')
        .doc(user.uid)
        .collection('inbox')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // Inject doc ID
        return InboxMessage.fromJson(data);
      }).toList();
    });
  }

  Future<void> _handleJoinRequest(InboxMessage message, bool accept) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final String? studentUid = message.studentUid;
    final String? sectionName = message.sectionName;

    if (studentUid == null || sectionName == null) return;

    if (accept) {
      // Add student to section (local & cloud)
      // Note: Logic duplicated from my_classes_page but necessary logic flow
      // We rely on Firestore 'sections' array in student doc mainly now
      
      try {
        // Teacher side: Add to section students list (persisted in section_detail logic)
        // Here we just update the Student's 'sections' array in Firestore
        await FirebaseFirestore.instance.collection('students').doc(studentUid).set(
            {'sections': FieldValue.arrayUnion([sectionName])},
            SetOptions(merge: true),
        );

        // Notify Student
         await FirebaseFirestore.instance.collection('students').doc(studentUid).collection('inbox').add({
          'title': 'Request Accepted',
          'message': 'Your request to join $sectionName has been accepted!',
          'timestamp': DateTime.now().toIso8601String(),
          'read': false,
          'type': 'request_response',
          'sectionName': sectionName,
        });

        // Clear Pending Request in Student record
        await FirebaseFirestore.instance.collection('students').doc(studentUid).update({
          'pendingRequests': FieldValue.arrayRemove([sectionName])
        });

      } catch (e) {
        debugPrint('Error accepting request: $e');
      }
    } else {
        // Notify Student of denial
         await FirebaseFirestore.instance.collection('students').doc(studentUid).collection('inbox').add({
          'title': 'Request Denied',
          'message': 'Your request to join $sectionName has been denied.',
          'timestamp': DateTime.now().toIso8601String(),
          'read': false,
          'type': 'request_response',
          'sectionName': sectionName,
        });

        // Clear Pending Request in Student record
        await FirebaseFirestore.instance.collection('students').doc(studentUid).update({
          'pendingRequests': FieldValue.arrayRemove([sectionName])
        });
    }

    // Delete request message from Inbox
    await _deleteMessage(message.id);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? 'Request accepted' : 'Request denied')),
      );
    }
  }

  Future<void> _markAsRead(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('teachers')
          .doc(user.uid)
          .collection('inbox')
          .doc(id)
          .update({'read': true});
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }
  }

  Future<void> _deleteMessage(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('teachers')
          .doc(user.uid)
          .collection('inbox')
          .doc(id)
          .delete();
    } catch (e) {
      debugPrint('Error deleting message: $e');
    }
  }

  Future<void> _clearAll() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      final snapshot = await FirebaseFirestore.instance
          .collection('teachers')
          .doc(user.uid)
          .collection('inbox')
          .get();
      
      int deniedCount = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        
        // Auto-deny pending join requests
        if (data['type'] == 'join_request') {
           final studentUid = data['studentUid'];
           final sectionName = data['sectionName'];
           
           if (studentUid != null && sectionName != null) {
              // Notify Student of denial
              final studentInboxRef = FirebaseFirestore.instance
                  .collection('students')
                  .doc(studentUid)
                  .collection('inbox')
                  .doc();
              
              batch.set(studentInboxRef, {
                'title': 'Request Denied',
                'message': 'Your request to join $sectionName has been denied (Teacher cleared inbox).',
                'timestamp': DateTime.now().toIso8601String(),
                'read': false,
                'type': 'request_response',
                'sectionName': sectionName, 
              });

              // Clear Pending Request in Student record via batch
              batch.update(FirebaseFirestore.instance.collection('students').doc(studentUid), {
                'pendingRequests': FieldValue.arrayRemove([sectionName])
              });
              
              deniedCount++;
           }
        }
        
        // Delete the message
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      
      if (mounted) {
        String msg = 'All messages cleared';
        if (deniedCount > 0) {
          msg += ' ($deniedCount pending request${deniedCount == 1 ? '' : 's'} denied)';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      debugPrint('Error clearing inbox: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error clearing inbox')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = width <= 600;
        final isDesktop = width > 900;

        return StreamBuilder<List<InboxMessage>>(
          stream: _inboxStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final messages = snapshot.data ?? [];
            final unreadCount = messages.where((m) => !m.read).length;

            return Container(
              color: Colors.grey[50],
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 16 : 24),
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
                                if (!isMobile) ...[
                                  Text(
                                    'Inbox',
                                    style: TextStyle(
                                      fontSize: isMobile ? 28 : 32,
                                      fontWeight: FontWeight.bold,
                                      color: HexColor("#116754"),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                Text(
                                  unreadCount == 0
                                      ? 'No unread messages'
                                      : '$unreadCount unread message${unreadCount > 1 ? 's' : ''}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                              if (messages.isNotEmpty)
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: _clearAll,
                                      icon: const Icon(Icons.clear_all, size: 18),
                                      label: const Text('Clear All'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: HexColor("#116754"),
                                      ),
                                    ),
                                  ],
                                ),
                        ],
                      ),
                      const SizedBox(height: 24),
    
                      if (messages.isEmpty)
                        SizedBox(
                          height: constraints.maxHeight * 0.6,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.inbox,
                                  size: 80,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No messages',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        if (isDesktop)
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 12,
                              mainAxisExtent: 180, // Approximate height for message cards
                            ),
                            itemCount: messages.length,
                            itemBuilder: (context, index) => _buildMessageCard(messages[index], index),
                          )
                        else
                          ...messages.asMap().entries.map((entry) {
                            final index = entry.key;
                            final message = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildMessageCard(message, index),
                            );
                          }),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMessageCard(InboxMessage message, int index) {
    final isJoinRequest = message.type == 'join_request';
    final isUnread = !message.read;

    return InkWell(
      onTap: isUnread ? () => _markAsRead(message.id) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUnread ? HexColor("#116754").withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUnread
                ? HexColor("#116754").withValues(alpha: 0.2)
                : Colors.grey[300]!,
            width: isUnread ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                  child: Icon(
                    isJoinRequest ? Icons.person_add : Icons.notifications,
                    color: HexColor("#116754"),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isUnread)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: HexColor("#e63946"),
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.redAccent.withValues(alpha: 0.7),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _deleteMessage(message.id),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              message.message,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
            if (isJoinRequest) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _handleJoinRequest(message, false),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('Deny'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _handleJoinRequest(message, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HexColor("#116754"),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Accept'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 7) {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      } else if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return 'Recently';
    }
  }
}

class InboxMessage {
  final String id;
  final String title;
  final String message;
  final String timestamp;
  bool read;
  final String type;
  final String? studentUid;
  final String? studentName;
  final String? sectionName;

  InboxMessage({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.read,
    required this.type,
    this.studentUid,
    this.studentName,
    this.sectionName,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'timestamp': timestamp,
      'read': read,
      'type': type,
      if (studentUid != null) 'studentUid': studentUid,
      if (studentName != null) 'studentName': studentName,
      if (sectionName != null) 'sectionName': sectionName,
    };
  }

  factory InboxMessage.fromJson(Map<String, dynamic> json) {
    return InboxMessage(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? 'Notification',
      message: json['message'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? DateTime.now().toIso8601String(),
      read: json['read'] as bool? ?? false,
      type: json['type'] as String? ?? 'general',
      studentUid: json['studentUid'] as String?,
      studentName: json['studentName'] as String?,
      sectionName: json['sectionName'] as String?,
    );
  }
}


