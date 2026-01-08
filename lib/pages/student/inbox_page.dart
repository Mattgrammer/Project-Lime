import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Removed shared_preferences import

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {

  Stream<List<InboxMessage>> _inboxStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('students')
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

  Future<void> _markAsRead(InboxMessage message) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .collection('inbox')
          .doc(message.id)
          .update({'read': true});
    } catch (e) {
      debugPrint('Error marking message as read: $e');
    }
  }

  Future<void> _deleteMessage(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('students')
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
          .collection('students')
          .doc(user.uid)
          .collection('inbox')
          .get();

      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All messages cleared')),
        );
      }
    } catch (e) {
      debugPrint('Error clearing inbox: $e');
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

            return SingleChildScrollView(
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
                              Text(
                                'Inbox',
                                style: TextStyle(
                                  fontSize: isMobile ? 28 : 32,
                                  fontWeight: FontWeight.bold,
                                  color: HexColor("#0F4C7F"),
                                ),
                              ),
                              const SizedBox(height: 4),
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
                          TextButton.icon(
                            onPressed: _clearAll,
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: const Text('Clear All'),
                            style: TextButton.styleFrom(
                              foregroundColor: HexColor("#0F4C7F"),
                            ),
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
                            mainAxisExtent: 140, // Approximate height for message cards
                          ),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            return InkWell(
                              onTap: () => _markAsRead(message),
                              borderRadius: BorderRadius.circular(12),
                              child: _buildMessageCard(message, _formatTime(message.timestamp)),
                            );
                          },
                        )
                      else
                        ...messages.asMap().entries.map((entry) {
                          final message = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              onTap: () => _markAsRead(message),
                              borderRadius: BorderRadius.circular(12),
                              child: _buildMessageCard(message, _formatTime(message.timestamp)),
                            ),
                          );
                        }),
                  ],
                ),
              ),
            );
          },
        );
      },
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

  Widget _buildMessageCard(InboxMessage msg, String time) {
    final String title = msg.title;
    final String message = msg.message;
    final bool isUnread = !msg.read;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUnread ? HexColor("#0F4C7F").withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUnread
              ? HexColor("#0F4C7F").withValues(alpha: 0.2)
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
                backgroundColor: HexColor("#0F4C7F").withValues(alpha: 0.1),
                child: Icon(
                  Icons.notifications,
                  color: HexColor("#0F4C7F"),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      time,
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
                onPressed: () => _deleteMessage(msg.id),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class InboxMessage {
  final String id;
  final String title;
  final String message;
  final String timestamp;
  bool read;
  final String type;

  InboxMessage({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.read,
    required this.type,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'timestamp': timestamp,
      'read': read,
      'type': type,
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
    );
  }
}