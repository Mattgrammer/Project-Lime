import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ota_update/ota_update.dart';
import 'dart:io';

class UpdateDialog extends StatefulWidget {
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

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  String _progress = "";
  bool _isDownloading = false;
  String _error = "";

  Future<void> _startUpdate() async {
    debugPrint('Attempting to start update: ${widget.downloadUrl}');
    if (widget.downloadUrl.isEmpty) {
      setState(() => _error = "Download URL is missing.");
      return;
    }

    if (!kIsWeb && Platform.isAndroid) {
      _executeAndroidUpdate();
    } else {
      _launchUrl();
    }
  }

  void _executeAndroidUpdate() {
    try {
      setState(() {
        _isDownloading = true;
        _error = "";
      });

      OtaUpdate().execute(
        widget.downloadUrl.trim(),
        destinationFilename: 'lime_update.apk',
      ).listen(
        (OtaEvent event) {
          setState(() {
            _progress = event.value ?? "0";
            if (event.status == OtaStatus.DOWNLOADING) {
              debugPrint('Downloading: ${event.value}%');
            } else if (event.status == OtaStatus.INSTALLING) {
              debugPrint('Installing...');
              _isDownloading = false;
            } else if (event.status == OtaStatus.ALREADY_RUNNING_ERROR) {
              _error = "An update is already in progress.";
              _isDownloading = false;
            } else if (event.status == OtaStatus.PERMISSION_NOT_GRANTED_ERROR) {
              _error = "Storage permission denied.";
              _isDownloading = false;
            } else if (event.status == OtaStatus.INTERNAL_ERROR || 
                       event.status == OtaStatus.DOWNLOAD_ERROR ||
                       event.status == OtaStatus.CHECKSUM_ERROR) {
              _error = "Download failed: ${event.status}";
              _isDownloading = false;
            }
          });
        },
      );
    } catch (e) {
      setState(() {
        _error = "Exception: $e";
        _isDownloading = false;
      });
    }
  }

  Future<void> _launchUrl() async {
    final Uri url = Uri.parse(widget.downloadUrl.trim());
    try {
      final bool launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        setState(() => _error = "Could not open browser.");
      }
    } catch (e) {
      setState(() => _error = "Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isEmergency && !_isDownloading,
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
                // Header Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: (widget.isEmergency ? Colors.red : HexColor("#116754")).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.isEmergency ? Icons.warning_amber_rounded : Icons.system_update_rounded,
                    size: 40,
                    color: widget.isEmergency ? Colors.red[700] : HexColor("#116754"),
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  _isDownloading ? 'Downloading Update...' : 'New Update Available!',
                  textAlign: TextAlign.center,
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
                    'Version ${widget.latestVersion}',
                    style: GoogleFonts.dmSerifText(
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current: ${widget.currentVersion} (${widget.currentBuildNumber})',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 20),

                if (_isDownloading) ...[
                  // Progress UI
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: double.tryParse(_progress) != null ? double.parse(_progress) / 100 : 0,
                    backgroundColor: Colors.grey[200],
                    color: HexColor("#1e824c"),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$_progress%',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: HexColor("#355E3B"),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please do not close the app...',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ] else ...[
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
                        widget.releaseNotes,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],

                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error,
                    style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ],

                if (widget.isEmergency && !_isDownloading) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red[200]!, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.red[700], size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'A mandatory update is required to continue. You may not skip this process.',
                            style: GoogleFonts.inter(
                              color: Colors.red[900],
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 30),

                // Action Buttons
                if (!_isDownloading)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _startUpdate,
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

                if (!widget.isEmergency && !_isDownloading)
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      'Later',
                      style: TextStyle(color: Colors.grey[600]),
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
