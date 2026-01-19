import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:lime/pages/sign_in_page.dart';
import 'pages/sign_up_page.dart';
import 'pages/profile_router.dart';
import 'pages/maintenance_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:window_manager/window_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lime/utils/update_checker.dart';
import 'package:lime/services/notification_service.dart';
import 'package:lime/services/connectivity_service.dart';
import 'package:lime/services/offline_sync_service.dart';
import 'package:lime/widgets/connectivity_indicator.dart';

// Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() async {
  // Set up global error handlers to prevent red screens
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exception}');
    debugPrint('Stack trace: ${details.stack}');
    // Don't show red screen - just log it
  };

  // Handle async errors
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Platform Error: $error');
    debugPrint('Stack trace: $stack');
    return true; // Mark as handled
  };

  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Enable Immersive Sticky Mode (Auto-hides system UI)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Initialize Firebase with timeout protection
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('Firebase initialization timed out');
          throw Exception('Firebase initialization timed out');
        },
      );

      // Explicitly configure Firestore settings for all platforms
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      debugPrint('Firestore initialized - persistence enabled (Unlimited Cache)');
    } catch (e) {
      debugPrint('Firebase initialization error: $e');
      // Continue anyway - app might work offline
    }

    // Initialize connectivity and sync services
    // Wrap in try-catch to prevent app crash if services fail
    try {
      await ConnectivityService().init().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('ConnectivityService initialization timed out');
        },
      );
    } catch (e, stackTrace) {
      debugPrint('Error initializing ConnectivityService: $e');
      debugPrint('Stack trace: $stackTrace');
      // Non-fatal, continue - app will work without connectivity monitoring
    }

    try {
      await OfflineSyncService().init().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('OfflineSyncService initialization timed out');
        },
      );
      debugPrint('Connectivity and sync services initialized');
    } catch (e, stackTrace) {
      debugPrint('Error initializing OfflineSyncService: $e');
      debugPrint('Stack trace: $stackTrace');
      // Non-fatal, continue - app will work without sync service
    }

    // Initialize Notifications - Only on mobile platforms
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      try {
        await NotificationService.init();
      } catch (e) {
        debugPrint('Notification service error: $e');
        // Non-fatal, continue
      }
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
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
      } catch (e) {
        debugPrint('Window manager error: $e');
        // Continue anyway - window might still work
      }
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
      // Global error handler to prevent red screens
      builder: (context, child) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('app_config')
              .doc('maintenance')
              .snapshots(),
          builder: (context, maintenanceSnapshot) {
            // Default to NOT in maintenance if there's any error or missing data
            bool isMaintenance = false;
            
            // Only check maintenance if we have valid data without errors
            if (maintenanceSnapshot.hasData && 
                !maintenanceSnapshot.hasError && 
                maintenanceSnapshot.data != null &&
                maintenanceSnapshot.data!.exists) {
              try {
                final data = maintenanceSnapshot.data!.data() as Map<String, dynamic>?;
                isMaintenance = data?['is_maintenance'] == true;
              } catch (e) {
                debugPrint('Error parsing maintenance data: $e');
                isMaintenance = false;
              }
            }

            // Always show the child (main app) - only overlay maintenance if needed
            return Stack(
              children: [
                if (child != null) 
                  Builder(
                    builder: (context) {
                      final isMobile = MediaQuery.of(context).size.width < 600;
                      // On mobile, position banner lower; on desktop, keep at top
                    if (isMobile) {
                      return Column(
                        children: [
                          // Position banner at the very top on mobile
                          Builder(
                            builder: (context) {
                              try {
                                return const OfflineBanner();
                              } catch (e) {
                                debugPrint('Error building OfflineBanner: $e');
                                return const SizedBox.shrink();
                              }
                            },
                          ),
                          Expanded(child: child),
                        ],
                      );
                    } else {
                        return Column(
                          children: [
                            // Wrap OfflineBanner in error boundary
                            Builder(
                              builder: (context) {
                                try {
                                  return const OfflineBanner();
                                } catch (e) {
                                  debugPrint('Error building OfflineBanner: $e');
                                  return const SizedBox.shrink();
                                }
                              },
                            ),
                            Expanded(child: child),
                          ],
                        );
                      }
                    },
                  ),
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
      body: Stack(
        children: [
          // 1. Base Gradient
          Container(
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
          ),
          
          // 2. Decorative Blobs
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isMobile = width < 600;
              
              if (isMobile) return const SizedBox.shrink();
              
              return Stack(
                children: [
                  Positioned(
                    top: -100,
                    left: -50,
                    child: _buildBlob(width * 0.4, HexColor("#abad23").withValues(alpha: 0.4)),
                  ),
                  Positioned(
                    bottom: -150,
                    right: -100,
                    child: _buildBlob(width * 0.45, HexColor("#116754").withValues(alpha: 0.4)),
                  ),
                ],
              );
            },
          ),

          // 3. Content
          LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = constraints.maxWidth;
              final screenHeight = constraints.maxHeight;
              final isMobile = screenWidth < 600;
              final isTablet = screenWidth >= 600 && screenWidth < 1024;

              // Dynamic width calculation
              double containerWidth;
              if (isMobile) {
                containerWidth = screenWidth * 0.92;
              } else if (isTablet) {
                containerWidth = (screenWidth * 0.75).clamp(480.0, 600.0);
              } else {
                containerWidth = (screenWidth * 0.45).clamp(520.0, 700.0);
              }

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: Container(
                    width: containerWidth,
                    clipBehavior: Clip.antiAlias, // Important for rounded corners
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 24 : (containerWidth * 0.1).clamp(32.0, 64.0),
                      vertical: isMobile ? 32 : 48,
                    ),
                    decoration: _cardDecoration(),
                    child: _cardContent(context, isMobile, screenHeight),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cardContent(BuildContext context, bool isMobile, double screenHeight) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: _cardChildren(context, isMobile, screenHeight),
    );
  }

  List<Widget> _cardChildren(BuildContext context, bool isMobile, double screenHeight) {
    // Dynamic image height
    double imageHeight = isMobile ? 180 : (screenHeight * 0.35).clamp(200.0, 320.0);
    double titleSize = isMobile ? 32 : (screenHeight * 0.05).clamp(36.0, 48.0);
    double subtitleSize = isMobile ? 18 : (screenHeight * 0.03).clamp(20.0, 28.0);
    return [
      SizedBox(
        height: imageHeight,
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
          fontSize: titleSize,
          fontWeight: FontWeight.bold,
          color: HexColor("#355E3B"),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Lets get you signed in and started',
        textAlign: TextAlign.center,
        style: GoogleFonts.dmSerifText(
          fontSize: subtitleSize,
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
          backgroundColor: HexColor("#116754"),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 50 : 80,
            vertical: isMobile ? 18 : 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.3),
        ),
        child: Text(
          'Let\'s Get Started',
          style: GoogleFonts.dmSerifText(
            fontSize: isMobile ? 18 : 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    ];
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 60,
          offset: const Offset(0, 15),
        ),
      ],
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