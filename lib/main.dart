import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:rsp/pages/sign_in_page.dart';
import 'package:window_manager/window_manager.dart';
import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      minimumSize: Size(900, 600),
      size: Size(1100, 750),
      center: true,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setResizable(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const StartupPage(),
    );
  }
}

class StartupPage extends StatelessWidget {
  const StartupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    return Scaffold(
      backgroundColor: HexColor("#116754"),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: width * 0.6,
            padding: const EdgeInsets.fromLTRB(48, 40, 60, 48), // More top padding
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // ACTUALLY BIG LOGO NOW
              Image.asset(
              'lib/pages/assets/LIME ASSETS/lime.png',
              width: width * 0.25, // 25% of screen width
              height: 250, // Fixed large height
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),

            Text(
              'Welcome To LIME',
              textAlign: TextAlign.center,
              style: GoogleFonts.merriweather(
                fontSize: width * 0.032,
                fontWeight: FontWeight.bold,
                color: HexColor("#355E3B"),
              ),
            ),
            const SizedBox(height: 12),

            Text(
              'Lets get you signed in and started',
            textAlign: TextAlign.center,
              style: GoogleFonts.dmSerifText(
                fontSize: width * 0.024,
                fontWeight: FontWeight.bold,
                color: HexColor("#355E3B"),
              ),
            ),
            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SignInPage(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: HexColor("#1e824c"),
                padding: EdgeInsets.symmetric(
                  horizontal: width * 0.05,
                  vertical: height * 0.02,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Lets Get Started',
              style: GoogleFonts.dmSerifText(
              fontSize: width * 0.022,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          ],
        ),
      ),
    ),
    ),
    );
  }
}