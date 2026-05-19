import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hexcolor/hexcolor.dart';

class WarningDialog extends StatelessWidget {
  final String message;
  final VoidCallback onAcknowledge;

  const WarningDialog({
    super.key,
    required this.message,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 10,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Warning Icon with background
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 64,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 24),
            
            // Title
            Text(
              'Account Warning',
              style: GoogleFonts.merriweather(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: HexColor("#355E3B"),
              ),
            ),
            const SizedBox(height: 16),
            
            // Message
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSerifText(
                fontSize: 18,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            
            // Acknowledge Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onAcknowledge,
                style: ElevatedButton.styleFrom(
                  backgroundColor: HexColor("#116754"),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                child: Text(
                  'I Understand',
                  style: GoogleFonts.dmSerifText(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showAccountWarning(BuildContext context, String message, VoidCallback onAcknowledge) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => WarningDialog(
      message: message,
      onAcknowledge: () {
        Navigator.of(context).pop();
        onAcknowledge();
      },
    ),
  );
}
