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
          // Default to offline on stream error
          _updateStatus(false);
        },
        cancelOnError: false, // Keep listening even on errors
      );
    } catch (e) {
      debugPrint('ConnectivityService: Initialization error: $e');
      // Default to offline if initialization fails
      _updateStatus(false);
    }
  }

  /// Check current connectivity status
  Future<void> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectivityStatus(results);
    } catch (e) {
      debugPrint('ConnectivityService: Error checking connectivity: $e');
      // Default to offline if check fails
      _updateStatus(false);
    }
  }

  /// Update connectivity status based on results
  void _updateConnectivityStatus(List<ConnectivityResult> results) {
    // Consider online if we have WiFi, mobile data, or ethernet
    final isOnline = results.any((result) =>
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet);

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
