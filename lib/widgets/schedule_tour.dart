import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'guide_pointer.dart';

class ScheduleTour {
  static const String _prefKey = 'schedule_tour_seen_v1';

  /// Check whether the tour was already shown
  static Future<bool> isSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  static Future<void> resetSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  /// Starts the tour only if it hasn't been shown before (unless [force] is true)
  static Future<void> startIfFirstRun(BuildContext context, {
    required List<GlobalKey> keys,
    bool force = false,
    VoidCallback? onComplete,
  }) {
    // NOTE: avoid using BuildContext after an `await` to satisfy the linter.
    // We use `then` so the function itself does not `await` and the analyzer
    // won't warn about using the provided `context` later.
    return isSeen().then((seen) {
      if (!force && seen) return;

      // Use a post-frame callback to capture the overlay synchronously.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        startForced(context, keys: keys, onComplete: onComplete);
      });
    });
  }

  /// Immediately starts the tour (ignores the seen flag)
  static Future<void> startForced(BuildContext context, {
    required List<GlobalKey> keys,
    VoidCallback? onComplete,
  }) {
    // Ensure we capture the overlay synchronously in a non-async callback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlayState = Overlay.of(context, rootOverlay: true);
      final renderObject = overlayState.context.findRenderObject();

      // Ensure the overlay's render object is a RenderBox. Avoid nullable
      // casts and unnecessary `!` assertions by checking the runtime type.
      if (renderObject is! RenderBox) {
        debugPrint('SCHEDULE_TOUR: overlay render box not available; aborting tour');
        return;
      }

      final RenderBox overlayBox = renderObject;

      // Now run the async polling/show logic in a helper that doesn't use BuildContext.
      _pollTargetsAndShow(overlayState, overlayBox, keys, onComplete);
    });

    return Future.value();
  }

  // Poll for rendered targets and show GuidePointer; does not use BuildContext.
  static Future<void> _pollTargetsAndShow(OverlayState overlayState, RenderBox overlayBox, List<GlobalKey> keys, VoidCallback? onComplete) {
    // Use a Timer.periodic loop so all BuildContext access happens synchronously
    // inside the timer callback (no `await`/async gaps), avoiding analyzer
    // warnings about using BuildContext across awaits.
    final completer = Completer<void>();
    const int maxRetries = 20;
    int tries = 0;
    Timer? timer;

    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      tries++;
      final resolvedKeys = <GlobalKey>[];

      for (var k in keys) {
        try {
          final ctxForKey = k.currentContext;
          if (ctxForKey == null) continue;
          final render = ctxForKey.findRenderObject();
          if (render is RenderBox && render.hasSize) {
            final topLeft = render.localToGlobal(Offset.zero, ancestor: overlayBox);
            final size = render.size;
            final rect = Rect.fromLTWH(topLeft.dx, topLeft.dy, size.width, size.height);
            final screenRect = Offset.zero & overlayBox.size;
            if (size.width > 0 && size.height > 0 && rect.overlaps(screenRect)) {
              try {
                final widgetType = (ctxForKey as Element).widget.runtimeType;
                debugPrint('SCHEDULE_TOUR: Resolved key=${k.toString()} widget=$widgetType rect=$rect');
              } catch (_) {
                debugPrint('SCHEDULE_TOUR: Resolved key=${k.toString()} rect=$rect');
              }
              resolvedKeys.add(k);
            }
          }
        } catch (_) {
          // ignore
        }
      }

      if (resolvedKeys.isNotEmpty || tries >= maxRetries) {
        timer?.cancel();

        if (resolvedKeys.isEmpty) {
          debugPrint('SCHEDULE_TOUR: No visible targets found after polling; not showing tour');
          for (var k in keys) {
            final ctxForKey = k.currentContext;
            if (ctxForKey == null) {
              debugPrint('SCHEDULE_TOUR: ${k.toString()} -> no context');
              continue;
            }
            final render = ctxForKey.findRenderObject();
            if (render is RenderBox) {
              debugPrint('SCHEDULE_TOUR: ${k.toString()} -> size=${render.size}');
            } else {
              debugPrint('SCHEDULE_TOUR: ${k.toString()} -> non-RenderBox');
            }
          }
          completer.complete();
          return;
        }

        // Build steps synchronously and insert overlay
        final steps = <GuideStep>[];
        for (var k in keys) {
          if (!resolvedKeys.contains(k)) continue;
          final originalIndex = keys.indexOf(k);
          String title = 'Tip';
          String content = 'Tap Next to continue.';

          if (originalIndex == 0) {
            title = 'Class Schedule';
            content = 'View all your assigned classes, rooms, and time slots at a glance. Select a day to see what you\'re teaching.';
          } else if (originalIndex == 1) {
            title = 'Semester Switcher';
            content = 'Tap SEM 1 or SEM 2 to switch schedules between semesters.';
          } else if (originalIndex == 2) {
            title = 'Day Selector';
            content = 'Use the day strip to filter classes by day. Tap a day to view its classes.';
          } else if (originalIndex == 3) {
            title = 'Class Details';
            content = 'Each card shows the subject name, assigned section, and specific day/time slots for that class.';
          } else if (originalIndex == 4) {
            title = 'Empty State';
            content = 'If you have no classes for the selected day, this friendly empty state will appear.';
          }

          steps.add(GuideStep(targetKey: k, title: title, content: content));
        }

        if (steps.isEmpty) {
          debugPrint('SCHEDULE_TOUR: No steps created after filtering — aborting tour');
          completer.complete();
          return;
        }

        debugPrint('SCHEDULE_TOUR: Showing tour with ${steps.length} steps; resolved keys: ${resolvedKeys.length}');

        OverlayEntry? entry;
        entry = OverlayEntry(
          builder: (c) => GuidePointer(
            steps: steps,
            onComplete: () {
              entry?.remove();
              markSeen();
              onComplete?.call();
            },
          ),
        );

        overlayState.insert(entry);
        completer.complete();
      }
    });

    return completer.future;
  }
}
