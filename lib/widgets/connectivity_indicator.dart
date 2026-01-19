import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lime/services/connectivity_service.dart';

/// Widget that displays online/offline status indicator
class ConnectivityIndicator extends StatefulWidget {
  final bool showText;
  final EdgeInsets? padding;
  
  const ConnectivityIndicator({
    super.key,
    this.showText = true,
    this.padding,
  });

  @override
  State<ConnectivityIndicator> createState() => _ConnectivityIndicatorState();
}

class _ConnectivityIndicatorState extends State<ConnectivityIndicator> {
  final ConnectivityService _connectivityService = ConnectivityService();
  bool _isOnline = true;
  StreamSubscription<bool>? _subscription;

  @override
  void initState() {
    super.initState();
    try {
      _isOnline = _connectivityService.isOnline;
      _subscription = _connectivityService.connectivityStream.listen(
        (isOnline) {
          if (mounted) {
            setState(() {
              _isOnline = isOnline;
            });
          }
        },
        onError: (error) {
          debugPrint('ConnectivityIndicator: Stream error: $error');
          // Default to online on error to avoid blocking UI
          if (mounted) {
            setState(() {
              _isOnline = true;
            });
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('ConnectivityIndicator: Initialization error: $e');
      // Default to online to avoid blocking UI
      _isOnline = true;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Make it responsive - smaller on mobile
    final isMobile = MediaQuery.of(context).size.width < 600;
    final dotSize = isMobile ? 6.0 : 8.0;
    final padding = widget.padding ?? (isMobile 
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 6));
    
    return Container(
      padding: padding,
      constraints: BoxConstraints(
        minWidth: isMobile ? 20 : 24,
        minHeight: isMobile ? 20 : 24,
      ),
      decoration: BoxDecoration(
        color: _isOnline 
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(isMobile ? 12 : 20),
        border: Border.all(
          color: _isOnline ? Colors.green : Colors.orange,
          width: isMobile ? 0.8 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            size: dotSize * 1.5,
            color: _isOnline ? Colors.green : Colors.orange,
          ),
          if (widget.showText && !isMobile) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _isOnline ? Colors.green.shade700 : Colors.orange.shade700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Banner widget that shows at the top when offline
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    try {
      return StreamBuilder<bool>(
        stream: ConnectivityService().connectivityStream,
        initialData: ConnectivityService().isOnline,
        builder: (context, snapshot) {
          // Handle errors gracefully
          if (snapshot.hasError) {
            debugPrint('OfflineBanner: Stream error: ${snapshot.error}');
            // Default to showing nothing on error
            return const SizedBox.shrink();
          }

          final isOnline = snapshot.data ?? true;
          
          if (isOnline) {
            return const SizedBox.shrink();
          }

          // Make banner responsive - smaller on mobile
          final isMobile = MediaQuery.of(context).size.width < 600;
          
          return Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                vertical: isMobile ? 6 : 8,
                horizontal: isMobile ? 12 : 16,
              ),
              color: Colors.orange.shade700,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.white,
                    size: isMobile ? 18 : 20,
                  ),
                  SizedBox(width: isMobile ? 6 : 8),
                  Flexible(
                    child: Text(
                      isMobile 
                          ? 'You\'re offline'
                          : 'You\'re offline. Some features may be limited.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 12 : 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('OfflineBanner: Build error: $e');
      // Return empty widget on error to prevent red screen
      return const SizedBox.shrink();
    }
  }
}
