import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/shared_preferences.dart';
import '../ui/media.dart';

/// A selectable phosphor color for the whole UI.
class Phosphor {
  const Phosphor(this.id, this.label, this.color);
  final String id;
  final String label;
  final Color color;

  static const green = Phosphor('green', 'P1 GREEN', Color(0xFF39FF6A));
  static const amber = Phosphor('amber', 'P3 AMBER', Color(0xFFFFB000));
  static const cyan = Phosphor('cyan', 'P7 CYAN', Color(0xFF7FE7FF));
  static const all = [green, amber, cyan];

  static Phosphor byId(String? id) => all.firstWhere((p) => p.id == id, orElse: () => green);
}

const ramOptions = [4, 6, 8, 12, 16];
const defaultInstancesDir = '~/.boloto/instances';

/// User-facing launcher preferences. Every setter writes through to disk
/// immediately, so there is no "save" step.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static const _kPhosphor = 'ui.phosphor';
  static const _kMedia = 'ui.media';
  static const _kCrt = 'ui.crt';
  static const _kRam = 'launcher.ramGb';

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async => AppSettings._(await SharedPreferences.getInstance());

  Phosphor get phosphor => Phosphor.byId(_prefs.getString(_kPhosphor));
  set phosphor(Phosphor v) => _write(() => _prefs.setString(_kPhosphor, v.id));

  MediaKind get media => _prefs.getString(_kMedia) == 'floppy' ? MediaKind.floppy : MediaKind.cassette;
  set media(MediaKind v) => _write(() => _prefs.setString(_kMedia, v.name));

  bool get crt => _prefs.getBool(_kCrt) ?? true;
  set crt(bool v) => _write(() => _prefs.setBool(_kCrt, v));

  /// Shares the key the download/version helpers already read.
  String get instancesDir => _prefs.getString(PrefKeys.packPath) ?? '';
  set instancesDir(String v) => _write(() => _prefs.setString(PrefKeys.packPath, v.trim()));
  String get instancesDirOrDefault => instancesDir.isEmpty ? defaultInstancesDir : instancesDir;

  int get ramGb => _prefs.getInt(_kRam) ?? 6;
  set ramGb(int v) => _write(() => _prefs.setInt(_kRam, v));

  /// Bumped on every write so screens can flash a "saved" status.
  int get revision => _revision;
  int _revision = 0;

  void resetDefaults() => _write(() async {
        for (final k in [_kPhosphor, _kMedia, _kCrt, _kRam, PrefKeys.packPath]) {
          await _prefs.remove(k);
        }
        return true;
      });

  // SharedPreferences updates its in-memory cache synchronously, so the
  // getters see the new value right away; the disk write finishes behind.
  void _write(Future<bool> Function() op) {
    op();
    _revision++;
    notifyListeners();
  }
}

class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({super.key, required AppSettings settings, required super.child}) : super(notifier: settings);

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}
