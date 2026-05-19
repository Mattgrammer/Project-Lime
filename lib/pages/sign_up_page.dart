import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:lime/services/connectivity_service.dart';

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

  Widget _buildBlob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0.0),
          ],
        ),
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

    // Check internet connection before attempting sign up
    final connectivityService = ConnectivityService();
    if (!connectivityService.isOnline) {
      _showSnackBar('Sorry, you don\'t have internet connection. Please check your network and try again.',
          backgroundColor: Colors.orange);
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
      
      // Check for network-related errors
      if (e.code == 'network-request-failed' || e.code == 'too-many-requests') {
        message = 'Sorry, you don\'t have internet connection. Please check your network and try again.';
      } else if (e.code == 'email-already-in-use') {
        message = 'Email already in use';
      } else if (e.code == 'weak-password') {
        message = 'Password is too weak';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address';
      }
      
      _showSnackBar(message, backgroundColor: Colors.redAccent);
      if (mounted) setState(() => _isProcessing = false);
    } catch (e) {
      // Check if it's a network error
      final errorString = e.toString().toLowerCase();
      String message;
      if (errorString.contains('network') || errorString.contains('socket') || errorString.contains('connection')) {
        message = 'Sorry, you don\'t have internet connection. Please check your network and try again.';
      } else {
        message = 'An error occurred. Please try again.';
      }
      _showSnackBar(message, backgroundColor: Colors.redAccent);
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;


        // Responsive scaling factors
        final isDesktop = screenWidth >= 1100;
        final isTablet = screenWidth >= 600 && screenWidth < 1100;
        final isMobile = screenWidth < 600;

        // Vertical scaling factor - tuned for a more compact height
        final screenHeight = constraints.maxHeight;
        final verticalScale = (screenHeight / 950).clamp(0.65, 1.0);

        // Dynamic width based on a percentage of screen with clamps
        double maxWidth;
        if (isMobile) {
          maxWidth = double.infinity;
        } else if (isTablet) {
          maxWidth = (screenWidth * 0.65).clamp(400.0, 480.0);
        } else {
          maxWidth = (screenWidth * 0.4).clamp(440.0, 480.0); // Slightly slimmer
        }

        final containerPadding = isMobile ? 0.0 : 24.0;
        final headerPadding = (isDesktop ? 18.0 : isTablet ? 14.0 : 12.0) * verticalScale;
        final headerFontSize = (isDesktop ? 34.0 : isTablet ? 30.0 : 28.0) * verticalScale;
        final logoSize = (isDesktop ? 100.0 : isTablet ? 90.0 : 200.0) * verticalScale;
        final welcomeFontSize = (isDesktop ? 30.0 : isTablet ? 26.0 : 34.0) * verticalScale;
        final subtitleFontSize = (isDesktop ? 17.0 : isTablet ? 16.0 : 22.0) * verticalScale;
        final fieldTextSize = (isDesktop ? 15.0 : isTablet ? 14.5 : 14.0) * verticalScale;
        final fieldSpacing = (isDesktop ? 16.0 : isTablet ? 14.0 : 12.0) * verticalScale;
        final buttonHeight = (isDesktop ? 52.0 : isTablet ? 48.0 : 44.0) * verticalScale;
        final iconSize = (isDesktop ? 20.0 : isTablet ? 19.0 : 18.0) * verticalScale;
        final borderRadius = isMobile ? 20.0 : 28.0;
        final contentPadding = (isDesktop ? 36.0 : isTablet ? 30.0 : 24.0) * verticalScale;
        final textFieldPadding = (isDesktop ? 16.0 : isTablet ? 14.0 : 12.0) * verticalScale;
        final linkFontSize = (isDesktop ? 16.0 : isTablet ? 15.0 : 14.0) * (verticalScale > 1.0 ? 1.0 : verticalScale);

        return Scaffold(
          backgroundColor: isMobile ? Colors.white : null,
          appBar: isMobile
              ? AppBar(
                  title: const Text('Sign Up', style: TextStyle(fontWeight: FontWeight.bold)),
                  backgroundColor: HexColor("#116754"),
                  foregroundColor: Colors.white,
                  centerTitle: true,
                  elevation: 0,
                )
              : null,
          body: Stack(
            children: [
              // 1. Base Gradient
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: isMobile
                    ? null
                    : BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            HexColor("#2a7925"),
                            HexColor("#abad23"),
                          ],
                        ),
                      ),
              ),

              // 2. Decorative Blobs (Premium Look)
              if (!isMobile)
                Positioned.fill(
                  child: Stack(
                    children: [
                      Positioned(
                        top: -100,
                        left: -50,
                        child: _buildBlob(
                            screenWidth * 0.4, HexColor("#abad23").withValues(alpha: 0.4)),
                      ),
                      Positioned(
                        bottom: -150,
                        right: -100,
                        child: _buildBlob(
                            screenWidth * 0.45, HexColor("#116754").withValues(alpha: 0.4)),
                      ),
                    ],
                  ),
                ),

              // 3. Content
              Center(
                child: Focus(
                  focusNode: _focusNode,
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    final double scrollDelta = 100.0;
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _scrollController.animateTo(
                        (_scrollController.offset + scrollDelta).clamp(
                            0, _scrollController.position.maxScrollExtent),
                        duration: const Duration(milliseconds: 100),
                        curve: Curves.linear,
                      );
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _scrollController.animateTo(
                        (_scrollController.offset - scrollDelta).clamp(
                            0, _scrollController.position.maxScrollExtent),
                        duration: const Duration(milliseconds: 100),
                        curve: Curves.linear,
                      );
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.pageDown) {
                      _scrollController.animateTo(
                        (_scrollController.offset + 400).clamp(
                            0, _scrollController.position.maxScrollExtent),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      );
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.pageUp) {
                      _scrollController.animateTo(
                        (_scrollController.offset - 400).clamp(
                            0, _scrollController.position.maxScrollExtent),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      );
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: isMobile
                        ? EdgeInsets.zero
                        : const EdgeInsets.symmetric(vertical: 24), // Adjusted padding
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: containerPadding,
                        vertical: 0,
                      ),
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: maxWidth,
                          minHeight: 0,
                        ),
                        decoration: isMobile
                            ? null
                            : BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(borderRadius),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 60,
                                    offset: const Offset(0, 15),
                                  ),
                                ],
                              ),
                        clipBehavior: isMobile ? Clip.none : Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isMobile) // Changed condition
                              Container(
                                width: double.infinity,
                                padding:
                                    EdgeInsets.symmetric(vertical: headerPadding),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      HexColor("#116754"),
                                      HexColor("#1a8a6f"),
                                    ],
                                  ),
                                ),
                                child: Text(
                                  'Sign Up',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.merriweather( // Changed font
                                    color: Colors.white,
                                    fontSize: headerFontSize,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: EdgeInsets.only(
                                top: headerPadding * 1.2,
                                bottom: fieldSpacing,
                              ),
                              child: Image.asset(
                                'lib/pages/assets/LIME ASSETS/lime.png',
                                height: logoSize * 1.2,
                                width: logoSize * 1.2,
                                fit: BoxFit.contain,
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
                              style: GoogleFonts.dmSerifText(
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
                                  // Name Field
                                  TextField(
                                    controller: _nameController,
                                    enabled: !_isProcessing,
                                    style: TextStyle(fontSize: fieldTextSize),
                                    decoration: InputDecoration(
                                      labelText: 'Full Name',
                                      labelStyle: TextStyle(fontSize: fieldTextSize),
                                      prefixIcon: Icon(Icons.person, size: iconSize, color: HexColor("#116754")),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: textFieldPadding,
                                        vertical: textFieldPadding + 4,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(borderRadius),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(borderRadius),
                                        borderSide: BorderSide(color: Colors.grey[400]!, width: 1.5),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(borderRadius),
                                        borderSide: BorderSide(color: HexColor("#116754"), width: 2.5),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: fieldSpacing),
                                  
                                  // Email Field
                                  TextField(
                                    controller: _emailController,
                                    enabled: !_isProcessing,
                                    keyboardType: TextInputType.emailAddress,
                                    style: TextStyle(fontSize: fieldTextSize),
                                    decoration: InputDecoration(
                                      labelText: 'Email',
                                      labelStyle: TextStyle(fontSize: fieldTextSize),
                                      prefixIcon: Icon(Icons.email, size: iconSize, color: HexColor("#116754")),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: textFieldPadding,
                                        vertical: textFieldPadding + 4,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(borderRadius),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(borderRadius),
                                        borderSide: BorderSide(color: Colors.grey[400]!, width: 1.5),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(borderRadius),
                                        borderSide: BorderSide(color: HexColor("#116754"), width: 2.5),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: fieldSpacing),
                                  // Password Field
                                  TextField(
                                    controller: _passwordController,
                                    enabled: !_isProcessing,
                                    obscureText: !_passwordVisible,
                                    style: TextStyle(fontSize: fieldTextSize),
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      labelStyle: TextStyle(fontSize: fieldTextSize),
                                      suffixIcon: GestureDetector(
                                        onTap: () => setState(() => _passwordVisible = !_passwordVisible),
                                        child: Icon(
                                          _passwordVisible ? Icons.lock_open : Icons.lock,
                                          size: iconSize,
                                          color: HexColor("#116754"),
                                        ),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: textFieldPadding,
                                        vertical: textFieldPadding + 4,
                                      ),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(borderRadius)),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(borderRadius),
                                        borderSide: BorderSide(color: Colors.grey[400]!, width: 1.5),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(borderRadius),
                                        borderSide: BorderSide(color: HexColor("#116754"), width: 2.5),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: fieldSpacing),

                                  // Confirm Password Field
                                  TextField(
                                    controller: _confirmPasswordController,
                                    enabled: !_isProcessing,
                                    obscureText: !_confirmPasswordVisible,
                                    style: TextStyle(fontSize: fieldTextSize),
                                    decoration: InputDecoration(
                                      labelText: 'Confirm Password',
                                      labelStyle: TextStyle(fontSize: fieldTextSize),
                                      suffixIcon: GestureDetector(
                                        onTap: () => setState(() => _confirmPasswordVisible = !_confirmPasswordVisible),
                                        child: Icon(
                                          _confirmPasswordVisible ? Icons.lock_open : Icons.lock,
                                          size: iconSize,
                                          color: HexColor("#116754"),
                                        ),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: textFieldPadding,
                                        vertical: textFieldPadding + 4,
                                      ),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(borderRadius)),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(borderRadius),
                                        borderSide: BorderSide(color: Colors.grey[400]!, width: 1.5),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(borderRadius),
                                        borderSide: BorderSide(color: HexColor("#116754"), width: 2.5),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: fieldSpacing * 1.5),

                                  // Sign Up Button
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
                                              child: const CircularProgressIndicator(
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

                                  // Login Link
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
                                            color: _isProcessing ? Colors.grey : HexColor("#116754"),
                                            fontWeight: FontWeight.bold,
                                            fontSize: linkFontSize,
                                            decoration: TextDecoration.underline,
                                          ),
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = _isProcessing ? null : () => Navigator.pop(context),
                                        ),
                                      ],
                                    ),
                                  ),
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
            ],
          ),
        );
      },
    );
  }
}