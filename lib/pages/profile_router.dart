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
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(HexColor("#0F4C7F")),
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
    } else {
      // Default to teacher profile page (which handles universal setup for new users)
      return const ProfileTeacherPage();
    }
  }
}

