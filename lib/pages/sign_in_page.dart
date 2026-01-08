import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'sign_up_page.dart';

import 'profile_router.dart';

// Firebase imports
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    minimumSize: Size(720, 405),
    size: Size(1280, 720),
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lime Sign In',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const SignInPage(),
      routes: {
        '/signin': (context) => const SignInPage(),
        '/signup': (context) => const SignUpPage(),
        '/home': (context) => const ProfileRouter(),
      },
    );
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  bool _passwordVisible = false;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // Basic validation
    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Please fill in all fields');
      return;
    }

    if (!email.contains('@')) {
      _showSnackBar('Please enter a valid email');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Sign in with Firebase
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Navigate to home on success
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred';

      if (e.code == 'user-not-found') {
        message = 'No user found with this email';
      } else if (e.code == 'wrong-password') {
        message = 'Wrong password';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address';
      } else if (e.code == 'user-disabled') {
        message = 'This account has been disabled';
      } else if (e.code == 'too-many-requests') {
        message = 'Too many attempts. Please try again later';
      } else if (e.code == 'invalid-credential') {
        message = 'Invalid email or password';
      }

      _showSnackBar(message);
    } catch (e) {
      _showSnackBar('An unexpected error occurred');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    
    // Show email entry dialog if field is empty
    String targetEmail = email;
    if (targetEmail.isEmpty) {
      final TextEditingController resetMailController = TextEditingController();
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reset Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your registered email address to receive a password reset link.'),
              const SizedBox(height: 16),
              TextField(
                controller: resetMailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: HexColor("#116754")),
              child: const Text('Send Reset Link', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
      targetEmail = resetMailController.text.trim();
    }

    if (targetEmail.isEmpty || !targetEmail.contains('@')) {
      _showSnackBar('Please enter a valid email address');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _auth.sendPasswordResetEmail(email: targetEmail);
      _showSnackBar('Password reset link sent to $targetEmail');
    } on FirebaseAuthException catch (e) {
      String message = 'Error sending reset link';
      if (e.code == 'user-not-found') {
        message = 'No account found with this email';
      }
      _showSnackBar(message);
    } catch (e) {
      _showSnackBar('An unexpected error occurred');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: HexColor("#116754"),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        final isDesktop = screenWidth > 900;
        final isTablet = screenWidth > 600 && screenWidth <= 900;
        final isMobile = screenWidth <= 600;

        // Responsive values
        final maxWidth = isDesktop ? 440.0 : isTablet ? 420.0 : double.infinity;
        final horizontalPadding = isDesktop ? 24.0 : isTablet ? 20.0 : 16.0;
        final verticalPadding = isDesktop ? 32.0 : isTablet ? 28.0 : 24.0;
        final headerFontSize = isDesktop ? 36.0 : isTablet ? 34.0 : 28.0;
        final welcomeFontSize = isDesktop ? 40.0 : isTablet ? 36.0 : 28.0;
        final subtitleFontSize = isDesktop ? 16.0 : isTablet ? 15.0 : 14.0;
        final buttonHeight = isDesktop ? 56.0 : isTablet ? 54.0 : 50.0;
        final imageHeight = isDesktop ? 160.0 : isTablet ? 150.0 : 120.0;
        final borderRadius = isDesktop ? 24.0 : isTablet ? 20.0 : 16.0;
        final contentPaddingHorizontal = isDesktop ? 40.0 : isTablet ? 32.0 : 24.0;
        final contentPaddingVertical = isDesktop ? 32.0 : isTablet ? 28.0 : 24.0;
        final shadowBlur = isDesktop ? 40.0 : isTablet ? 30.0 : 20.0;
        final shadowOffset = isDesktop ? 20.0 : isTablet ? 15.0 : 10.0;
        final shadowAlpha = isDesktop ? 0.12 : isTablet ? 0.1 : 0.08;

        return Scaffold(
          body: Container(
            width: screenWidth,
            height: screenHeight,
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
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: isDesktop ? 20 : 16,
                    ),
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: maxWidth,
                        minHeight: isMobile ? screenHeight * 0.6 : screenHeight * 0.8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(borderRadius),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: shadowAlpha),
                            blurRadius: shadowBlur,
                            offset: Offset(0, shadowOffset),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(vertical: verticalPadding),
                            decoration: BoxDecoration(
                              color: HexColor("#116754"),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(borderRadius),
                                topRight: Radius.circular(borderRadius),
                              ),
                            ),
                            child: Text(
                              'Sign In',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: headerFontSize,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),

                          // Content
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              contentPaddingHorizontal,
                              contentPaddingVertical,
                              contentPaddingHorizontal,
                              contentPaddingVertical,
                            ),
                            child: Column(
                              children: [
                                // Image asset placeholder
                                Image.asset(
                                  'lib/pages/assets/LIME ASSETS/limelogo.png',
                                  height: imageHeight,
                                  width: isDesktop ? 200 : isTablet ? 180 : 140,
                                  fit: BoxFit.contain,
                                ),
                                SizedBox(height: isDesktop ? 24 : isTablet ? 20 : 16),

                                // Welcome text
                                Text(
                                  'Welcome Back!',
                                  style: TextStyle(
                                    color: HexColor("#116754"),
                                    fontSize: welcomeFontSize,
                                    fontWeight: FontWeight.bold,
                                    height: 1.2,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: isDesktop ? 12 : isTablet ? 10 : 8),
                                Text(
                                  'Sign in to your Lime Account',
                                  style: TextStyle(
                                    color: const Color(0xFF666666),
                                    fontSize: subtitleFontSize,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: isDesktop ? 48 : isTablet ? 40 : 32),

                                // Email field
                                TextField(
                                  controller: _emailController,
                                  enabled: !_isLoading,
                                  decoration: InputDecoration(
                                    prefixIcon: Icon(
                                      Icons.email,
                                      color: HexColor("#116754"),
                                      size: isDesktop ? 24 : isTablet ? 22 : 20,
                                    ),
                                    hintText: 'Email',
                                    hintStyle: TextStyle(
                                      color: const Color(0xFFAAAAAA),
                                      fontSize: isDesktop ? 16 : isTablet ? 15 : 14,
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Colors.grey[300]!,
                                        width: 1.5,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Colors.grey[300]!,
                                        width: 1.5,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: HexColor("#116754"),
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: isDesktop ? 16 : isTablet ? 14 : 12,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontSize: isDesktop ? 16 : isTablet ? 15 : 14,
                                  ),
                                ),
                                SizedBox(height: isDesktop ? 24 : isTablet ? 20 : 16),

                                // Password field
                                TextField(
                                  controller: _passwordController,
                                  obscureText: !_passwordVisible,
                                  enabled: !_isLoading,
                                  decoration: InputDecoration(
                                    prefixIcon: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _passwordVisible = !_passwordVisible;
                                        });
                                      },
                                      child: Icon(
                                        _passwordVisible
                                            ? Icons.lock_open
                                            : Icons.lock,
                                        color: HexColor("#116754"),
                                        size: isDesktop ? 24 : isTablet ? 22 : 20,
                                      ),
                                    ),
                                    hintText: 'Password',
                                    hintStyle: TextStyle(
                                      color: const Color(0xFFAAAAAA),
                                      fontSize: isDesktop ? 16 : isTablet ? 15 : 14,
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Colors.grey[300]!,
                                        width: 1.5,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Colors.grey[300]!,
                                        width: 1.5,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: HexColor("#116754"),
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: isDesktop ? 16 : isTablet ? 14 : 12,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontSize: isDesktop ? 16 : isTablet ? 15 : 14,
                                  ),
                                ),
                                SizedBox(height: isDesktop ? 12 : isTablet ? 10 : 8),
                                
                                // Forgot Password link
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _isLoading ? null : _handleForgotPassword,
                                    child: Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        color: HexColor("#116754"),
                                        fontSize: isDesktop ? 15 : isTablet ? 14 : 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                
                                SizedBox(height: isDesktop ? 24 : isTablet ? 20 : 16),

                                // Sign In button
                                SizedBox(
                                  width: double.infinity,
                                  height: buttonHeight,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _handleSignIn,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: HexColor("#116754"),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(32),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                        : Text(
                                      'Sign In',
                                      style: TextStyle(
                                        fontSize: isDesktop ? 18 : isTablet ? 17 : 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: isDesktop ? 32 : isTablet ? 28 : 24),

                                // Sign up link
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  children: [
                                    Text(
                                      "Don't have an account?  ",
                                      style: TextStyle(
                                        color: const Color(0xFF666666),
                                        fontSize: isDesktop ? 16 : isTablet ? 15 : 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: _isLoading
                                          ? null
                                          : () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => const SignUpPage(),
                                          ),
                                        );
                                      },
                                      child: Text(
                                        'Sign Up',
                                        style: TextStyle(
                                          color: HexColor("#116754"),
                                          fontSize: isDesktop ? 16 : isTablet ? 15 : 14,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                          decorationColor: HexColor("#116754"),
                                        ),
                                      ),
                                    ),
                                  ],
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
          ),
        );
      },
    );
  }
}