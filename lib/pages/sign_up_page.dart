import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

// Import the profile router
import 'profile_router.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  bool _isProcessing = false;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ?? HexColor("#116754"),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ================= SIGN UP LOGIC =================
  Future<void> _handleSignUp() async {
    if (_isProcessing) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (name.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showSnackBar('Please fill in all fields',
          backgroundColor: Colors.redAccent);
      return;
    }

    if (password.length < 6) {
      _showSnackBar('Password must be at least 6 characters',
          backgroundColor: Colors.redAccent);
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar('Passwords do not match',
          backgroundColor: Colors.redAccent);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      debugPrint('🔥 STEP 1: Starting signup...');

      // 🔐 CREATE USER
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      debugPrint('✅ STEP 2: User created in Firebase Auth');

      final user = credential.user;
      if (user == null) {
        throw Exception('User creation failed - no user returned');
      }

      // 👤 UPDATE DISPLAY NAME
      debugPrint('🔄 STEP 3: Updating display name...');
      await user.updateDisplayName(name);
      await user.reload();
      debugPrint('✅ STEP 4: Display name updated: $name');

      // ☁ SAVE MINIMAL PROFILE TO FIRESTORE
      debugPrint('🔄 STEP 5: Saving to Firestore (minimal)...');
      final Map<String, dynamic> docData = {
        'uid': user.uid,
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await _firestore.collection('students').doc(user.uid).set(docData);
      debugPrint('✅ STEP 6: User data saved to Firestore');

      if (!mounted) return;
      _showSnackBar('Account created successfully!');

      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const ProfileRouter(),
        ),
            (route) => false,
      );

    } on FirebaseAuthException catch (e) {
      String message = 'Signup failed';
      if (e.code == 'email-already-in-use') {
        message = 'Email already in use';
      } else if (e.code == 'weak-password') {
        message = 'Password is too weak';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address';
      }
      _showSnackBar(message, backgroundColor: Colors.redAccent);
      if (mounted) setState(() => _isProcessing = false);
    } catch (e) {
      _showSnackBar('Error: ${e.toString()}', backgroundColor: Colors.redAccent);
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;

        final isTablet = screenWidth > 600 && screenWidth <= 900;
        final isDesktop = screenWidth > 900;

        final maxWidth = isDesktop ? 440.0 : isTablet ? 420.0 : double.infinity;
        final containerPadding = isDesktop ? 24.0 : isTablet ? 20.0 : 16.0;
        final headerPadding = isDesktop ? 32.0 : isTablet ? 28.0 : 24.0;
        final headerFontSize = isDesktop ? 42.0 : isTablet ? 38.0 : 34.0;
        final logoSize = isDesktop ? 160.0 : isTablet ? 150.0 : 140.0;
        final welcomeFontSize = isDesktop ? 38.0 : isTablet ? 34.0 : 30.0;
        final subtitleFontSize = isDesktop ? 20.0 : isTablet ? 19.0 : 18.0;
        final fieldTextSize = isDesktop ? 17.0 : isTablet ? 16.0 : 15.0;
        final fieldSpacing = isDesktop ? 20.0 : isTablet ? 18.0 : 16.0;
        final buttonHeight = isDesktop ? 56.0 : isTablet ? 52.0 : 48.0;
        final iconSize = isDesktop ? 24.0 : isTablet ? 22.0 : 20.0;
        final borderRadius = isDesktop ? 14.0 : isTablet ? 12.0 : 10.0;
        final contentPadding = isDesktop ? 28.0 : isTablet ? 24.0 : 20.0;
        final textFieldPadding = isDesktop ? 16.0 : isTablet ? 14.0 : 12.0;
        final linkFontSize = isDesktop ? 17.0 : isTablet ? 16.0 : 15.0;

        return Scaffold(
          body: Container(
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
              child: Focus(
                focusNode: _focusNode,
                autofocus: true,
                onKeyEvent: (node, event) {
                  final double scrollDelta = 100.0;
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _scrollController.animateTo(
                      (_scrollController.offset + scrollDelta).clamp(0, _scrollController.position.maxScrollExtent),
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.linear,
                    );
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _scrollController.animateTo(
                      (_scrollController.offset - scrollDelta).clamp(0, _scrollController.position.maxScrollExtent),
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.linear,
                    );
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.pageDown) {
                    _scrollController.animateTo(
                      (_scrollController.offset + 400).clamp(0, _scrollController.position.maxScrollExtent),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.pageUp) {
                    _scrollController.animateTo(
                      (_scrollController.offset - 400).clamp(0, _scrollController.position.maxScrollExtent),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.all(containerPadding),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(borderRadius + 6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(vertical: headerPadding),
                          decoration: BoxDecoration(
                            color: HexColor("#116754"),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(borderRadius + 6),
                            ),
                          ),
                          child: Text(
                            'Sign Up',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: headerFontSize,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(
                            top: headerPadding * 0.8,
                            bottom: fieldSpacing * 0.8,
                          ),
                          child: Image.asset(
                            'lib/pages/assets/LIME ASSETS/limelogo.png',
                            height: logoSize,
                            width: logoSize,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.school,
                                size: logoSize,
                                color: HexColor("#116754"),
                              );
                            },
                          ),
                        ),
                        SizedBox(height: fieldSpacing * 0.4),
                        Text(
                          'Welcome!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: HexColor("#116754"),
                            fontSize: welcomeFontSize,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(height: fieldSpacing * 0.3),
                        Text(
                          'Join The Lime Community',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: subtitleFontSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(contentPadding),
                          child: Column(
                            children: [
                              TextField(
                                controller: _nameController,
                                enabled: !_isProcessing,
                                style: TextStyle(fontSize: fieldTextSize),
                                decoration: InputDecoration(
                                  labelText: 'Full Name',
                                  labelStyle: TextStyle(fontSize: fieldTextSize),
                                  prefixIcon: Icon(Icons.person, size: iconSize),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: textFieldPadding,
                                    vertical: textFieldPadding + 4,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(borderRadius),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(borderRadius),
                                    borderSide: BorderSide(
                                      color: Colors.grey[400]!,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(borderRadius),
                                    borderSide: BorderSide(
                                      color: HexColor("#116754"),
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: fieldSpacing),
                              TextField(
                                controller: _emailController,
                                enabled: !_isProcessing,
                                keyboardType: TextInputType.emailAddress,
                                style: TextStyle(fontSize: fieldTextSize),
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  labelStyle: TextStyle(fontSize: fieldTextSize),
                                  prefixIcon: Icon(Icons.email, size: iconSize),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: textFieldPadding,
                                    vertical: textFieldPadding + 4,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(borderRadius),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(borderRadius),
                                    borderSide: BorderSide(
                                      color: Colors.grey[400]!,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(borderRadius),
                                    borderSide: BorderSide(
                                      color: HexColor("#116754"),
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: fieldSpacing),
                              TextField(
                                controller: _passwordController,
                                enabled: !_isProcessing,
                                obscureText: !_passwordVisible,
                                style: TextStyle(fontSize: fieldTextSize),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  labelStyle: TextStyle(fontSize: fieldTextSize),
                                  prefixIcon: GestureDetector(
                                    onTap: () => setState(
                                          () => _passwordVisible = !_passwordVisible,
                                    ),
                                    child: Icon(
                                      _passwordVisible
                                          ? Icons.lock_open
                                          : Icons.lock,
                                      size: iconSize,
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: textFieldPadding,
                                    vertical: textFieldPadding + 4,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(borderRadius),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(borderRadius),
                                    borderSide: BorderSide(
                                      color: Colors.grey[400]!,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(borderRadius),
                                    borderSide: BorderSide(
                                      color: HexColor("#116754"),
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: fieldSpacing),
                              TextField(
                                controller: _confirmPasswordController,
                                enabled: !_isProcessing,
                                obscureText: !_confirmPasswordVisible,
                                style: TextStyle(fontSize: fieldTextSize),
                                decoration: InputDecoration(
                                  labelText: 'Confirm Password',
                                  labelStyle: TextStyle(fontSize: fieldTextSize),
                                  prefixIcon: GestureDetector(
                                    onTap: () => setState(() =>
                                    _confirmPasswordVisible =
                                    !_confirmPasswordVisible),
                                    child: Icon(
                                      _confirmPasswordVisible
                                          ? Icons.lock_open
                                          : Icons.lock,
                                      size: iconSize,
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: textFieldPadding,
                                    vertical: textFieldPadding + 4,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(borderRadius),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(borderRadius),
                                    borderSide: BorderSide(
                                      color: Colors.grey[400]!,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(borderRadius),
                                    borderSide: BorderSide(
                                      color: HexColor("#116754"),
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: fieldSpacing),
                              SizedBox(
                                width: double.infinity,
                                height: buttonHeight,
                                child: ElevatedButton(
                                  onPressed: _isProcessing ? null : _handleSignUp,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: HexColor("#116754"),
                                    disabledBackgroundColor: Colors.grey,
                                    elevation: 2,
                                    shadowColor: HexColor("#116754").withValues(alpha: 0.3),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(buttonHeight / 2),
                                    ),
                                  ),
                                  child: _isProcessing
                                      ? SizedBox(
                                    height: buttonHeight * 0.4,
                                    width: buttonHeight * 0.4,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 3,
                                    ),
                                  )
                                      : Text(
                                    'Create Account',
                                    style: TextStyle(
                                      fontSize: buttonHeight * 0.35,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: fieldSpacing),
                              RichText(
                                text: TextSpan(
                                  text: 'Already have an account? ',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: linkFontSize,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'Sign In',
                                      style: TextStyle(
                                        color: _isProcessing
                                            ? Colors.grey
                                            : HexColor("#116754"),
                                        fontWeight: FontWeight.bold,
                                        fontSize: linkFontSize,
                                        decoration: TextDecoration.underline,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = _isProcessing
                                            ? null
                                            : () => Navigator.pop(context),
                                    ),
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}