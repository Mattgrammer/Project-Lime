import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:lime/pages/sign_in_page.dart';
import 'pages/sign_up_page.dart';
import 'pages/profile_router.dart';
import 'pages/maintenance_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:window_manager/window_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lime/utils/update_checker.dart';

// Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.ensureInitialized();

      const windowOptions = WindowOptions(
        minimumSize: Size(1000, 700),
        size: Size(1280, 720),
        center: true,
      );

      // Ensure window is ready before showing/maximizing to prevent crashes
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setResizable(true);
        // Add a small delay for native stability
        await Future.delayed(const Duration(milliseconds: 100));
        await windowManager.maximize();
        await windowManager.show();
        await windowManager.focus();
      });
    }

    runApp(const MyApp());
  } catch (e, stackTrace) {
    debugPrint('Fatal error during initialization: $e');
    debugPrint(stackTrace.toString());
    // Still run the app so it doesn't just vanish, 
    // but the app might need a fallback error screen if it gets here.
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Failed to initialize: $e')),
      ),
    ));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const AuthWrapper(),
      routes: {
        '/signin': (context) => const SignInPage(),
        '/signup': (context) => const SignUpPage(),
        '/home': (context) => const ProfileRouter(),
      },
      builder: (context, child) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('app_config')
              .doc('maintenance')
              .snapshots(),
          builder: (context, maintenanceSnapshot) {
            bool isMaintenance = false;
            if (maintenanceSnapshot.hasData && maintenanceSnapshot.data!.exists) {
              final data = maintenanceSnapshot.data!.data() as Map<String, dynamic>?;
              isMaintenance = data?['is_maintenance'] == true;
            }

            return Stack(
              children: [
                if (child != null) child,
                if (isMaintenance)
                  const Positioned.fill(
                    child: MaintenancePage(),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isOnboarded = false;
  bool _isCheckingOnboarded = true;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
    // Check for updates after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateChecker.checkForUpdates(context);
    });
  }

  Future<void> _checkOnboardingStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isOnboarded = prefs.getBool('is_onboarded') ?? false;
        _isCheckingOnboarded = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // If still loading either auth or onboarding status, show loading screen
        if (snapshot.connectionState == ConnectionState.waiting || _isCheckingOnboarded) {
          return Scaffold(
            backgroundColor: HexColor("#116754"),
            body: const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
          );
        }

        // If user is logged in, go to home
        if (snapshot.hasData && snapshot.data != null) {
          return const ProfileRouter();
        }

        // If user is not logged in, but has completed onboarding, go directly to SignIn
        if (_isOnboarded) {
          return const SignInPage();
        }

        // If user is not logged in and brand new, go to startup
        return const StartupPage();
      },
    );
  }
}

class StartupPage extends StatelessWidget {
  const StartupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HexColor("#116754"),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isMobile = width < 600;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              child: Container(
                width: isMobile ? width * 0.9 : 520,
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 28 : 36,
                  vertical: isMobile ? 35 : 45,
                ),
                decoration: _cardDecoration(),
                child: _cardContent(context, isMobile),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cardContent(BuildContext context, bool isMobile) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: _cardChildren(context, isMobile),
    );
  }

  List<Widget> _cardChildren(BuildContext context, bool isMobile) {
    return [
      SizedBox(
        height: isMobile ? 180 : 260,
        child: Image.asset(
          'lib/pages/assets/LIME ASSETS/lime.png',
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(height: 30),
      Text(
        'Welcome To LIME',
        textAlign: TextAlign.center,
        style: GoogleFonts.merriweather(
          fontSize: isMobile ? 32 : 42,
          fontWeight: FontWeight.bold,
          color: HexColor("#355E3B"),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Lets get you signed in and started',
        textAlign: TextAlign.center,
        style: GoogleFonts.dmSerifText(
          fontSize: isMobile ? 18 : 26,
          fontWeight: FontWeight.bold,
          color: HexColor("#355E3B"),
        ),
      ),
      const SizedBox(height: 40),
      ElevatedButton(
        onPressed: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_onboarded', true);
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SignInPage(),
              ),
            );
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: HexColor("#1e824c"),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 50 : 80,
            vertical: isMobile ? 16 : 22,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          'Lets Get Started',
          style: GoogleFonts.dmSerifText(
            fontSize: isMobile ? 18 : 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    ];
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}