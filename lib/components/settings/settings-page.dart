import 'package:flutter/material.dart';
import 'package:lib_boloto_launcher/helpers/shared_preferences.dart';
import 'package:lib_boloto_launcher/helpers/access_key_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lib_boloto_launcher/theme/boloto_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _pathController = TextEditingController();
  final _accessKeyController = TextEditingController();

  List<String> _accessKeys = [];
  List<String> _enabledModpacks = [];
  bool _isValidatingKey = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPrefs();
  }

  Future<void> _loadSavedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _pathController.text = prefs.getString(PrefKeys.packPath) ?? '';

    // Load access keys and enabled modpacks
    final accessKeys = await AccessKeyService.getAccessKeys();
    final enabledModpacks = await AccessKeyService.getEnabledModpacks();

    setState(() {
      _accessKeys = accessKeys;
      _enabledModpacks = enabledModpacks;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.packPath, _pathController.text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Settings saved!',
          style: TextStyle(color: BolotoTheme.background),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
        ),
        // behavior: SnackBarBehavior.floating,
        backgroundColor: BolotoTheme.textOnDark,
      ),
    );
  }

  Future<void> _validateAndSaveAccessKey() async {
    final accessKey = _accessKeyController.text.trim();

    if (accessKey.isEmpty) {
      _showSnackBar('Please enter an access key', isError: true);
      return;
    }

    setState(() {
      _isValidatingKey = true;
    });

    try {
      final modpackInfo = await AccessKeyService.saveAccessKey(accessKey);

      if (modpackInfo != null) {
        final modpackName =
            modpackInfo['name'] ?? modpackInfo['title'] ?? 'Unknown Modpack';
        _showSnackBar('Access key validated! Enabled: $modpackName');
        _accessKeyController.clear();
        await _loadSavedPrefs(); // Refresh the lists
      } else {
        _showSnackBar(
          'Invalid access key. Please check and try again.',
          isError: true,
        );
      }
    } catch (e) {
      _showSnackBar(
        'Error validating access key. Please try again.',
        isError: true,
      );
    } finally {
      setState(() {
        _isValidatingKey = false;
      });
    }
  }

  Future<void> _removeAccessKey(String accessKey, String modpackId) async {
    await AccessKeyService.removeAccessKey(accessKey, modpackId);
    _showSnackBar('Access key removed and modpack disabled');
    await _loadSavedPrefs(); // Refresh the lists
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: BolotoTheme.background),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
        ),
        backgroundColor: isError ? Colors.red : BolotoTheme.textOnDark,
      ),
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    _accessKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Installation Path Section
            TextFormField(
              controller: _pathController,
              decoration: const InputDecoration(labelText: 'Installation path'),
              validator: (val) =>
                  val == null || val.isEmpty ? 'Enter the path' : null,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                if (_formKey.currentState?.validate() ?? false) {
                  _savePrefs();
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),

            const SizedBox(height: 40),

            // Access Keys Section
            const Text(
              'Access Keys',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Add Access Key Form
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add New Access Key',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _accessKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Access Key',
                        hintText: 'Enter your access key',
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isValidatingKey
                          ? null
                          : _validateAndSaveAccessKey,
                      icon: _isValidatingKey
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.key),
                      label: Text(
                        _isValidatingKey ? 'Validating...' : 'Validate Key',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Active Access Keys List
            if (_accessKeys.isNotEmpty) ...[
              const Text(
                'Active Access Keys',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              ...(_accessKeys.asMap().entries.map((entry) {
                final index = entry.key;
                final key = entry.value;
                final modpackId = index < _enabledModpacks.length
                    ? _enabledModpacks[index]
                    : 'Unknown';

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.vpn_key, color: Colors.green),
                    title: Text('Key: ${key.substring(0, 8)}...'),
                    subtitle: Text('Modpack: $modpackId'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _removeAccessKey(key, modpackId),
                    ),
                  ),
                );
              }).toList()),
            ],

            if (_enabledModpacks.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Enabled Modpacks',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              ..._enabledModpacks
                  .map(
                    (modpack) => Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        ),
                        title: Text(modpack),
                        subtitle: const Text('Access granted'),
                      ),
                    ),
                  )
                  .toList(),
            ],
          ],
        ),
      ),
    );
  }
}
