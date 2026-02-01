import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match')),
      );
      return;
    }

    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    setState(() => _isLoading = true);
    debugPrint('ChangePasswordDialog: Starting process...');

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        debugPrint('ChangePasswordDialog: Error - User not found');
        throw Exception('User not logged in or email missing');
      }

      // Capture messenger and navigator before async gap
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      // Check connectivity explicitly
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        throw Exception('No internet connection detected. Please check your network.');
      }

      await user.reload().timeout(
        const Duration(seconds: 10), 
        onTimeout: () => debugPrint('Reload timed out, continuing...')
      );
      
      // Small delay to let native state settle on Windows
      await Future.delayed(const Duration(milliseconds: 500));

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      try {
        debugPrint('ChangePasswordDialog: Attempting Method A (Re-authentication)...');
        // Method A: Standard Re-auth with snappier timeout
        await user.reauthenticateWithCredential(credential).timeout(
          const Duration(seconds: 10), // Increased timeout
          onTimeout: () => throw Exception('Method A Timeout'),
        );
      } catch (e) {
        debugPrint('ChangePasswordDialog: Method A failed/timed out ($e), trying Fallback Method B...');
        // Small delay before retry
        await Future.delayed(const Duration(milliseconds: 800));
        
        // Method B: Sign-in fallback (refreshes session tokens)
        await FirebaseAuth.instance.signInWithCredential(credential).timeout(
          const Duration(seconds: 10), // Increased timeout
          onTimeout: () => throw Exception('Authentication timed out. Please check your internet signal.'),
        );
      }

      debugPrint('ChangePasswordDialog: Updating password...');
      // 2. Update password
      await user.updatePassword(newPassword).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('ChangePasswordDialog: Password update timed out');
          throw Exception('Password update timed out. Please try again.');
        },
      );

      debugPrint('ChangePasswordDialog: Success!');
      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Password changed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('ChangePasswordDialog: FirebaseAuthException code=${e.code}');
      String errorMessage = 'Error updating password';
      switch (e.code) {
        case 'wrong-password':
          errorMessage = 'Incorrect current password';
          break;
        case 'weak-password':
          errorMessage = 'The password provided is too weak';
          break;
        case 'requires-recent-login':
          errorMessage = 'Please logout and login again before changing password';
          break;
        case 'user-mismatch':
          errorMessage = 'User credentials do not match current session';
          break;
        case 'user-not-found':
          errorMessage = 'User account not found';
          break;
        default:
          errorMessage = 'Auth Error (${e.code}): ${e.message}';
          // Force detailed logging
          debugPrint('Full Firebase Error: $e');
          debugPrint('Stack: ${StackTrace.current}');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } catch (e) {
      debugPrint('ChangePasswordDialog: Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      debugPrint('ChangePasswordDialog: Process finished, clearing loading state...');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock_reset_rounded, color: HexColor("#116754")),
          const SizedBox(width: 10),
          const Text('Change Password'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _currentPasswordController,
              obscureText: _obscureCurrent,
              decoration: InputDecoration(
                labelText: 'Current Password',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newPasswordController,
              obscureText: _obscureNew,
              decoration: InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'Confirm New Password',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _changePassword,
          style: ElevatedButton.styleFrom(
            backgroundColor: HexColor("#116754"),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isLoading 
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Change Password'),
        ),
      ],
    );
  }
}
