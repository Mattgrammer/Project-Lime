import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'student/student_profile.dart';
import 'teacher/teacher_profile.dart';
import 'suspended_page.dart';
import '../widgets/pin_gate.dart';
import '../widgets/warning_dialog.dart';

class ProfileRouter extends StatefulWidget {
  const ProfileRouter({super.key});

  @override
  State<ProfileRouter> createState() => _ProfileRouterState();
}

class _ProfileRouterState extends State<ProfileRouter> {
  bool _isLoading = true;
  String? _userType;
  bool _needsCompleteProfile = false;
  bool _isSuspended = false;
  bool _isWarned = false;
  String? _warnedMessage;
  bool _warningDismissed = false;
  bool _warningDialogShowing = false;
  bool _persistenceLoaded = false;

  StreamSubscription? _userSub;
  String? _dismissedWarningMessage;

  String _normalize(String? s) {
    if (s == null) return '';
    return s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  void initState() {
    super.initState();
    _checkUserType();
    
    // Safety timeout: If still loading after 5 seconds, something is wrong.
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _isLoading && _userType == null) {
        debugPrint('ProfileRouter: Loading timeout reached.');
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  Future<void> _checkUserType() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    // 1. ALWAYS load persistence first with fallback
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // Critical for Windows to ensure fresh data from disk
      
      if (mounted) {
        final key = 'LIME_DISMISSED_WARNING_V3_${user.uid}';
        final saved = prefs.getString(key);
        _dismissedWarningMessage = saved;
        debugPrint('ProfileRouter: Loaded dismissal message: "$saved"');
        setState(() {
          _persistenceLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('ProfileRouter: Error loading prefs: $e');
      if (mounted) {
        setState(() {
          _persistenceLoaded = true; // Proceed anyway to avoid getting stuck
        });
      }
    }

    // 2. Try to get from cache for instant routing
    final cachedUserType = prefs?.getString('cached_user_type_${user.uid}');
    if (cachedUserType != null) {
      if (mounted) {
        setState(() {
          _userType = cachedUserType;
          _isLoading = false;
        });
      }
      // Continue refreshing in background
      if (prefs != null) _refreshUserType(user, prefs);
      return;
    }

    if (prefs != null) {
      await _refreshUserType(user, prefs);
    } else {
      // Fallback if prefs failed
      final freshPrefs = await SharedPreferences.getInstance();
      await _refreshUserType(user, freshPrefs);
    }
  }

  Future<void> _refreshUserType(User user, SharedPreferences prefs) async {
    try {
      // Parallelize checks for performance
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('teachers').doc(user.uid).get(),
        FirebaseFirestore.instance.collection('students').doc(user.uid).get(),
      ]);

      final teacherDoc = results[0];
      final studentDoc = results[1];

      String? newUserType;
      bool newNeedsCompleteProfile = false;
      bool localIsSuspended = false;
      bool localIsWarned = false;
      String? localWarnedMessage;

      if (teacherDoc.exists) {
        newUserType = 'Teacher';
        final data = teacherDoc.data();
        if (data != null) {
          if (data['isSuspended'] == true || data['suspended'] == true) {
            localIsSuspended = true;
          }
          if (data['isWarned'] == true || data['warned'] == true) {
            localIsWarned = true;
            localWarnedMessage = data['warnedMessage'] as String? ?? "You have a warning for violating rules.";
          }
        }
      } else if (studentDoc.exists) {
        final data = studentDoc.data();
        if (data != null) {
          if (data['isSuspended'] == true || data['suspended'] == true) {
            localIsSuspended = true;
          }
          if (data['isWarned'] == true || data['warned'] == true) {
            localIsWarned = true;
            localWarnedMessage = data['warnedMessage'] as String? ?? "You have a warning for violating rules.";
          }
          final type = data['userType'] as String?;
          final detailsSubmitted = data['detailsSubmitted'] as bool? ?? false;
          
          if (type == null || !detailsSubmitted) {
            newNeedsCompleteProfile = true;
          } else {
            newUserType = type;
          }
        }
      }

      // Final state preparation
      bool finalIsSuspended = localIsSuspended;
      bool finalIsWarned = localIsWarned;
      String? finalWarnedMessage = localWarnedMessage;
      bool finalWarningDismissed = false;

      // Check if the warning was already dismissed
      final String normalizedCurrent = _normalize(finalWarnedMessage);
      final String normalizedDismissed = _normalize(_dismissedWarningMessage);
      
      if (finalIsWarned && normalizedCurrent.isNotEmpty && normalizedCurrent == normalizedDismissed) {
        finalWarningDismissed = true;
      }

      // Update cache
      if (newUserType != null) {
        await prefs.setString('cached_user_type_${user.uid}', newUserType);
      }

      if (mounted) {
        setState(() {
          _userType = newUserType;
          _needsCompleteProfile = newNeedsCompleteProfile;
          _isSuspended = finalIsSuspended;
          _isWarned = finalIsWarned;
          _warnedMessage = finalWarnedMessage;
          _warningDismissed = finalWarningDismissed;
          _isLoading = false;
        });
      }
      
      // Init stream AFTER state is settled
      _initUserStream(user, teacherDoc.exists ? 'teachers' : 'students');

      
      // If after checking both collections we still have no user type,
      // and it's not a "needs complete" case, then the user record is missing.
      if (newUserType == null && !newNeedsCompleteProfile) {
        debugPrint('ProfileRouter: User not found in either collection.');
      }
    } catch (e) {
      debugPrint('Error loading user type: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _initUserStream(User user, String collection) {
    _userSub?.cancel();
    _userSub = FirebaseFirestore.instance.collection(collection).doc(user.uid).snapshots().listen((doc) {
      if (doc.exists && mounted) {
        final data = doc.data();
        final suspended = data?['isSuspended'] == true || data?['suspended'] == true;
        final warned = data?['isWarned'] == true || data?['warned'] == true;
        final message = data?['warnedMessage'] as String? ?? "You have a warning for violating rules.";
        
        // Only update state if something actually changed
        if (suspended != _isSuspended || warned != _isWarned || message != _warnedMessage) {
          setState(() {
            _isSuspended = suspended;
            _isWarned = warned;
            _warnedMessage = message;
            
            // Check dismissal status whenever warned is true
            if (warned) {
              final String normNew = _normalize(message);
              final String normStored = _normalize(_dismissedWarningMessage);
              
              if (normNew == normStored) {
                _warningDismissed = true;
              } else {
                // message changed, show dialog again
                _warningDismissed = false;
                _warningDialogShowing = false;
              }
            } else {
              // Admin cleared the warning
              _warningDismissed = false;
              _warningDialogShowing = false;
            }
          });
        }
      }
    });
  }


  void _showWarningDialogIfNeeded() {
    if (_isWarned && _persistenceLoaded && !_warningDismissed && !_warningDialogShowing && mounted) {
      _warningDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _persistenceLoaded && !_warningDismissed && _isWarned) {
          showAccountWarning(context, _warnedMessage ?? "Account Warning", () async {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;
            
            // Persist the dismissal
            final messageToSave = _warnedMessage ?? "You have a warning for violating rules.";
            
            try {
              final prefs = await SharedPreferences.getInstance();
              final key = 'LIME_DISMISSED_WARNING_V3_${user.uid}';
              
              await prefs.setString(key, messageToSave);
              await prefs.reload(); // Ensure it's on disk
            } catch (e) {
              debugPrint('ProfileRouter: Failed to save dismissal: $e');
            }

            if (mounted) {
              setState(() {
                _dismissedWarningMessage = messageToSave;
                _warningDismissed = true;
                _warningDialogShowing = false;
              });
            }
          });
        } else {
          _warningDialogShowing = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSuspended) {
      return const SuspendedPage();
    }
    if (_isLoading && _userType == null) {
      return Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                HexColor("#2a7925"),
                HexColor("#abad23"),
              ],
            ),
          ),
          child: Center(
            child: CircularProgressIndicator(
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }

    // Show warning dialog if needed (NOW moved after loading check)
    _showWarningDialogIfNeeded();

    // Route based on user type
    if (_needsCompleteProfile) {
      return const ProfileTeacherPage();
    }

    if (_userType == 'Student') {
      return const PinGate(child: ProfileStudentPage());
    } else if (_userType == 'Teacher') {
      return const PinGate(child: ProfileTeacherPage());
    } else {
      // Fallback for missing user record or timeout
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: HexColor("#116754")),
              const SizedBox(height: 16),
              const Text(
                'Account Setup Incomplete',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Please try logging in again or contact support.'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                style: ElevatedButton.styleFrom(backgroundColor: HexColor("#116754")),
                child: const Text('Back to Login', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
  }
}
