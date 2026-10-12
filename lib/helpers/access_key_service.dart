import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:lib_boloto_launcher/helpers/shared_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccessKeyService {
  // You can configure this URL based on your API endpoint
  static const String _baseUrl = 'https://your-api-endpoint.com/validate-key';

  /// Validates an access key by making a GET request to the API
  /// Returns the modpack info if valid, null if invalid
  static Future<Map<String, dynamic>?> validateAccessKey(
    String accessKey,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl?key=$accessKey'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      // Handle network errors or other exceptions
      print('Error validating access key: $e');
      return null;
    }
  }

  /// Validates and saves an access key, returns modpack info if successful
  static Future<Map<String, dynamic>?> saveAccessKey(String accessKey) async {
    try {
      final modpackInfo = await validateAccessKey(accessKey);

      if (modpackInfo == null) {
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final modpackId =
          modpackInfo['id']?.toString() ??
          modpackInfo['modpack_id']?.toString() ??
          'unknown';

      // Get existing access keys
      final existingKeys = prefs.getStringList(PrefKeys.accessKeys) ?? [];

      // Add new key if not already present
      if (!existingKeys.contains(accessKey)) {
        existingKeys.add(accessKey);
        await prefs.setStringList(PrefKeys.accessKeys, existingKeys);
      }

      // Get existing enabled modpacks
      final enabledModpacks =
          prefs.getStringList(PrefKeys.enabledModpacks) ?? [];

      // Enable the modpack if not already enabled
      if (!enabledModpacks.contains(modpackId)) {
        enabledModpacks.add(modpackId);
        await prefs.setStringList(PrefKeys.enabledModpacks, enabledModpacks);
      }

      return modpackInfo;
    } catch (e) {
      print('Error saving access key: $e');
      return null;
    }
  }

  /// Removes an access key and disables the associated modpack
  static Future<void> removeAccessKey(
    String accessKey,
    String modpackId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Remove from access keys
      final accessKeys = prefs.getStringList(PrefKeys.accessKeys) ?? [];
      accessKeys.remove(accessKey);
      await prefs.setStringList(PrefKeys.accessKeys, accessKeys);

      // Remove from enabled modpacks
      final enabledModpacks =
          prefs.getStringList(PrefKeys.enabledModpacks) ?? [];
      enabledModpacks.remove(modpackId);
      await prefs.setStringList(PrefKeys.enabledModpacks, enabledModpacks);
    } catch (e) {
      print('Error removing access key: $e');
    }
  }

  /// Gets all stored access keys
  static Future<List<String>> getAccessKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(PrefKeys.accessKeys) ?? [];
  }

  /// Gets all enabled modpacks
  static Future<List<String>> getEnabledModpacks() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(PrefKeys.enabledModpacks) ?? [];
  }

  /// Checks if a specific modpack is enabled
  static Future<bool> isModpackEnabled(String modpackId) async {
    final enabledModpacks = await getEnabledModpacks();
    return enabledModpacks.contains(modpackId);
  }
}
