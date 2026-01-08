import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:lime/utils/delete_account.dart';

class ProcessingDeletionPage extends StatefulWidget {
  final String password;

  const ProcessingDeletionPage({super.key, required this.password});

  @override
  State<ProcessingDeletionPage> createState() => _ProcessingDeletionPageState();
}

class _ProcessingDeletionPageState extends State<ProcessingDeletionPage> {
  String _status = 'Securing connection...';

  @override
  void initState() {
    super.initState();
    _startDeletion();
  }

  Future<void> _startDeletion() async {
    try {
      if (!mounted) return;
      setState(() => _status = 'Stopping background services...');
      
      // Extended delay to ensure all dashboard streams are killed and platform channels clear
      await Future.delayed(const Duration(milliseconds: 3000));

      if (!mounted) return;
      setState(() => _status = 'Verifying security credentials...');
      
      await deleteUserAccount(widget.password);

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/signin', (_) => false);
    } catch (e) {
      if (!mounted) return;
      
      String errorMessage = 'Error deleting account';
      final errorStr = e.toString().toLowerCase();

      if (errorStr.contains('wrong-password') || errorStr.contains('invalid-credential')) {
        errorMessage = 'Incorrect password. Please try again.';
      } else if (errorStr.contains('requires-recent-login') || errorStr.contains('security timeout')) {
        errorMessage = 'Security timeout. Please logout and login again.';
      } else {
        errorMessage = 'Failed: ${e.toString().replaceAll('Exception: ', '')}';
      }

      // Go back to home and show error
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: HexColor("#0F4C7F"),
            ),
            const SizedBox(height: 24),
            Text(
              _status,
              style: TextStyle(
                fontSize: 18,
                color: HexColor("#0F4C7F"),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please do not close the app',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
