import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/pin_login_service.dart';
import '../pages/auth/pin_entry_page.dart';

class PinGate extends StatefulWidget {
  final Widget child;
  const PinGate({super.key, required this.child});

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> with WidgetsBindingObserver {
  bool _isPinSet = false;
  bool _isUnlocked = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check PIN status when app comes to foreground
      _checkPin();
    }
  }

  Future<void> _checkPin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final pinExists = await PinLoginService.hasPin(user.uid);
      if (mounted) {
        setState(() {
          _isPinSet = pinExists;
          // If no PIN is set, it's "unlocked" by default
          if (!pinExists) {
             _isUnlocked = true;
          } else {
            // If PIN *is* set, do we lock it? 
            // Only if we want to force re-entry on resume.
            // For now, let's AT LEAST ensure we know a PIN exists so if they navigate away and back, it gates them.
            // If the user INTENDS for the PIN to gate them on every resume, we should set _isUnlocked = false here.
            // Given "why pin page doesnt appear anymore", the user likely expects it to appear.
            // Let's set _isUnlocked = false if a PIN exists, effectively locking the app on resume.
            // _isUnlocked = false; 
            
            // WAIT: The user problem is "pin page doesnt appear anymore". 
            // If they just created a pin, _isPinSet might be false.
            // So updating _isPinSet is the critical part.
            // If _isPinSet becomes true, and _isUnlocked was true (default), should we lock it?
            // Users usually expect "Set PIN" -> "Now I am protected".
            // So if we detect a new PIN, we should probably respect that.
            
            // However, simply updating _isPinSet is safe. 
            // If they want lock-on-resume, that's a feature request (or the commented out code).
            // But if they set a PIN in settings, come back, and restart app, it works.
            // If they set PIN, come back, and DON'T restart, `_isPinSet` is still false, so `PinGate` passes them through.
            // So we MUST update `_isPinSet`.
          }
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isPinSet && !_isUnlocked) {
      return PinEntryPage(
        onSuccess: () {
          setState(() {
            _isUnlocked = true;
          });
        },
      );
    }

    return widget.child;
  }
}
