import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:window_manager/window_manager.dart';
import 'sign_up_page.dart';

import 'profile_router.dart';

// Firebase imports
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lime/services/connectivity_service.dart';

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

    // Check internet connection before attempting sign in
    final connectivityService = ConnectivityService();
    if (!connectivityService.isOnline) {
      _showSnackBar('Sorry, you don\'t have internet connection. Please check your network and try again.');
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

      // Check for network-related errors
      if (e.code == 'network-request-failed' || e.code == 'too-many-requests') {
        message = 'Sorry, you don\'t have internet connection. Please check your network and try again.';
      } else if (e.code == 'user-not-found') {
        message = 'No user found with this email';
      } else if (e.code == 'wrong-password') {
        message = 'Wrong password';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address';
      } else if (e.code == 'user-disabled') {
        message = 'This account has been disabled';
      } else if (e.code == 'invalid-credential') {
        message = 'Invalid email or password';
      }

      _showSnackBar(message);
    } catch (e) {
      // Check if it's a network error
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('network') || errorString.contains('socket') || errorString.contains('connection')) {
        _showSnackBar('Sorry, you don\'t have internet connection. Please check your network and try again.');
      } else {
        _showSnackBar('An unexpected error occurred');
      }
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
        final headerFontSize = (isDesktop ? 34.0 : isTablet ? 30.0 : 28.0) * verticalScale;
        final welcomeFontSize = (isDesktop ? 30.0 : isTablet ? 26.0 : 34.0) * verticalScale;
        final subtitleFontSize = (isDesktop ? 17.0 : isTablet ? 16.0 : 22.0) * verticalScale;
        final buttonHeight = (isDesktop ? 52.0 : isTablet ? 48.0 : 44.0) * verticalScale;
        final borderRadius = isMobile ? 20.0 : 28.0; // More premium rounding
        
        // Header padding scales aggressively with height
        final verticalPadding = (isDesktop ? 22.0 : isTablet ? 18.0 : 16.0) * verticalScale;
        
        // Shadow scaling - more depth

        // Content scaling
        final imageHeight = (isDesktop ? 160.0 : isTablet ? 140.0 : 250.0) * verticalScale;
        final iconSize = (isDesktop ? 20.0 : isTablet ? 19.0 : 18.0) * verticalScale;
        final contentPaddingHorizontal = isMobile ? 24.0 : (maxWidth * 0.1).clamp(32.0, 56.0);
        final contentPaddingVertical = (isMobile ? 24.0 : 32.0) * verticalScale;
        final interSpacing = (isDesktop ? 24.0 : isTablet ? 20.0 : 16.0) * verticalScale;



        return Scaffold(
          backgroundColor: isMobile ? Colors.white : null,
          appBar: isMobile
              ? AppBar(
                  title: Text('Sign In', style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)),
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

              // 2. Decorative Blobs
              if (!isMobile)
                Positioned.fill(
                  child: Stack(
                    children: [
                      Positioned(
                        top: -100,
                        left: -50,
                        child: _buildBlob(screenWidth * 0.4, HexColor("#abad23").withValues(alpha: 0.4)),
                      ),
                      Positioned(
                        bottom: -150,
                        right: -100,
                        child: _buildBlob(screenWidth * 0.45, HexColor("#116754").withValues(alpha: 0.4)),
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
                     // ... handle scroll
                     return KeyEventResult.ignored;
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: isMobile ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 24),
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
                        clipBehavior: isMobile ? Clip.none : Clip.antiAlias, // Fix for rounded corners
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header (Desktop/Tablet only)
                            if (!isMobile)
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(vertical: verticalPadding),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      HexColor("#116754"),
                                      HexColor("#1a8a6f"),
                                    ],
                                  ),
                                ),
                                child: Text(
                                  'Sign In',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.merriweather(
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
                                contentPaddingVertical * 1.2, // Slightly more top room
                                contentPaddingHorizontal,
                                contentPaddingVertical,
                              ),
                              child: Column(
                                children: [
                                  // Full Logo branding
                                  Image.asset(
                                    'lib/pages/assets/LIME ASSETS/lime.png',
                                    height: imageHeight,
                                    width: isDesktop ? 240 : isTablet ? 210 : 320,
                                    fit: BoxFit.contain,
                                  ),
                                  SizedBox(height: interSpacing),

                                  // Welcome text
                                  Text(
                                    'Welcome Back!',
                                    style: GoogleFonts.dmSerifText(
                                      color: HexColor("#116754"),
                                      fontSize: welcomeFontSize,
                                      fontWeight: FontWeight.bold,
                                      height: 1.2,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: interSpacing * 0.4),
                                  Text(
                                    'Sign in to your Lime Account',
                                    style: TextStyle(
                                      color: const Color(0xFF666666),
                                      fontSize: subtitleFontSize,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: interSpacing * 1.5),

                                  // Email field
                                  TextField(
                                    controller: _emailController,
                                    enabled: !_isLoading,
                                    decoration: InputDecoration(
                                      prefixIcon: Icon(
                                        Icons.email,
                                        color: HexColor("#116754"),
                                        size: iconSize,
                                      ),
                                    hintText: 'Email',
                                    hintStyle: TextStyle(
                                      color: const Color(0xFFAAAAAA),
                                      fontSize: isDesktop ? 16 : isTablet ? 15 : 14,
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(borderRadius),
                                      borderSide: BorderSide(
                                        color: Colors.grey[300]!,
                                        width: 1.5,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(borderRadius),
                                      borderSide: BorderSide(
                                        color: Colors.grey[300]!,
                                        width: 1.5,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(borderRadius),
                                      borderSide: BorderSide(
                                        color: HexColor("#116754"),
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: (isDesktop ? 16 : isTablet ? 14 : 12) * verticalScale,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontSize: (isDesktop ? 16 : isTablet ? 15 : 14) * (verticalScale > 1.0 ? 1.0 : verticalScale),
                                  ),
                                ),
                                SizedBox(height: interSpacing * 0.7),

                                // Password field
                                TextField(
                                  controller: _passwordController,
                                  obscureText: !_passwordVisible,
                                  enabled: !_isLoading,
                                  decoration: InputDecoration(
                                    suffixIcon: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _passwordVisible = !_passwordVisible;
                                        });
                                      },
                                      child: Icon(
                                        _passwordVisible ? Icons.lock_open : Icons.lock,
                                        color: HexColor("#116754"),
                                        size: iconSize,
                                      ),
                                    ),
                                    hintText: 'Password',
                                    hintStyle: TextStyle(
                                      color: const Color(0xFFAAAAAA),
                                      fontSize: (isDesktop ? 16 : isTablet ? 15 : 14) * (verticalScale > 1.0 ? 1.0 : verticalScale),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(borderRadius),
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
                                      vertical: (isDesktop ? 16 : isTablet ? 14 : 12) * verticalScale,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontSize: (isDesktop ? 16 : isTablet ? 15 : 14) * (verticalScale > 1.0 ? 1.0 : verticalScale),
                                  ),
                                ),
                                SizedBox(height: interSpacing * 0.3),
                                
                                // Forgot Password link
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _isLoading ? null : _handleForgotPassword,
                                    child: Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        color: HexColor("#116754"),
                                        fontSize: (isDesktop ? 15 : isTablet ? 14 : 13) * (verticalScale > 1.0 ? 1.0 : verticalScale),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                
                                SizedBox(height: interSpacing * 0.7),

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
                                        fontSize: (isDesktop ? 18 : isTablet ? 17 : 16) * (verticalScale > 1.0 ? 1.0 : verticalScale),
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: interSpacing * 1.0),

                                // Sign up link
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  children: [
                                    Text(
                                      "Don't have an account?  ",
                                      style: TextStyle(
                                        color: const Color(0xFF666666),
                                        fontSize: (isDesktop ? 16 : isTablet ? 15 : 14) * (verticalScale > 1.0 ? 1.0 : verticalScale),
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
                                          fontSize: (isDesktop ? 16 : isTablet ? 15 : 14) * (verticalScale > 1.0 ? 1.0 : verticalScale),
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
            ],
          ),
        );
      },
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
}
