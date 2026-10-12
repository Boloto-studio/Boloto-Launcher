import 'package:shared_preferences/shared_preferences.dart';

class PrefKeys {
  static const packPath = 'packPath';
  static const hoursPlayed = 'hoursPlayed';
  static const accessKeys = 'accessKeys';
  static const enabledModpacks = 'enabledModpacks';
}

class SharedPreferencesHelper {
  static Future<SharedPreferences> getInstance() async {
    return await SharedPreferences.getInstance();
  }

  static Future<void> setString(String key, String value) async {
    final prefs = await getInstance();
    await prefs.setString(key, value);
  }

  static Future<String?> getString(String key) async {
    final prefs = await getInstance();
    return prefs.getString(key);
  }

  static Future<void> setBool(String key, bool value) async {
    final prefs = await getInstance();
    await prefs.setBool(key, value);
  }

  static Future<bool?> getBool(String key) async {
    final prefs = await getInstance();
    return prefs.getBool(key);
  }

  static Future<void> setInt(String key, int value) async {
    final prefs = await getInstance();
    await prefs.setInt(key, value);
  }

  static Future<int?> getInt(String key) async {
    final prefs = await getInstance();
    return prefs.getInt(key);
  }

  static Future<void> remove(String key) async {
    final prefs = await getInstance();
    await prefs.remove(key);
  }
}
