import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'student/student_profile.dart';
import 'teacher/teacher_profile.dart';

class ProfileRouter extends StatefulWidget {
  const ProfileRouter({super.key});

  @override
  State<ProfileRouter> createState() => _ProfileRouterState();
}

class _ProfileRouterState extends State<ProfileRouter> {
  bool _isLoading = true;
  String? _userType;
  bool _needsCompleteProfile = false;

  @override
  void initState() {
    super.initState();
    _checkUserType();
    
    // Safety timeout: If still loading after 5 seconds, something is wrong.
    // Try to force a decision or show an error.
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _isLoading && _userType == null) {
        debugPrint('ProfileRouter: Loading timeout reached.');
        setState(() {
          _isLoading = false;
        });
      }
    });
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

    // Try to get from cache first for instant routing
    final prefs = await SharedPreferences.getInstance();
    final cachedUserType = prefs.getString('cached_user_type_${user.uid}');
    
    if (cachedUserType != null) {
      if (mounted) {
        setState(() {
          _userType = cachedUserType;
          _isLoading = false;
        });
      }
      // Continue refreshing in background to ensure data is up to date
      _refreshUserType(user, prefs);
      return;
    }

    await _refreshUserType(user, prefs);
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

      if (teacherDoc.exists) {
        newUserType = 'Teacher';
      } else if (studentDoc.exists) {
        final data = studentDoc.data();
        if (data != null) {
          final type = data['userType'] as String?;
          final detailsSubmitted = data['detailsSubmitted'] as bool? ?? false;
          
          if (type == null || !detailsSubmitted) {
            newNeedsCompleteProfile = true;
          } else {
            newUserType = type;
          }
        }
      }

      // Update cache
      if (newUserType != null) {
        await prefs.setString('cached_user_type_${user.uid}', newUserType);
      }

      if (mounted) {
        setState(() {
          _userType = newUserType;
          _needsCompleteProfile = newNeedsCompleteProfile;
          _isLoading = false;
        });
      }
      
      // If after checking both collections we still have no user type,
      // and it's not a "needs complete" case, then the user record is missing.
      if (newUserType == null && !newNeedsCompleteProfile) {
        debugPrint('ProfileRouter: User not found in either collection.');
        // Optional: Force logout or redirect to a "Finish Setup" page
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

  @override
  Widget build(BuildContext context) {
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

    // Route based on user type
    if (_needsCompleteProfile) {
      return const ProfileTeacherPage();
    }

    if (_userType == 'Student') {
      return const ProfileStudentPage();
    } else if (_userType == 'Teacher') {
      return const ProfileTeacherPage();
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

