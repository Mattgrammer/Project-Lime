import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:lime/services/connectivity_service.dart';

/// Service to handle offline data synchronization
class OfflineSyncService {
  static final OfflineSyncService _instance = OfflineSyncService._internal();
  factory OfflineSyncService() => _instance;
  OfflineSyncService._internal();

  FirebaseFirestore? _firestoreInstance;
  FirebaseFirestore get _firestore => _firestoreInstance ?? FirebaseFirestore.instance;

  final ConnectivityService _connectivityService = ConnectivityService();
  StreamSubscription<bool>? _connectivitySubscription;
  
  bool _isSyncing = false;
  DateTime? _lastSyncTime;

  /// Initialize sync service and listen for connectivity changes
  Future<void> init() async {
    try {
      // Listen for connectivity changes
      _connectivitySubscription = _connectivityService.connectivityStream.listen(
        (isOnline) {
          try {
            if (isOnline && !_isSyncing) {
              _syncWhenOnline();
            }
          } catch (e) {
            debugPrint('OfflineSyncService: Error in connectivity listener: $e');
          }
        },
        onError: (error) {
          debugPrint('OfflineSyncService: Stream error: $error');
          // Don't crash on stream errors
        },
        cancelOnError: false,
      );

      // If already online, sync immediately (with delay to avoid blocking)
      if (_connectivityService.isOnline) {
        // Delay to ensure app is fully initialized
        Future.delayed(const Duration(seconds: 1), () {
          _syncWhenOnline();
        });
      }
    } catch (e) {
      debugPrint('OfflineSyncService: Initialization error: $e');
      // Continue anyway - sync is not critical for app startup
    }
  }

  /// Sync data when coming back online
  Future<void> _syncWhenOnline() async {
    if (_isSyncing) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('OfflineSyncService: No user logged in, skipping sync');
        return;
      }

      _isSyncing = true;
      debugPrint('OfflineSyncService: Starting sync...');

      // Wait a bit for network to stabilize
      await Future.delayed(const Duration(seconds: 2));

      // Double-check connectivity before proceeding
      if (!_connectivityService.isOnline) {
        debugPrint('OfflineSyncService: Lost connection during sync wait');
        _isSyncing = false;
        return;
      }

      // Force Firestore to sync pending writes
      // Firestore automatically syncs when online, but we can trigger a check
      try {
        await _firestore.enableNetwork().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('OfflineSyncService: enableNetwork timed out');
          },
        );
      } catch (e) {
        debugPrint('OfflineSyncService: Error enabling network: $e');
        // Continue anyway - Firestore will sync automatically
      }
      
      // Wait for sync to complete
      await Future.delayed(const Duration(seconds: 1));

      _lastSyncTime = DateTime.now();
      debugPrint('OfflineSyncService: Sync completed at $_lastSyncTime');
    } catch (e, stackTrace) {
      debugPrint('OfflineSyncService: Error during sync: $e');
      debugPrint('OfflineSyncService: Stack trace: $stackTrace');
      // Don't rethrow - sync failures shouldn't crash the app
    } finally {
      _isSyncing = false;
    }
  }

  /// Manually trigger sync
  Future<void> syncNow() async {
    if (!_connectivityService.isOnline) {
      debugPrint('OfflineSyncService: Cannot sync - offline');
      return;
    }
    await _syncWhenOnline();
  }

  /// Get last sync time
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Check if currently syncing
  bool get isSyncing => _isSyncing;

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
