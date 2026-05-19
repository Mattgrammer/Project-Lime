import 'package:shared_preferences/shared_preferences.dart';

class PinLoginService {
  static const String _pinPrefix = 'user_pin_';

  /// Saves the 4-digit PIN for the given user ID.
  static Future<void> setPin(String uid, String pin) async {
    if (pin.length != 4) throw Exception('PIN must be 4 digits');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_pinPrefix$uid', pin);
  }

  /// Verifies if the entered PIN matches the stored PIN.
  static Future<bool> verifyPin(String uid, String enteredPin) async {
    final prefs = await SharedPreferences.getInstance();
    final storedPin = prefs.getString('$_pinPrefix$uid');
    return storedPin == enteredPin;
  }

  /// Checks if the user has a PIN configured.
  static Future<bool> hasPin(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_pinPrefix$uid');
  }

  /// Removes the PIN for the user (e.g. on disable).
  static Future<void> removePin(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_pinPrefix$uid');
  }
}
