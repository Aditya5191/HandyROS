import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted, app-wide user settings (ROS domain ID, theme mode).
/// A single instance is created once in main() and passed down —
/// [AppSettings.load] must complete before the app reads any values.
class AppSettings extends ChangeNotifier {
  static const _kDomainIdKey = 'ros_domain_id';
  static const _kThemeModeKey = 'theme_mode';

  final SharedPreferences _prefs;

  int _domainId;
  ThemeMode _themeMode;

  AppSettings._(this._prefs, this._domainId, this._themeMode);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final domainId = prefs.getInt(_kDomainIdKey) ?? 0;
    final themeModeIndex = prefs.getInt(_kThemeModeKey);
    final themeMode =
        themeModeIndex != null && themeModeIndex < ThemeMode.values.length
        ? ThemeMode.values[themeModeIndex]
        : ThemeMode.system;
    return AppSettings._(prefs, domainId, themeMode);
  }

  int get domainId => _domainId;
  ThemeMode get themeMode => _themeMode;

  /// Takes effect on the next DDS (re)connect — changing the domain ID
  /// of an already-running participant isn't supported by DDS, so this
  /// doesn't tear down/rebuild the live connection itself.
  Future<void> setDomainId(int value) async {
    if (value == _domainId) return;
    _domainId = value;
    await _prefs.setInt(_kDomainIdKey, value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    await _prefs.setInt(_kThemeModeKey, mode.index);
    notifyListeners();
  }
}
