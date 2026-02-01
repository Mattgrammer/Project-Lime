import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lime/pages/update_dialog.dart';
import 'dart:io';

class UpdateChecker {
  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      // Get local app info
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      int currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;
      String currentVersion = packageInfo.version;

      // Get remote app config from Firestore
      DocumentSnapshot config = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version')
          .get();

      if (!config.exists) {
        debugPrint('UpdateChecker: Firestore config not found.');
        return;
      }

      final data = config.data() as Map<String, dynamic>;
      
      // Safely parse build number (handle int or String)
      var buildNumRaw = data['build_number'];
      int latestBuildNumber = 0;
      if (buildNumRaw is int) {
        latestBuildNumber = buildNumRaw;
      } else if (buildNumRaw is String) {
        latestBuildNumber = int.tryParse(buildNumRaw) ?? 0;
      }

      String latestVersion = data['latest_version'] ?? currentVersion;
      String releaseNotes = data['release_notes'] ?? 'New version available!';
      
      // Select the correct download URL based on the platform
      String downloadUrl = '';
      if (Platform.isAndroid) {
        downloadUrl = data['download_url_android'] ?? data['download_url'] ?? '';
      } else if (Platform.isWindows) {
        downloadUrl = data['download_url_windows'] ?? data['download_url'] ?? '';
      } else {
        downloadUrl = data['download_url'] ?? '';
      }

      // Safely parse is_emergency
      var emergencyRaw = data['is_emergency'];
      bool isEmergencyUpdate = false; 
      if (emergencyRaw is bool) {
        isEmergencyUpdate = emergencyRaw;
      } else if (emergencyRaw is String) {
         isEmergencyUpdate = emergencyRaw.toLowerCase() == 'true';
      }

      // IMPROVED VERSION DETECTION:
      bool isUpdateAvailable = false;
      if (latestBuildNumber > currentBuildNumber) {
        isUpdateAvailable = true;
      } else if (latestVersion != currentVersion) {
        isUpdateAvailable = _isNewerVersion(latestVersion, currentVersion);
      }

      debugPrint('UpdateChecker: Local v$currentVersion($currentBuildNumber), Remote v$latestVersion($latestBuildNumber), Update: $isUpdateAvailable');

      if (isUpdateAvailable) {
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: !isEmergencyUpdate,
            builder: (context) => UpdateDialog(
              latestVersion: latestVersion,
              currentVersion: currentVersion,
              currentBuildNumber: currentBuildNumber,
              releaseNotes: releaseNotes,
              downloadUrl: downloadUrl,
              isEmergency: isEmergencyUpdate,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('UpdateChecker Error: $e');
    }
  }

  static bool _isNewerVersion(String latest, String current) {
    try {
      List<int> latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      
      for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return latestParts.length > currentParts.length;
    } catch (e) {
      return latest != current;
    }
  }
}
