import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight key-value cache for non-sensitive snapshots.
class KvCache {
  KvCache(this._prefs);
  final SharedPreferences _prefs;

  Future<void> putJson(String key, Object? value) async {
    if (value == null) {
      await _prefs.remove(key);
      return;
    }
    await _prefs.setString(key, jsonEncode(value));
  }

  T? readJson<T>(String key, T Function(Object json) decoder) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoder(decoded as Object);
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) => _prefs.remove(key);
  Future<void> clear() => _prefs.clear();

  bool getBool(String key, {bool defaultValue = false}) =>
      _prefs.getBool(key) ?? defaultValue;
  Future<void> setBool(String key, bool v) => _prefs.setBool(key, v);

  int? getInt(String key) => _prefs.getInt(key);
  Future<void> setInt(String key, int v) => _prefs.setInt(key, v);

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String v) => _prefs.setString(key, v);
}
