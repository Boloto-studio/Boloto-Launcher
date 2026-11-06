import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the launcher keeps things on disk.
///
/// Shared, read-mostly data (Java runtimes, Minecraft libraries, assets,
/// versions, bundled git) lives under [root]; each pack build gets its own
/// game folder under [instancesDir].
class LauncherPaths {
  LauncherPaths({required this.root, required this.instancesDir});

  /// `~/.boloto` by default, with `~/.boloto/instances` for game folders.
  /// [instancesOverride] is the user's Settings › Instances value (may use `~`).
  factory LauncherPaths.resolve({String? instancesOverride}) {
    final root = p.join(homeDir(), '.boloto');
    final override = instancesOverride?.trim() ?? '';
    return LauncherPaths(
      root: root,
      instancesDir: override.isEmpty ? p.join(root, 'instances') : expandHome(override),
    );
  }

  final String root;
  final String instancesDir;

  String get libraries => p.join(root, 'libraries');
  String get versions => p.join(root, 'versions');
  String get assets => p.join(root, 'assets');
  String get runtimes => p.join(root, 'runtime');
  String get tools => p.join(root, 'tools');
  String get cache => p.join(root, 'cache');

  String versionDir(String id) => p.join(versions, id);
  String versionJson(String id) => p.join(versionDir(id), '$id.json');
  String versionJar(String id) => p.join(versionDir(id), '$id.jar');
  String nativesDir(String id) => p.join(versionDir(id), 'natives');

  /// Library file for a Maven-style relative path (`a/b/c.jar`).
  String library(String mavenPath) => p.join(libraries, p.joinAll(mavenPath.split('/')));

  /// Game folder for one pack build, e.g. `instances/vatra-dev`.
  String instance(String buildSlug) => p.join(instancesDir, buildSlug);
}

String homeDir() =>
    Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.current.path;

String expandHome(String path) {
  if (path == '~') return homeDir();
  if (path.startsWith('~/') || path.startsWith(r'~\')) return p.join(homeDir(), path.substring(2));
  return path;
}
