import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'downloader.dart';
import 'paths.dart';
import 'platform.dart';

const javaRuntimeIndexUrl =
    'https://launchermeta.mojang.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json';

/// Installs Mojang's Java runtimes (the same ones the official launcher
/// uses), so players don't need Java installed.
class JavaRuntimeInstaller {
  JavaRuntimeInstaller({required this.paths, required this.downloader, HostPlatform? host})
      : host = host ?? HostPlatform.current;

  final LauncherPaths paths;
  final Downloader downloader;
  final HostPlatform host;

  /// Ensures [component] (e.g. `java-runtime-gamma`, from the version JSON's
  /// `javaVersion.component`) is installed and returns the java executable.
  Future<String> ensure(String component, {ProgressCallback? onProgress, CancelToken? cancel}) async {
    final dir = p.join(paths.runtimes, component, host.javaRuntimeKey);
    final marker = File(p.join(dir, '.installed'));
    if (await marker.exists()) {
      final exe = findJavaExecutable(dir, host);
      if (exe != null) return exe;
    }

    final index = jsonDecode(await downloader.getText(javaRuntimeIndexUrl)) as Map<String, dynamic>;
    final platform = index[host.javaRuntimeKey] as Map<String, dynamic>?;
    final entries = platform?[component] as List<dynamic>?;
    if (entries == null || entries.isEmpty) {
      throw GameException('Mojang has no $component Java runtime for ${host.javaRuntimeKey}.');
    }
    final manifestInfo = (entries.first as Map<String, dynamic>)['manifest'] as Map<String, dynamic>;
    final manifest = jsonDecode(await downloader.getText(manifestInfo['url'] as String)) as Map<String, dynamic>;
    final files = (manifest['files'] as Map<String, dynamic>).cast<String, Map<String, dynamic>>();

    final tasks = <DownloadTask>[];
    final executables = <String>[];
    final links = <String, String>{};
    for (final e in files.entries) {
      final target = p.join(dir, p.joinAll(e.key.split('/')));
      switch (e.value['type']) {
        case 'directory':
          await Directory(target).create(recursive: true);
        case 'file':
          final raw = (e.value['downloads'] as Map<String, dynamic>)['raw'] as Map<String, dynamic>;
          tasks.add(DownloadTask(
            url: raw['url'] as String,
            path: target,
            sha1: raw['sha1'] as String?,
            size: (raw['size'] as num?)?.toInt(),
          ));
          if (e.value['executable'] == true) executables.add(target);
        case 'link':
          links[target] = e.value['target'] as String;
      }
    }
    await downloader.downloadAll(tasks, onProgress: onProgress, cancel: cancel);

    if (!host.isWindows) {
      for (final f in executables) {
        await Process.run('chmod', ['+x', f]);
      }
      for (final l in links.entries) {
        final link = Link(l.key);
        if (!await link.exists()) await link.create(l.value);
      }
    }

    final exe = findJavaExecutable(dir, host);
    if (exe == null) throw GameException('Java runtime $component installed but no java executable found.');
    await marker.writeAsString(manifestInfo['sha1'] as String? ?? 'ok');
    return exe;
  }
}

/// On Windows prefer `javaw.exe`: same as java.exe but doesn't pop a console
/// window. Its stdout/stderr still reach the launcher through pipes.
String? findJavaExecutable(String runtimeDir, HostPlatform host) {
  final candidates = host.isWindows
      ? ['bin/javaw.exe', 'bin/java.exe']
      : ['jre.bundle/Contents/Home/bin/java', 'bin/java'];
  for (final c in candidates) {
    final f = File(p.join(runtimeDir, p.joinAll(c.split('/'))));
    if (f.existsSync()) return f.path;
  }
  return null;
}
