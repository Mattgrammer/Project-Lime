import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:google_fonts/google_fonts.dart';

class MaintenancePage extends StatelessWidget {
  const MaintenancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon or Illustration
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: HexColor("#116754").withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.construction_rounded,
                  size: 80,
                  color: HexColor("#116754"),
                ),
              ),
              const SizedBox(height: 40),
              
              // Title
              Text(
                'System Maintenance',
                textAlign: TextAlign.center,
                style: GoogleFonts.merriweather(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: HexColor("#355E3B"),
                ),
              ),
              const SizedBox(height: 20),
              
              // Message
              Text(
                'We are currently performing scheduled maintenance to improve our services.\nLIME will be back online shortly.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSerifText(
                  fontSize: 18,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              
              // Logo
              Opacity(
                opacity: 0.6,
                child: SizedBox(
                  height: 80,
                  child: Image.asset(
                    'lib/pages/assets/LIME ASSETS/lime.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
