import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Service to monitor network connectivity status
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final _connectivityController = StreamController<bool>.broadcast();
  
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Stream that emits true when online, false when offline
  Stream<bool> get connectivityStream => _connectivityController.stream;

  /// Current connectivity status
  bool get isOnline => _isOnline;

  /// Initialize connectivity monitoring
  Future<void> init() async {
    try {
      // Check initial status
      await _checkConnectivity();

      // Listen to connectivity changes
      _subscription = _connectivity.onConnectivityChanged.listen(
        (List<ConnectivityResult> results) {
          try {
            _updateConnectivityStatus(results);
          } catch (e) {
            debugPrint('ConnectivityService: Error in connectivity listener: $e');
            // Default to offline on error
            _updateStatus(false);
          }
        },
        onError: (error) {
          debugPrint('ConnectivityService: Stream error: $error');
          // Default to online on stream error to avoid blocking UI
          _updateStatus(true);
        },
        cancelOnError: false, // Keep listening even on errors
      );
    } catch (e) {
      debugPrint('ConnectivityService: Initialization error: $e');
      // Default to online if initialization fails
      _updateStatus(true);
    }
  }

  /// Check current connectivity status
  Future<void> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectivityStatus(results);
    } catch (e) {
      debugPrint('ConnectivityService: Error checking connectivity: $e');
      // Default to online if check fails
      _updateStatus(true);
    }
  }

  /// Update connectivity status based on results
  void _updateConnectivityStatus(List<ConnectivityResult> results) {
    // Consider online if we have ANY connection result that isn't 'none'
    // This is more robust for VPNs or 'other' Desktop connections
    final isOnline = results.any((result) => result != ConnectivityResult.none);

    _updateStatus(isOnline);
  }

  /// Update status and notify listeners
  void _updateStatus(bool online) {
    try {
      if (_isOnline != online) {
        _isOnline = online;
        if (!_connectivityController.isClosed) {
          _connectivityController.add(_isOnline);
        }
        debugPrint('ConnectivityService: Status changed to ${online ? "ONLINE" : "OFFLINE"}');
      }
    } catch (e) {
      debugPrint('ConnectivityService: Error updating status: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _subscription?.cancel();
    _connectivityController.close();
  }
}
