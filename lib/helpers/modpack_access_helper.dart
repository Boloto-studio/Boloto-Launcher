import 'package:lib_boloto_launcher/helpers/access_key_service.dart';

/// Example utility class showing how to use the access key system
/// throughout your application
class ModpackAccessHelper {
  /// Check if a user has access to a specific modpack before showing it
  static Future<bool> canAccessModpack(String modpackId) async {
    return await AccessKeyService.isModpackEnabled(modpackId);
  }

  /// Filter a list of modpacks to only show those the user has access to
  static Future<List<String>> filterAccessibleModpacks(
    List<String> allModpacks,
  ) async {
    final enabledModpacks = await AccessKeyService.getEnabledModpacks();
    return allModpacks
        .where((modpack) => enabledModpacks.contains(modpack))
        .toList();
  }

  /// Get all modpacks that the user currently has access to
  static Future<List<String>> getUserAccessibleModpacks() async {
    return await AccessKeyService.getEnabledModpacks();
  }
}
