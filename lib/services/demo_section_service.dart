import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage demo section visibility
/// Used by tutorial/onboarding system to show/hide demo sections
class DemoSectionService {
  static const String _flagKey = 'show_demo_sections';

  /// Enable demo sections (for tutorial mode)
  static Future<void> enableDemoSections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_flagKey, true);
  }

  /// Disable demo sections (for normal app usage)
  static Future<void> disableDemoSections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_flagKey, false);
  }

  /// Check if demo sections are currently enabled
  static Future<bool> areDemoSectionsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_flagKey) ?? false;
  }

  /// Toggle demo sections visibility
  static Future<bool> toggleDemoSections() async {
    final prefs = await SharedPreferences.getInstance();
    final currentState = prefs.getBool(_flagKey) ?? false;
    await prefs.setBool(_flagKey, !currentState);
    return !currentState;
  }
}
