
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static const _aliasKey = 'alias';
  static const _fingerprintKey = 'fingerprint';
  static const _pinEnabledKey = 'pin_enabled';
  static const _pinKey = 'pin';

  final SharedPreferences prefs;

  AppSettings._(this.prefs);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings._(prefs);
    if ((prefs.getString(_fingerprintKey) ?? '').isEmpty) {
      await prefs.setString(_fingerprintKey, settings._newFingerprint());
    }
    if ((prefs.getString(_aliasKey) ?? '').isEmpty) {
      await prefs.setString(_aliasKey, 'گوشی من');
    }
    return settings;
  }

  String get alias => prefs.getString(_aliasKey) ?? 'گوشی من';
  String get fingerprint => prefs.getString(_fingerprintKey) ?? _newFingerprint();
  bool get pinEnabled => prefs.getBool(_pinEnabledKey) ?? false;
  String get pin => prefs.getString(_pinKey) ?? '';

  Future<void> setAlias(String value) =>
      prefs.setString(_aliasKey, value.trim().isEmpty ? 'گوشی من' : value.trim());

  Future<void> setPinEnabled(bool value) =>
      prefs.setBool(_pinEnabledKey, value);

  Future<void> setPin(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final safe = digits.length > 6 ? digits.substring(0, 6) : digits;
    return prefs.setString(_pinKey, safe);
  }

  String _newFingerprint() {
    const chars = 'abcdef0123456789';
    final random = Random.secure();
    return List.generate(64, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
