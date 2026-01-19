import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateDialog extends StatelessWidget {
  final String latestVersion;
  final String currentVersion;
  final int currentBuildNumber;
  final String releaseNotes;
  final String downloadUrl;
  final bool isEmergency;

  const UpdateDialog({
    super.key,
    required this.latestVersion,
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.releaseNotes,
    required this.downloadUrl,
    this.isEmergency = true,
  });

  Future<void> _launchUrl(BuildContext context) async {
    debugPrint('Attempting to launch URL: $downloadUrl');
    if (downloadUrl.isEmpty) {
      debugPrint('Error: downloadUrl is empty');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Download URL is missing in Firestore.')),
        );
      }
      return;
    }
    
    final Uri url = Uri.parse(downloadUrl.trim());
    try {
      final bool launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        debugPrint('Could not launch $url');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open browser for: $downloadUrl')),
          );
        }
      }
    } catch (e) {
      debugPrint('Exception launching URL: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isEmergency,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 10,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // LIME Logo or Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: HexColor("#116754").withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.system_update_rounded,
                  size: 40,
                  color: HexColor("#116754"),
                ),
              ),
              const SizedBox(height: 24),
              
              // Title
              Text(
                'New Update Available!',
                style: GoogleFonts.merriweather(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: HexColor("#355E3B"),
                ),
              ),
              const SizedBox(height: 8),
              
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: HexColor("#1e824c"),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Version $latestVersion',
                    style: GoogleFonts.dmSerifText(
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current: $currentVersion ($currentBuildNumber)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              const SizedBox(height: 20),
              
              // Release Notes
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "What's New:",
                  style: GoogleFonts.dmSerifText(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: HexColor("#355E3B"),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(
                    releaseNotes,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              
              // Action Buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _launchUrl(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HexColor("#1e824c"),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                  child: Text(
                    'Update Now',
                    style: GoogleFonts.dmSerifText(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              
              if (!isEmergency) 
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Later',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
            ],
          ),
        ),
      ),
      )
    );
  }
}
