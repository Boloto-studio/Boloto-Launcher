import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'downloader.dart';
import 'maven.dart';
import 'paths.dart';
import 'platform.dart';
import 'rules.dart';

const versionManifestUrl = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';
const librariesBaseUrl = 'https://libraries.minecraft.net/';
const resourcesBaseUrl = 'https://resources.download.minecraft.net/';

/// One file a library entry needs on disk.
class LibraryFile {
  const LibraryFile({
    required this.path,
    this.url,
    this.sha1,
    this.size,
    this.isNative = false,
    this.onClasspath = true,
  });

  /// Maven-style relative path under `libraries/`.
  final String path;

  /// Null when the file is produced locally (e.g. by Forge's processors).
  final String? url;
  final String? sha1;
  final int? size;

  /// Holds native code (LWJGL .dll/.so/.dylib) to extract next to the game.
  final bool isNative;

  /// Goes on the Java classpath. Old-style native jars (a `natives` map) are
  /// only extracted; new-style ones (1.19+) are regular libraries too.
  final bool onClasspath;
}

/// The files for one `libraries[]` entry on this platform; empty when its
/// rules exclude this OS.
List<LibraryFile> libraryFiles(Map<String, dynamic> lib, HostPlatform host) {
  if (!rulesAllow(lib['rules'] as List<dynamic>?, host)) return const [];
  final name = lib['name'] as String;
  final artifact = MavenArtifact.parse(name);
  final downloads = lib['downloads'] as Map<String, dynamic>?;
  final out = <LibraryFile>[];

  // New-style natives (1.19+): the classifier itself says natives-<os>.
  final isNativeArtifact = artifact.classifier?.startsWith('natives-') ?? false;

  final art = downloads?['artifact'] as Map<String, dynamic>?;
  if (art != null) {
    final url = art['url'] as String?;
    out.add(LibraryFile(
      path: (art['path'] as String?) ?? artifact.path,
      url: (url == null || url.isEmpty) ? null : url,
      sha1: art['sha1'] as String?,
      size: (art['size'] as num?)?.toInt(),
      isNative: isNativeArtifact,
    ));
  } else if (downloads == null && lib['natives'] == null) {
    // Old/Forge style: just a name and maybe a repository base URL.
    final base = (lib['url'] as String?) ?? librariesBaseUrl;
    out.add(LibraryFile(
      path: artifact.path,
      url: '${base.endsWith('/') ? base : '$base/'}${artifact.path}',
      sha1: lib['checksums'] is List && (lib['checksums'] as List).isNotEmpty ? (lib['checksums'] as List).first as String : null,
      isNative: isNativeArtifact,
    ));
  }

  // Old-style natives: a `natives` map pointing at a classifier.
  final natives = lib['natives'] as Map<String, dynamic>?;
  final classifierName = (natives?[host.nativesKey] as String?)
      ?.replaceAll(r'${arch}', host.arch == 'x86' ? '32' : '64');
  if (classifierName != null) {
    final classifiers = downloads?['classifiers'] as Map<String, dynamic>?;
    final c = classifiers?[classifierName] as Map<String, dynamic>?;
    if (c != null) {
      out.add(LibraryFile(
        path: (c['path'] as String?) ?? MavenArtifact.parse('$name:$classifierName').path,
        url: c['url'] as String?,
        sha1: c['sha1'] as String?,
        size: (c['size'] as num?)?.toInt(),
        isNative: true,
        onClasspath: false,
      ));
    }
  }
  return out;
}

/// Downloads and lays out a vanilla Minecraft version.
class VanillaInstaller {
  VanillaInstaller({required this.paths, required this.downloader, HostPlatform? host})
      : host = host ?? HostPlatform.current;

  final LauncherPaths paths;
  final Downloader downloader;
  final HostPlatform host;

  /// The version JSON for [id] (e.g. `1.20.1`), cached under versions/.
  Future<Map<String, dynamic>> versionJson(String id) async {
    final file = File(paths.versionJson(id));
    if (await file.exists()) return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final manifest = jsonDecode(await downloader.getText(versionManifestUrl)) as Map<String, dynamic>;
    final entry = (manifest['versions'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((v) => v['id'] == id)
        .firstOrNull;
    if (entry == null) throw GameException('Minecraft $id does not exist.');
    await downloader.download(DownloadTask(url: entry['url'] as String, path: file.path, sha1: entry['sha1'] as String?));
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  /// Client jar + libraries for [version].
  Future<void> installGameFiles(Map<String, dynamic> version, {ProgressCallback? onProgress, CancelToken? cancel}) async {
    final id = version['id'] as String;
    final client = (version['downloads'] as Map<String, dynamic>)['client'] as Map<String, dynamic>;
    final tasks = <DownloadTask>[
      DownloadTask(
        url: client['url'] as String,
        path: paths.versionJar(id),
        sha1: client['sha1'] as String?,
        size: (client['size'] as num?)?.toInt(),
      ),
      ...libraryDownloadTasks(version['libraries'] as List<dynamic>),
    ];
    await downloader.downloadAll(tasks, onProgress: onProgress, cancel: cancel);
  }

  List<DownloadTask> libraryDownloadTasks(List<dynamic> libraries) => [
        for (final lib in libraries)
          for (final f in libraryFiles(lib as Map<String, dynamic>, host))
            if (f.url != null)
              DownloadTask(url: f.url!, path: paths.library(f.path), sha1: f.sha1, size: f.size),
      ];

  /// Unpacks native libraries into the version's natives folder.
  Future<String> extractNatives(Map<String, dynamic> version) async {
    final dir = Directory(paths.nativesDir(version['id'] as String));
    await dir.create(recursive: true);
    for (final lib in (version['libraries'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final exclude = ((lib['extract'] as Map<String, dynamic>?)?['exclude'] as List<dynamic>?)?.cast<String>() ??
          const ['META-INF/'];
      for (final f in libraryFiles(lib, host).where((f) => f.isNative)) {
        final jar = File(paths.library(f.path));
        if (!await jar.exists()) continue;
        final archive = ZipDecoder().decodeBytes(await jar.readAsBytes());
        for (final entry in archive.files) {
          if (!entry.isFile) continue;
          if (exclude.any((e) => entry.name.startsWith(e))) continue;
          if (!_isNativeFile(entry.name)) continue;
          final out = File(p.join(dir.path, p.basename(entry.name)));
          if (await out.exists() && await out.length() == entry.size) continue;
          await out.writeAsBytes(entry.content as List<int>);
        }
      }
    }
    return dir.path;
  }

  static bool _isNativeFile(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.dll') || n.endsWith('.so') || n.endsWith('.dylib') || n.endsWith('.jnilib');
  }

  /// Asset index + objects. Returns the asset index id.
  Future<String> installAssets(Map<String, dynamic> version, {ProgressCallback? onProgress, CancelToken? cancel}) async {
    final info = version['assetIndex'] as Map<String, dynamic>;
    final id = info['id'] as String;
    final indexFile = p.join(paths.assets, 'indexes', '$id.json');
    await downloader.download(DownloadTask(
      url: info['url'] as String,
      path: indexFile,
      sha1: info['sha1'] as String?,
      size: (info['size'] as num?)?.toInt(),
    ));
    final index = jsonDecode(await File(indexFile).readAsString()) as Map<String, dynamic>;
    final objects = (index['objects'] as Map<String, dynamic>).values.cast<Map<String, dynamic>>();
    final tasks = [
      for (final o in objects)
        DownloadTask(
          url: '$resourcesBaseUrl${(o['hash'] as String).substring(0, 2)}/${o['hash']}',
          path: p.join(paths.assets, 'objects', (o['hash'] as String).substring(0, 2), o['hash'] as String),
          sha1: o['hash'] as String,
          size: (o['size'] as num?)?.toInt(),
        ),
    ];
    await downloader.downloadAll(tasks, onProgress: onProgress, cancel: cancel);
    return id;
  }
}
