import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'dart:async';
import '../services/demo_section_service.dart';

class GuideStep {
  final GlobalKey targetKey;
  final String title;
  final String content;
  final String? buttonLabel;
  final bool hideButton;
  final bool isBlocking; // NEW: Whether to block taps outside the spotlight
  final VoidCallback? onShow; // NEW: Callback when step is shown

  GuideStep({
    required this.targetKey,
    required this.title,
    required this.content,
    this.buttonLabel,
    this.hideButton = false,
    this.isBlocking = true,
    this.onShow,
  });
}

class GuidePointer extends StatefulWidget {
  final List<GuideStep> steps;
  final VoidCallback onComplete;

  final int? totalStepsOverride;
  final int initialStepOffset;

  const GuidePointer({
    super.key,
    required this.steps,
    required this.onComplete,
    this.totalStepsOverride,
    this.initialStepOffset = 0,
  });

  /// Static method to show the tour globally
  static OverlayEntry? _currentOverlay;
  static final GlobalKey<_GuidePointerState> _globalKey = GlobalKey<_GuidePointerState>();

  static void show(BuildContext context, {
    required List<GuideStep> steps,
    required VoidCallback onComplete,
    int? totalStepsOverride,
    int initialStepOffset = 0,
  }) {
    debugPrint('GUIDE: show() called with ${steps.length} steps');

    // Enable demo sections when guide starts
    DemoSectionService.enableDemoSections().then((_) {
      debugPrint('GUIDE: Demo sections enabled');
    });

    dismiss();
    
    // Use rootOverlay to ensure the guide is above everything (bottom bars, dialogs, etc.)
    final overlay = Overlay.of(context, rootOverlay: true);
    
    _currentOverlay = OverlayEntry(
      builder: (context) => GuidePointer(
        key: _globalKey,
        steps: steps,
        onComplete: () {
          debugPrint('GUIDE: onComplete triggered');
          dismiss();
          onComplete();
        },
        totalStepsOverride: totalStepsOverride,
        initialStepOffset: initialStepOffset,
      ),
    );
    overlay.insert(_currentOverlay!);
    debugPrint('GUIDE: Overlay inserted into rootOverlay successfully');
  }

  static void next() {
    _globalKey.currentState?.nextStep();
  }

  static void nextFor(GlobalKey key) {
    final state = _globalKey.currentState;
    if (state != null) {
      final currentStep = state.widget.steps[state._currentStepIndex];
      debugPrint('TOUR: nextFor called with key=${key.hashCode}, currentStep.targetKey=${currentStep.targetKey.hashCode}');
      if (currentStep.targetKey == key) {
        debugPrint('TOUR: Keys match! Advancing step...');
        state.nextStep();
      } else {
        debugPrint('TOUR: Keys do NOT match, ignoring nextFor call');
      }
    } else {
      debugPrint('TOUR: nextFor called but state is null');
    }
  }

  static void toggle(bool visible) {
    final state = _globalKey.currentState;
    if (state != null) {
      // Update blocking state immediately
      state.setInteractionAuth(visible);

      if (visible) {
        state._fadeController.forward();
        state._startTracking();
      } else {
        state._fadeController.reverse();
        state._stopTracking();
      }
    }
  }

  static void dismiss() {
    if (_currentOverlay != null) {
      debugPrint('GUIDE: dismissing current overlay');
      _currentOverlay?.remove();
      _currentOverlay = null;

      // Disable demo sections when guide ends
      DemoSectionService.disableDemoSections().then((_) {
        debugPrint('GUIDE: Demo sections disabled');
      });
    }
  }

  /// Dynamically update the current step's target to a new key
  static void updateTarget(GlobalKey newKey) {
    final state = _globalKey.currentState;
    if (state != null) {
      state._setTargetOverride(newKey);
    }
  }

  @override
  State<GuidePointer> createState() => _GuidePointerState();
}

class _GuidePointerState extends State<GuidePointer> with TickerProviderStateMixin {
  int _currentStepIndex = 0;
  
  // Optional override for the target key (for dynamic spotlight)
  GlobalKey? _targetKeyOverride;
  
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // For smooth spotlight transitions
  Rect? _targetRect;
  Rect? _previousRect;
  late AnimationController _moveController;
  late Animation<Rect?> _moveAnimation;

  Timer? _timer;

  void _setTargetOverride(GlobalKey? key) {
    if (mounted) {
      setState(() {
        _targetKeyOverride = key;
      });
      _updateTargetRect(immediate: true);
    }
  }

  @override
  void initState() {
    super.initState();
    
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _moveAnimation = RectTween(begin: null, end: null).animate(
      CurvedAnimation(parent: _moveController, curve: Curves.easeInOut),
    );

    // Initial check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTargetRect(immediate: true);
      _startTracking();
      // Call onShow for the very first step
      widget.steps[_currentStepIndex].onShow?.call();
    });
  }

  void _startTracking() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 32), (_) => _updateTargetRect());
  }

  void _stopTracking() {
    _timer?.cancel();
    _timer = null;
  }

  int _retryCount = 0;

  void _updateTargetRect({bool immediate = false}) {
    if (!mounted) return;
    
    final overlay = Overlay.of(context, rootOverlay: true);
    final RenderBox? overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    final step = widget.steps[_currentStepIndex];
    final targetKey = _targetKeyOverride ?? step.targetKey;
    final box = targetKey.currentContext?.findRenderObject() as RenderBox?;
    
    if (box != null && box.hasSize) {
      _retryCount = 0; // Reset retries on success
      try {
        final position = box.localToGlobal(Offset.zero, ancestor: overlayBox);
        final size = box.size;
        
        if (size.width > 0 && size.height > 0) {
          final newRect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
          
          if (_targetRect != newRect) {
            debugPrint('GUIDE: Target found! Rect=$newRect, Step=$_currentStepIndex');
            if (immediate || _targetRect == null) {
              setState(() {
                _targetRect = newRect;
                _previousRect = newRect;
              });
            } else {
              _previousRect = _targetRect;
              _targetRect = newRect;
              
              _moveAnimation = RectTween(
                begin: _previousRect,
                end: _targetRect,
              ).animate(CurvedAnimation(parent: _moveController, curve: Curves.easeInOut));
              
              _moveController.forward(from: 0);
            }
          }
        }
      } catch (e) {
        final position = box.localToGlobal(Offset.zero);
        final size = box.size;
        final newRect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
        setState(() {
          _targetRect = newRect;
          _previousRect = newRect;
        });
      }
    } else {
       // Target missing: retry silently for up to 2 seconds
       if (_retryCount < 20) {
         _retryCount++;
         debugPrint('GUIDE: Target NOT found for step $_currentStepIndex, retry $_retryCount/20...');
         Future.delayed(const Duration(milliseconds: 100), () => _updateTargetRect());
       } else {
         // Truly missing after 2 seconds: clear highlight
         if (_targetRect != null) {
           debugPrint('GUIDE: Giving up on target for step $_currentStepIndex after 2s');
           setState(() {
             _targetRect = null;
           });
         }
       }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeController.dispose();
    _pulseController.dispose();
    _moveController.dispose();
    super.dispose();
  }

  void nextStep() {
    debugPrint('TOUR: nextStep called, currentStepIndex was $_currentStepIndex');
    if (!mounted) return;
    if (_currentStepIndex < widget.steps.length - 1) {
      setState(() {
        _currentStepIndex++;
        _targetKeyOverride = null;
        _retryCount = 0; // Reset retry counter for new step
      });
      debugPrint('TOUR: Now on step $_currentStepIndex: ${widget.steps[_currentStepIndex].title}');
      
      widget.steps[_currentStepIndex].onShow?.call();
      // Restore smooth animations by NOT using immediate: true
      _updateTargetRect();
    } else {
      debugPrint('TOUR: Last step reached, completing tour');
      _fadeController.reverse().then((_) {
        if (mounted) widget.onComplete();
      });
    }
  }

  void _handleGlobalTap(PointerDownEvent event) {
    if (_targetRect == null) return;
    
    // Inflate slightly to match visual hole + margin
    final rect = _targetRect!.inflate(12.0);
    
    if (rect.contains(event.position)) {
      // ONLY advance on hole-tap if it's an informational step (has a button)
      // and NOT blocking (or if we want tap-to-advance for info tips).
      // For interactive steps (hideButton: true), we NEVER advance on tap.
      if (!widget.steps[_currentStepIndex].hideButton) {
          nextStep();
      }
    }
  }

  bool _isInteractionPaused = false;

  void setInteractionAuth(bool visible) {
      if (mounted) {
          setState(() {
              _isInteractionPaused = !visible;
          });
      }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: _isInteractionPaused,
      child: AnimatedBuilder(
        animation: Listenable.merge([_moveController, _pulseAnimation, _fadeAnimation]),
        builder: (context, child) {
        final currentDisplayRect = _moveController.isAnimating 
            ? _moveAnimation.value 
            : _targetRect;

        final rect = currentDisplayRect?.inflate(12.0) ?? Rect.zero; 
        final hasRect = currentDisplayRect != null;
        
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;

        final step = widget.steps[_currentStepIndex];
        // Check available safe space
        final padding = MediaQuery.of(context).padding;
        final double safeSpaceAbove = rect.top - padding.top;
        final double safeSpaceBelow = screenHeight - rect.bottom - padding.bottom;
        
        const double requiredHeight = 120.0; // Reduced estimate to prevent aggressive bottom-snapping
        
        bool isArrowUp;
        if (safeSpaceBelow >= requiredHeight && safeSpaceAbove < requiredHeight) {
          isArrowUp = true; // Must go below
        } else if (safeSpaceAbove >= requiredHeight && safeSpaceBelow < requiredHeight) {
          isArrowUp = false; // Must go above
        } else {
          // Both fit or neither fit: pick the larger space
          isArrowUp = safeSpaceBelow >= safeSpaceAbove;
        }

        // SAFETY: If BOTH spaces are too small (< requiredHeight), force center placement (ignoring rect for positioning)
        // This ensures the text is always visible even if it overlaps the hole slightly.
        final bool forceCenter = safeSpaceAbove < requiredHeight && safeSpaceBelow < requiredHeight;

        return Listener(
          onPointerDown: _handleGlobalTap,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            children: [
              // 1. Dark Overlay with Spotlight
              IgnorePointer(
                child: SizedBox.expand(
                  child: CustomPaint(
                    painter: SpotlightPainter(
                      targetRect: currentDisplayRect ?? Rect.zero,
                      isVisible: hasRect,
                      pulseValue: _pulseAnimation.value,
                      opacity: _fadeAnimation.value,
                    ),
                  ),
                ),
              ),

              // 2. Tap Blockers
              if (hasRect && step.isBlocking) ...[
                Positioned(
                  top: 0, left: 0, right: 0, height: rect.top,
                  child: GestureDetector(onTap: () {}, behavior: HitTestBehavior.opaque, child: const SizedBox()),
                ),
                Positioned(
                  top: rect.bottom, left: 0, right: 0, bottom: 0,
                  child: GestureDetector(onTap: () {}, behavior: HitTestBehavior.opaque, child: const SizedBox()),
                ),
                Positioned(
                  top: rect.top, bottom: screenHeight - rect.bottom, left: 0, width: rect.left,
                  child: GestureDetector(onTap: () {}, behavior: HitTestBehavior.opaque, child: const SizedBox()),
                ),
                Positioned(
                  top: rect.top, bottom: screenHeight - rect.bottom, right: 0, width: screenWidth - rect.right,
                  child: GestureDetector(onTap: () {}, behavior: HitTestBehavior.opaque, child: const SizedBox()),
                ),
                // ONLY block the hole itself if isBlocking is true AND it's an informational step (hideButton: false)
                // If it's an interactive step (hideButton: true), we leave the hole open for user input!
                if (step.isBlocking && !step.hideButton)
                  Positioned.fromRect(
                     rect: rect,
                     child: GestureDetector(onTap: () {}, behavior: HitTestBehavior.opaque, child: const SizedBox()),
                  ),
              ] else if (!hasRect && step.isBlocking)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const SizedBox.expand(),
                ),

              // 3. Header Controls
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 20,
                right: 20,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: HexColor("#116754"),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                          ),
                          child: Text(
                            "Tip ${_currentStepIndex + 1 + widget.initialStepOffset} of ${widget.totalStepsOverride ?? widget.steps.length}",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      // Close button moved to right alignment in Row
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        onPressed: widget.onComplete,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(40, 40),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ),

              // 4. Instruction Card
              Positioned(
                left: 0,
                right: 0,
                top: (hasRect && !forceCenter)
                    ? (isArrowUp ? rect.bottom + 20 : null)
                    : null, 
                bottom: (hasRect && !forceCenter)
                    ? (!isArrowUp ? (screenHeight - rect.top) + 20 : null)
                    : (forceCenter ? 50 : null), // Raised from 30 to 50
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Material(
                  type: MaterialType.transparency,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasRect && isArrowUp && !forceCenter)
                          const Icon(Icons.arrow_drop_up, color: Colors.white, size: 40),
                        Container(
                          padding: const EdgeInsets.all(20),
                            constraints: BoxConstraints(
                              maxHeight: screenHeight * 0.4, // Max 40% of screen height
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 40,
                                  offset: Offset(0, 15),
                                ),
                              ],
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                                        child: Icon(Icons.lightbulb_outline, color: HexColor("#116754")),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          step.title,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold, 
                                            fontSize: 18, // Reduced from 22
                                            color: HexColor("#116754"),
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    step.content,
                                    style: TextStyle(fontSize: 15, height: 1.5, color: Colors.grey[800]), // Reduced from 17
                                  ),
                                  if (!step.hideButton) ...[
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: nextStep,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: HexColor("#116754"),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          elevation: 4,
                                          shadowColor: HexColor("#116754").withValues(alpha: 0.4),
                                        ),
                                        child: Text(
                                          step.buttonLabel ?? (_currentStepIndex < widget.steps.length - 1 ? "Next Tip" : "Finish"),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        if (hasRect && !isArrowUp && !forceCenter)
                          const Icon(Icons.arrow_drop_down, color: Colors.white, size: 40),
                      ],
                    ),
                  ),
                ),
              ),
                ),
              ),
            ],
          ),
        );
      },
    ),
    );
  }
}

class SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final bool isVisible;
  final double pulseValue;
  final double opacity;

  SpotlightPainter({
    required this.targetRect, 
    required this.isVisible,
    required this.pulseValue,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // FALLBACK: If no spotlight is visible (rect is zero), show a less dark overlay (40%) 
    // instead of blocking the entire screen (85%), so the user can still orientations themselves.
    final bool hasSpotlight = isVisible && !targetRect.isEmpty;
    final overlayColor = Colors.black.withValues(
      alpha: (hasSpotlight ? 0.85 : 0.4) * opacity
    );
    
    final overlayPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    if (!hasSpotlight) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), overlayPaint);
      return;
    }

    // 1. Draw Background with Hole
    final fullPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        targetRect.inflate(12), 
        const Radius.circular(16),
      ));

    final combinedPath = Path.combine(
      PathOperation.difference,
      fullPath,
      holePath,
    );
    canvas.drawPath(combinedPath, overlayPaint);

    // 2. Pulsating Glow Effect
    final glowOpacity = (0.3 + (pulseValue * 0.4)) * opacity;
    final glowInflation = 12.0 + (pulseValue * 8.0);
    
    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: glowOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 + (pulseValue * 2);
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        targetRect.inflate(glowInflation), 
        Radius.circular(16 + (pulseValue * 4)),
      ),
      glowPaint,
    );

    // 3. Inner Sharp Border
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        targetRect.inflate(12), 
        const Radius.circular(16),
      ),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(SpotlightPainter oldDelegate) {
    return true; // We animate pulse and move
  }
}
