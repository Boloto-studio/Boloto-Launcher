import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'downloader.dart';
import 'forge.dart' show LogCallback;
import 'paths.dart';
import 'platform.dart';

/// Portable Git for Windows + Git LFS, used when git isn't installed.
/// Pinned by SHA-256 so a tampered download is refused.
const _minGit = (
  url: 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/MinGit-2.47.1-64-bit.zip',
  sha256: '50b04b55425b5c465d076cdb184f63a0cd0f86f6ec8bb4d5860114a713d2c29a',
  dir: 'mingit-2.47.1',
);
const _gitLfs = (
  url: 'https://github.com/git-lfs/git-lfs/releases/download/v3.6.0/git-lfs-windows-amd64-v3.6.0.zip',
  sha256: '62fce4cfd453493966c387db167ba1aa46ecee730ae24a5b902a1d05650fb4ce',
  dir: 'git-lfs-3.6.0',
);

/// A git executable plus the environment to run it with.
class GitTools {
  const GitTools(this.git, [this.environment = const {}]);
  final String git;
  final Map<String, String> environment;
}

/// Runs a command and streams its output; throws on a non-zero exit.
typedef CommandRunner = Future<void> Function(
  String executable,
  List<String> args, {
  required String workingDirectory,
  Map<String, String> environment,
  LogCallback? log,
});

Future<void> runCommand(
  String executable,
  List<String> args, {
  required String workingDirectory,
  Map<String, String> environment = const {},
  LogCallback? log,
}) async {
  final process = await Process.start(
    executable,
    args,
    workingDirectory: workingDirectory,
    environment: {
      ...environment,
      // Never block waiting for a password prompt nobody can see.
      'GIT_TERMINAL_PROMPT': '0',
      'GCM_INTERACTIVE': 'never',
    },
  );
  final out = process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => log?.call(l));
  final err = process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => log?.call(l));
  final code = await process.exitCode;
  await out.cancel();
  await err.cancel();
  if (code != 0) {
    throw GameException('`${p.basenameWithoutExtension(executable)} ${args.first}` failed (exit code $code).');
  }
}

/// Keeps a pack build's game folder in sync with its git branch.
///
/// Players only ever get the latest commit (`--depth 1`), and the folder is
/// reset to exactly match the branch. Files the repo doesn't track (worlds,
/// options.txt, screenshots…) are left alone. Big files come through Git
/// LFS from wherever the repo's .lfsconfig points (git.boloto.studio).
class PackSync {
  PackSync({required this.paths, required this.downloader, HostPlatform? host, CommandRunner? run})
      : host = host ?? HostPlatform.current,
        _run = run ?? runCommand;

  final LauncherPaths paths;
  final Downloader downloader;
  final HostPlatform host;
  final CommandRunner _run;

  /// System git when it has LFS; otherwise (Windows) a downloaded MinGit.
  Future<GitTools> ensureGit({LogCallback? log, CancelToken? cancel}) async {
    if (await _works('git', ['--version']) && await _works('git', ['lfs', 'version'])) {
      return const GitTools('git');
    }
    if (!host.isWindows) {
      throw const GameException('Install git and git-lfs to download packs (e.g. `sudo apt install git git-lfs`).');
    }
    final gitDir = p.join(paths.tools, _minGit.dir);
    final lfsDir = p.join(paths.tools, _gitLfs.dir);
    if (!File(p.join(gitDir, 'cmd', 'git.exe')).existsSync()) {
      log?.call('[git] downloading portable Git');
      await _installZip(_minGit.url, _minGit.sha256, gitDir, cancel: cancel);
    }
    if (!File(p.join(lfsDir, 'git-lfs.exe')).existsSync()) {
      log?.call('[git] downloading Git LFS');
      await _installZip(_gitLfs.url, _gitLfs.sha256, lfsDir, stripTopFolder: true, cancel: cancel);
    }
    final path = [lfsDir, p.join(gitDir, 'cmd'), p.join(gitDir, 'mingw64', 'bin'), Platform.environment['PATH'] ?? '']
        .join(';');
    return GitTools(p.join(gitDir, 'cmd', 'git.exe'), {'PATH': path});
  }

  Future<bool> _works(String exe, List<String> args) async {
    try {
      return (await Process.run(exe, args)).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  Future<void> _installZip(String url, String sha256, String dest, {bool stripTopFolder = false, CancelToken? cancel}) async {
    final zip = p.join(paths.cache, p.basename(url));
    await downloader.download(DownloadTask(url: url, path: zip), cancel: cancel);
    if (await sha256OfFile(zip) != sha256) {
      await File(zip).delete();
      throw GameException('Downloaded ${p.basename(url)} failed its checksum; not using it.');
    }
    final archive = ZipDecoder().decodeBytes(await File(zip).readAsBytes());
    for (final f in archive.files) {
      if (!f.isFile) continue;
      var name = f.name;
      if (stripTopFolder) {
        final slash = name.indexOf('/');
        if (slash < 0) continue;
        name = name.substring(slash + 1);
      }
      final out = File(p.join(dest, p.joinAll(name.split('/'))));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>);
    }
  }

  /// Whether [dir] has been synced before.
  bool isCloned(String dir) => Directory(p.join(dir, '.git')).existsSync();

  /// Makes [dir] match `origin/<branch>` of [url].
  Future<void> sync({
    required GitTools git,
    required String url,
    required String branch,
    required String dir,
    LogCallback? log,
    CancelToken? cancel,
  }) async {
    await Directory(dir).create(recursive: true);
    Future<void> g(List<String> args, {Map<String, String> env = const {}}) async {
      cancel?.throwIfCancelled();
      log?.call('> git ${args.join(' ')}');
      await _run(git.git, args, workingDirectory: dir, environment: {...git.environment, ...env}, log: log);
    }

    if (!isCloned(dir)) {
      await g(['init', '--quiet']);
      await g(['remote', 'add', 'origin', url]);
    } else {
      await g(['remote', 'set-url', 'origin', url]);
    }
    if (host.isWindows) await g(['config', 'core.longpaths', 'true']);
    await g(['lfs', 'install', '--local']);
    await g(['fetch', '--depth', '1', '--no-tags', 'origin', branch]);
    // Check out without LFS first, then pull LFS files with progress output.
    await g(['reset', '--hard', 'FETCH_HEAD'], env: {'GIT_LFS_SKIP_SMUDGE': '1'});
    await g(['lfs', 'pull']);
    await installDefaults(dir, log: log);
  }

  /// `options.default.txt` → `options.txt` (and servers) only if missing, so
  /// updates never reset a player's keybinds or server list.
  Future<void> installDefaults(String dir, {LogCallback? log}) async {
    for (final (src, dst) in [('options.default.txt', 'options.txt'), ('servers.default.dat', 'servers.dat')]) {
      final from = File(p.join(dir, src));
      final to = File(p.join(dir, dst));
      if (await from.exists() && !await to.exists()) {
        await from.copy(to.path);
        log?.call('[pack] installed default $dst');
      }
    }
  }
}
