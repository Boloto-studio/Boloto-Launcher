import 'package:flutter/material.dart';
import 'package:lib_boloto_launcher/helpers/shared_preferences.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSavedPrefs();
  }

  Future<void> _loadSavedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _pathController.text = prefs.getString(PrefKeys.packPath) ?? '';
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

  @override
  void dispose() {
    _pathController.dispose();
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
              icon: Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
