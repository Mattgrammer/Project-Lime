import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SuspendedPage extends StatelessWidget {
  const SuspendedPage({super.key});

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
              if (width < 600) return const SizedBox.shrink();
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
              final isMobile = screenWidth < 600;
              final containerWidth = isMobile ? screenWidth * 0.9 : 520.0;

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    width: containerWidth,
                    padding: EdgeInsets.symmetric(
                      vertical: isMobile ? 32 : 48,
                      horizontal: isMobile ? 24 : 40,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 60,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Header: Logo centered
                        Image.asset(
                          'lib/pages/assets/LIME ASSETS/lime.png',
                          height: isMobile ? 100 : 130,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 40),
                        
                        // Title
                        Text(
                          'Account Suspended',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.merriweather(
                            fontSize: isMobile ? 32 : 42,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // Message
                        Text(
                          'Your account has been suspended by your Lemon Administrator.\n\nPlease contact your administrator if you believe this is a mistake.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.dmSerifText(
                            fontSize: isMobile ? 20 : 24,
                            color: Colors.black,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Back to login button
                        ElevatedButton(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HexColor("#116754"),
                            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 4,
                          ),
                          child: Text(
                            'Back to Login',
                            style: GoogleFonts.dmSerifText(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
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
}
