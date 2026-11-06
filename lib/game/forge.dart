import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'downloader.dart';
import 'maven.dart';
import 'paths.dart';
import 'platform.dart';
import 'vanilla.dart';

const forgeMavenUrl = 'https://maven.minecraftforge.net/';

typedef LogCallback = void Function(String line);

/// Installs Forge without the official launcher or Forge's installer GUI.
///
/// Forge's installer jar contains `install_profile.json` (libraries plus a
/// list of Java "processors" that patch the Minecraft jar) and `version.json`
/// (the launch profile). We download what it lists, unpack its bundled
/// files, run the client-side processors with the downloaded Java, and
/// keep version.json for launching — the same thing Prism/MultiMC do.
class ForgeInstaller {
  ForgeInstaller({required this.paths, required this.downloader, HostPlatform? host})
      : host = host ?? HostPlatform.current;

  final LauncherPaths paths;
  final Downloader downloader;
  final HostPlatform host;

  /// `1.20.1-forge-47.3.0`, the id the installer gives the version.
  static String versionId(String mcVersion, String forgeVersion) => '$mcVersion-forge-$forgeVersion';

  /// Ensures Forge [forgeVersion] for [mcVersion] is installed and returns its
  /// version JSON (which `inheritsFrom` the vanilla one).
  Future<Map<String, dynamic>> ensure({
    required String mcVersion,
    required String forgeVersion,
    required Map<String, dynamic> vanilla,
    required String java,
    LogCallback? log,
    ProgressCallback? onProgress,
    CancelToken? cancel,
  }) async {
    final id = versionId(mcVersion, forgeVersion);
    final jsonFile = File(paths.versionJson(id));
    final marker = File(p.join(paths.versionDir(id), '.installed'));
    if (await jsonFile.exists() && await marker.exists()) {
      return jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
    }

    final full = '$mcVersion-$forgeVersion';
    final installerPath = p.join(paths.cache, 'forge-$full-installer.jar');
    log?.call('[forge] downloading installer $full');
    await downloader.download(DownloadTask(
      url: '${forgeMavenUrl}net/minecraftforge/forge/$full/forge-$full-installer.jar',
      path: installerPath,
    ));
    cancel?.throwIfCancelled();

    final installer = ZipDecoder().decodeBytes(await File(installerPath).readAsBytes());
    Map<String, dynamic> readJson(String name) {
      final f = installer.findFile(name);
      if (f == null) throw GameException('Forge installer is missing $name.');
      return jsonDecode(utf8.decode(f.content as List<int>)) as Map<String, dynamic>;
    }

    final profile = readJson('install_profile.json');
    final version = readJson(((profile['json'] as String?) ?? '/version.json').replaceFirst(RegExp('^/'), ''));

    // Bundled Maven files (Forge's own jars) go straight into libraries/.
    for (final f in installer.files) {
      if (!f.isFile || !f.name.startsWith('maven/')) continue;
      final out = File(paths.library(f.name.substring('maven/'.length)));
      if (await out.exists() && await out.length() == f.size) continue;
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>);
    }

    // Libraries for the processors and for the game.
    final vanillaInstaller = VanillaInstaller(paths: paths, downloader: downloader, host: host);
    final libs = [...(profile['libraries'] as List<dynamic>? ?? const []), ...(version['libraries'] as List<dynamic>? ?? const [])];
    log?.call('[forge] downloading ${libs.length} libraries');
    await downloader.downloadAll(vanillaInstaller.libraryDownloadTasks(libs), onProgress: onProgress, cancel: cancel);

    // Data values processors refer to as {KEY}.
    final work = Directory(p.join(paths.cache, 'forge-$full-data'));
    await work.create(recursive: true);
    final data = <String, String>{
      'SIDE': 'client',
      'MINECRAFT_JAR': paths.versionJar(mcVersion),
      'MINECRAFT_VERSION': mcVersion,
      'ROOT': paths.root,
      'INSTALLER': installerPath,
      'LIBRARY_DIR': paths.libraries,
    };
    for (final e in (profile['data'] as Map<String, dynamic>? ?? const {}).entries) {
      final value = (e.value as Map<String, dynamic>)['client'] as String?;
      if (value == null) continue;
      data[e.key] = await _resolveDataValue(value, installer, work.path);
    }

    final processors = (profile['processors'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final clientProcessors =
        processors.where((pr) => (pr['sides'] as List<dynamic>?)?.contains('client') ?? true).toList();
    for (final (i, proc) in clientProcessors.indexed) {
      cancel?.throwIfCancelled();
      await _runProcessor(proc, data, java, log: log, step: '${i + 1}/${clientProcessors.length}');
    }

    await jsonFile.parent.create(recursive: true);
    await jsonFile.writeAsString(const JsonEncoder.withIndent('  ').convert(version));
    await marker.writeAsString(full);
    log?.call('[forge] installed $id');
    return version;
  }

  /// `[group:artifact:version]` → library path, `'literal'` → literal,
  /// `/path/in/installer` → extracted file, anything else → as-is.
  Future<String> _resolveDataValue(String value, Archive installer, String workDir) async {
    if (value.startsWith('[') && value.endsWith(']')) {
      return paths.library(MavenArtifact.parse(value.substring(1, value.length - 1)).path);
    }
    if (value.startsWith("'") && value.endsWith("'")) return value.substring(1, value.length - 1);
    if (value.startsWith('/')) {
      final entry = installer.findFile(value.substring(1));
      if (entry == null) throw GameException('Forge installer is missing $value.');
      final out = File(p.join(workDir, p.joinAll(value.substring(1).split('/'))));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(entry.content as List<int>);
      return out.path;
    }
    return value;
  }

  /// Replaces `{KEY}` with data values and `[maven:coord]` with library paths.
  String resolveArg(String arg, Map<String, String> data) {
    if (arg.startsWith('[') && arg.endsWith(']')) {
      return paths.library(MavenArtifact.parse(arg.substring(1, arg.length - 1)).path);
    }
    return arg.replaceAllMapped(RegExp(r'\{([A-Z_]+)\}'), (m) {
      final v = data[m[1]];
      if (v == null) throw GameException('Forge processor needs unknown value {${m[1]}}.');
      return v;
    });
  }

  Future<void> _runProcessor(
    Map<String, dynamic> proc,
    Map<String, String> data,
    String java, {
    LogCallback? log,
    required String step,
  }) async {
    final jar = paths.library(MavenArtifact.parse(proc['jar'] as String).path);
    final classpath = [
      jar,
      for (final c in (proc['classpath'] as List<dynamic>? ?? const [])) paths.library(MavenArtifact.parse(c as String).path),
    ];
    final mainClass = await jarMainClass(jar);
    if (mainClass == null) throw GameException('Forge processor $jar has no Main-Class.');
    final args = [for (final a in (proc['args'] as List<dynamic>? ?? const [])) resolveArg(a as String, data)];

    log?.call('[forge] processor $step: ${proc['jar']}');
    final process = await Process.start(java, ['-cp', classpath.join(host.classpathSeparator), mainClass, ...args]);
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => log?.call('[forge] $l'));
    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => log?.call('[forge] $l'));
    final code = await process.exitCode;
    if (code != 0) throw GameException('Forge install step failed (${proc['jar']}, exit code $code).');
  }
}

/// `Main-Class` from a jar's manifest.
Future<String?> jarMainClass(String jarPath) async {
  final archive = ZipDecoder().decodeBytes(await File(jarPath).readAsBytes());
  final manifest = archive.findFile('META-INF/MANIFEST.MF');
  if (manifest == null) return null;
  for (final line in const LineSplitter().convert(utf8.decode(manifest.content as List<int>))) {
    if (line.startsWith('Main-Class:')) return line.substring('Main-Class:'.length).trim();
  }
  return null;
}
