import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class BugReportDialog extends StatefulWidget {
  final String userType;
  const BugReportDialog({super.key, required this.userType});

  @override
  State<BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<BugReportDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  // IMPORTANT: Replace this with your actual Formspree ID from https://formspree.io
  final String _formspreeId = "mqeprzew"; 

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    if (title.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.displayName ?? 'Anonymous';
      final userId = user?.uid ?? 'anonymous';
      final deviceInfo = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

      // 1. Log to Firestore (Private detailed record)
      await FirebaseFirestore.instance.collection('bug_reports').add({
        'userId': userId,
        'userName': userName,
        'userType': widget.userType,
        'title': title,
        'description': description,
        'deviceInfo': deviceInfo,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      // 2. Silent Email via Formspree (Cleaner formatting)
      if (_formspreeId != "YOUR_FORM_ID_HERE") {
        // CLEANER FORMATTING: Embed technical info in the message string
        final cleanMessage = 
          'Bug Report Description:\n'
          '$description\n\n'
          '--- System Information ---\n'
          'User: $userName\n'
          'Status: ${widget.userType}\n'
          'Platform: ${Platform.operatingSystem}';

        final response = await http.post(
          Uri.parse('https://formspree.io/f/$_formspreeId'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'subject': 'LIME Bug Report: $title',
            'email': user?.email ?? 'anonymous@lime.app',
            'message': cleanMessage,
            'UserName': userName,
            'UserType': widget.userType,
          }),
        );

        if (response.statusCode != 200 && response.statusCode != 201) {
          throw 'Failed to send email. Status: ${response.statusCode} - ${response.body}';
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bug report sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.bug_report, color: HexColor("#116754")),
          const SizedBox(width: 10),
          const Text('Report a Bug'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Found something wrong? Tell us about it and we\'ll fix it right away.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Bug Title',
                  hintText: 'e.g., App crashes on Home page',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'Please provide details...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitReport,
          style: ElevatedButton.styleFrom(
            backgroundColor: HexColor("#116754"),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isSubmitting 
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Submit Report'),
        ),
      ],
    );
  }
}
