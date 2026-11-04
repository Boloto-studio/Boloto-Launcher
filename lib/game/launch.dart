import 'dart:io';

import 'maven.dart';
import 'paths.dart';
import 'platform.dart';
import 'rules.dart';
import 'vanilla.dart';

/// Who the game runs as — from the Microsoft/Minecraft sign-in.
class LaunchSession {
  const LaunchSession({
    required this.username,
    required this.uuid,
    required this.accessToken,
    this.xuid = '',
    this.userType = 'msa',
  });

  final String username;
  final String uuid;
  final String accessToken;
  final String xuid;
  final String userType;
}

/// Everything needed to start the game process.
class LaunchCommand {
  const LaunchCommand({required this.executable, required this.arguments, required this.workingDirectory});
  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  /// Same command with the access token blanked, safe to show in logs.
  String describe(String accessToken) =>
      [executable, ...arguments].map((a) => a.replaceAll(accessToken, '<token>')).join(' ');
}

/// Mojang's recommended G1 flags (what the official launcher passes).
const defaultJvmFlags = [
  '-XX:+UnlockExperimentalVMOptions',
  '-XX:+UseG1GC',
  '-XX:G1NewSizePercent=20',
  '-XX:G1ReservePercent=20',
  '-XX:MaxGCPauseMillis=50',
  '-XX:G1HeapRegionSize=32M',
];

/// Builds the `java …` command for a vanilla version, optionally with a
/// mod loader version (Forge) layered on top of it.
class LaunchBuilder {
  LaunchBuilder({required this.paths, HostPlatform? host}) : host = host ?? HostPlatform.current;

  final LauncherPaths paths;
  final HostPlatform host;

  static const launcherName = 'boloto-launcher';
  static const launcherVersion = '1.0';

  /// Libraries in launch order, child (Forge) first; the first occurrence of
  /// a `group:artifact[:classifier]` wins so Forge's newer versions are used.
  List<String> classpathLibraries(List<Map<String, dynamic>> versionsChildFirst) {
    final seen = <String>{};
    final out = <String>[];
    for (final v in versionsChildFirst) {
      for (final lib in (v['libraries'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>()) {
        final key = MavenArtifact.parse(lib['name'] as String).key;
        if (!seen.add(key)) continue;
        for (final f in libraryFiles(lib, host)) {
          if (f.onClasspath) out.add(paths.library(f.path));
        }
      }
    }
    return out;
  }

  /// The jar for the launched version. For an inherited version (Forge) this
  /// is a copy of the vanilla jar under the child's id, like the official
  /// launcher does; Forge's `-DignoreList=…${version_name}.jar` expects it.
  Future<String> versionJar({required String vanillaId, required String launchId}) async {
    final jar = paths.versionJar(launchId);
    if (launchId != vanillaId && !await File(jar).exists()) {
      await File(jar).parent.create(recursive: true);
      await File(paths.versionJar(vanillaId)).copy(jar);
    }
    return jar;
  }

  Future<LaunchCommand> build({
    required String java,
    required Map<String, dynamic> vanilla,
    Map<String, dynamic>? loader,
    required LaunchSession session,
    required String gameDir,
    required String nativesDir,
    required String assetIndex,
    required int memoryGb,
    String? clientId,
  }) async {
    final chain = [if (loader != null) loader, vanilla];
    final vanillaId = vanilla['id'] as String;
    final launchId = (loader?['id'] as String?) ?? vanillaId;
    final mainClass = (loader?['mainClass'] as String?) ?? vanilla['mainClass'] as String;

    final classpath = [
      ...classpathLibraries(chain),
      await versionJar(vanillaId: vanillaId, launchId: launchId),
    ];

    final values = <String, String>{
      'auth_player_name': session.username,
      'auth_uuid': session.uuid,
      'auth_access_token': session.accessToken,
      'auth_xuid': session.xuid,
      'auth_session': session.accessToken,
      'user_type': session.userType,
      'user_properties': '{}',
      'clientid': clientId ?? '',
      'version_name': launchId,
      'version_type': (vanilla['type'] as String?) ?? 'release',
      'game_directory': gameDir,
      'assets_root': paths.assets,
      'game_assets': paths.assets,
      'assets_index_name': assetIndex,
      'natives_directory': nativesDir,
      'library_directory': paths.libraries,
      'classpath_separator': host.classpathSeparator,
      'classpath': classpath.join(host.classpathSeparator),
      'launcher_name': launcherName,
      'launcher_version': launcherVersion,
    };

    final jvm = <String>[];
    final game = <String>[];
    // Parent (vanilla) arguments first, then the loader's additions.
    for (final v in chain.reversed) {
      final args = v['arguments'] as Map<String, dynamic>?;
      if (args != null) {
        jvm.addAll(flattenArguments(args['jvm'] as List<dynamic>?, host));
        game.addAll(flattenArguments(args['game'] as List<dynamic>?, host));
      } else if (v['minecraftArguments'] is String) {
        // Pre-1.13 style; kept so older packs still start.
        game.addAll((v['minecraftArguments'] as String).split(' ').where((a) => a.isNotEmpty));
        if (jvm.isEmpty) jvm.addAll([r'-Djava.library.path=${natives_directory}', '-cp', r'${classpath}']);
      }
    }

    return LaunchCommand(
      executable: java,
      workingDirectory: gameDir,
      arguments: [
        '-Xmx${memoryGb}G',
        '-Xms1G',
        ...defaultJvmFlags,
        for (final a in jvm) substitute(a, values),
        mainClass,
        for (final a in game) substitute(a, values),
      ],
    );
  }
}
