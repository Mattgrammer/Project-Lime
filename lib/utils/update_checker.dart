import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lime/pages/update_dialog.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateChecker {
  static bool _isDialogShowing = false;

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
      if (!kIsWeb && Platform.isAndroid) {
        downloadUrl = data['download_url_android'] ?? data['download_url'] ?? '';
      } else if (!kIsWeb && Platform.isWindows) {
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

      // SMARTER VERSION DETECTION:
      int versionComparison = _compareVersions(latestVersion, currentVersion);
      bool isUpdateAvailable = false;
      
      if (versionComparison > 0) {
        // Remote version name is strictly newer (e.g., 1.0.1 > 1.0.0)
        isUpdateAvailable = true;
      } else if (versionComparison == 0) {
        // Version names are equal, check build number (e.g., 1.0.0+2 > 1.0.0+1)
        if (latestBuildNumber > currentBuildNumber) {
          isUpdateAvailable = true;
        }
      }
      // If versionComparison < 0, local version is newer than remote (e.g., dev build 1.1.0 > remote 1.0.0), no update.

      debugPrint('UpdateChecker: Local v$currentVersion($currentBuildNumber), Remote v$latestVersion($latestBuildNumber), Update: $isUpdateAvailable');

      // Check for dismissed version
      final prefs = await SharedPreferences.getInstance();
      final dismissedVersion = prefs.getString('dismissed_update_version');
      
      if (isUpdateAvailable && !_isDialogShowing) {
        if (dismissedVersion == latestVersion && !isEmergencyUpdate) {
           debugPrint('UpdateChecker: Update v$latestVersion dismissed by user.');
           return;
        }

        if (context.mounted) {
          _isDialogShowing = true;
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
          ).then((result) async {
             _isDialogShowing = false;
             if (result == true && !isEmergencyUpdate) {
               await prefs.setString('dismissed_update_version', latestVersion);
               debugPrint('UpdateChecker: User dismissed update v$latestVersion');
             }
          });
        }
      }
    } catch (e) {
      debugPrint('UpdateChecker Error: $e');
    }
  }

  /// Listens to real-time updates from Firestore
  static StreamSubscription<DocumentSnapshot> listenForUpdates(BuildContext context) {
    return FirebaseFirestore.instance
        .collection('app_config')
        .doc('version')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && context.mounted) {
        _processUpdateSnapshot(context, snapshot);
      }
    }, onError: (e) => debugPrint('UpdateChecker Stream Error: $e'));
  }

  static Future<void> _processUpdateSnapshot(BuildContext context, DocumentSnapshot snapshot) async {
    try {
      final data = snapshot.data() as Map<String, dynamic>;
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      int currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;
      String currentVersion = packageInfo.version;

      // Safely parse build number
      var buildNumRaw = data['build_number'];
      int latestBuildNumber = 0;
      if (buildNumRaw is int) {
        latestBuildNumber = buildNumRaw;
      } else if (buildNumRaw is String) {
        latestBuildNumber = int.tryParse(buildNumRaw) ?? 0;
      }

      String latestVersion = data['latest_version'] ?? currentVersion;
      String releaseNotes = data['release_notes'] ?? 'New version available!';
      
      String downloadUrl = '';
      if (!kIsWeb && Platform.isAndroid) {
        downloadUrl = data['download_url_android'] ?? data['download_url'] ?? '';
      } else if (!kIsWeb && Platform.isWindows) {
        downloadUrl = data['download_url_windows'] ?? data['download_url'] ?? '';
      } else {
        downloadUrl = data['download_url'] ?? '';
      }

      var emergencyRaw = data['is_emergency'];
      bool isEmergencyUpdate = false; 
      if (emergencyRaw is bool) {
        isEmergencyUpdate = emergencyRaw;
      } else if (emergencyRaw is String) {
         isEmergencyUpdate = emergencyRaw.toLowerCase() == 'true';
      }

      int versionComparison = _compareVersions(latestVersion, currentVersion);
      bool isUpdateAvailable = false;
      
      if (versionComparison > 0) {
        isUpdateAvailable = true;
      } else if (versionComparison == 0) {
        if (latestBuildNumber > currentBuildNumber) {
          isUpdateAvailable = true;
        }
      }

      if (isUpdateAvailable && !_isDialogShowing) {
        // Check for dismissed version
        final prefs = await SharedPreferences.getInstance();
        final dismissedVersion = prefs.getString('dismissed_update_version');

        if (dismissedVersion == latestVersion && !isEmergencyUpdate) {
           return;
        }

        if (context.mounted) {
          _isDialogShowing = true;
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
          ).then((result) async {
             _isDialogShowing = false;
             if (result == true && !isEmergencyUpdate) {
               await prefs.setString('dismissed_update_version', latestVersion);
             }
          });
        }
      }
    } catch (e) {
      debugPrint('UpdateChecker Realtime Error: $e');
    }
  }

  /// Compares two version strings. 
  /// Returns 1 if latest > current, -1 if current > latest, and 0 if equal.
  static int _compareVersions(String latest, String current) {
    try {
      List<int> latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      
      int length = latestParts.length > currentParts.length ? latestParts.length : currentParts.length;
      
      for (int i = 0; i < length; i++) {
        int latestVal = i < latestParts.length ? latestParts[i] : 0;
        int currentVal = i < currentParts.length ? currentParts[i] : 0;
        
        if (latestVal > currentVal) return 1;
        if (currentVal > latestVal) return -1;
      }
      return 0;
    } catch (e) {
      return latest == current ? 0 : 1; // Fallback to simple string comparison if parsing fails
    }
  }
}
