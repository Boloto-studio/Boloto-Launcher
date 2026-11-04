import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../library/packs.dart';
import 'downloader.dart';
import 'forge.dart';
import 'java_runtime.dart';
import 'launch.dart';
import 'pack_sync.dart';
import 'paths.dart';
import 'platform.dart';
import 'vanilla.dart';

/// Where an install is, for the progress bar.
class InstallProgress {
  const InstallProgress(this.stage, this.fraction);

  /// Short label, e.g. `ASSETS`.
  final String stage;

  /// Overall progress, 0..1.
  final double fraction;
}

/// A started game.
class RunningGame {
  RunningGame({required this.exitCode, required void Function() stop}) : _stop = stop;

  RunningGame.fromProcess(Process process) : this(exitCode: process.exitCode, stop: () => process.kill());

  final Future<int> exitCode;
  final void Function() _stop;

  void stop() => _stop();
}

/// Installs and launches pack builds. The UI only talks to this, so tests can
/// swap in a fake.
abstract class GameService {
  /// Whether the build's game folder has been set up before.
  Future<bool> isInstalled(PackBuild build);

  /// Downloads/updates everything for [build] and starts the game.
  Future<RunningGame> launch(
    PackBuild build, {
    required LaunchSession session,
    required int memoryGb,
    required void Function(InstallProgress) onProgress,
    required LogCallback log,
    CancelToken? cancel,
  });
}

/// The real thing: Mojang + Forge + git, no official launcher involved.
class BolotoGameService implements GameService {
  BolotoGameService({required this.pathsFor, http.Client? client, HostPlatform? host})
      : host = host ?? HostPlatform.current,
        _downloader = Downloader(client: client);

  /// Resolved per launch so a changed Settings › Instances path applies.
  final LauncherPaths Function() pathsFor;
  final HostPlatform host;
  final Downloader _downloader;

  @override
  Future<bool> isInstalled(PackBuild build) async {
    final paths = pathsFor();
    return PackSync(paths: paths, downloader: _downloader, host: host).isCloned(paths.instance(build.slug));
  }

  // Share of the overall bar each step takes.
  static const _steps = [
    ('JAVA', 0.12),
    ('MINECRAFT', 0.12),
    ('ASSETS', 0.22),
    ('FORGE', 0.20),
    ('PACK FILES', 0.30),
    ('LAUNCH', 0.04),
  ];

  @override
  Future<RunningGame> launch(
    PackBuild build, {
    required LaunchSession session,
    required int memoryGb,
    required void Function(InstallProgress) onProgress,
    required LogCallback log,
    CancelToken? cancel,
  }) async {
    final paths = pathsFor();
    final mc = build.minecraftVersion.trim();
    if (mc.isEmpty) throw const GameException('This build has no Minecraft version set on the website.');
    final loader = build.modLoader.trim().toLowerCase();
    if (loader.isNotEmpty && loader != 'forge') {
      throw GameException('${build.modLoader} packs aren\'t supported yet (only Forge).');
    }
    if (loader == 'forge' && build.loaderVersion.trim().isEmpty) {
      throw const GameException('This build is missing its Forge version on the website.');
    }

    var stepIndex = 0;
    void report(int done, int total) {
      final before = _steps.take(stepIndex).fold<double>(0, (a, s) => a + s.$2);
      final share = _steps[stepIndex].$2 * (total == 0 ? 1 : done / total);
      onProgress(InstallProgress(_steps[stepIndex].$1, (before + share).clamp(0.0, 1.0).toDouble()));
    }

    void step(int i) {
      stepIndex = i;
      report(0, 1);
    }

    final vanillaInstaller = VanillaInstaller(paths: paths, downloader: _downloader, host: host);

    // 1. Minecraft version info, so we know which Java it wants.
    log('[launcher] preparing ${build.label} — Minecraft $mc${loader == 'forge' ? ' + Forge ${build.loaderVersion}' : ''}');
    final vanilla = await vanillaInstaller.versionJson(mc);

    // 2. Java
    step(0);
    final component = ((vanilla['javaVersion'] as Map<String, dynamic>?)?['component'] as String?) ?? 'java-runtime-gamma';
    log('[java] $component');
    final java = await JavaRuntimeInstaller(paths: paths, downloader: _downloader, host: host)
        .ensure(component, onProgress: report, cancel: cancel);

    // 3. Minecraft client + libraries
    step(1);
    log('[minecraft] client and libraries');
    await vanillaInstaller.installGameFiles(vanilla, onProgress: report, cancel: cancel);
    final natives = await vanillaInstaller.extractNatives(vanilla);

    // 4. Assets
    step(2);
    log('[minecraft] assets');
    final assetIndex = await vanillaInstaller.installAssets(vanilla, onProgress: report, cancel: cancel);

    // 5. Forge
    step(3);
    Map<String, dynamic>? forge;
    if (loader == 'forge') {
      forge = await ForgeInstaller(paths: paths, downloader: _downloader, host: host).ensure(
        mcVersion: mc,
        forgeVersion: build.loaderVersion.trim(),
        vanilla: vanilla,
        java: java,
        log: log,
        onProgress: report,
        cancel: cancel,
      );
    }

    // 6. Pack files from git
    step(4);
    final gameDir = paths.instance(build.slug);
    if (build.gitUrl.trim().isEmpty) {
      log('[pack] no git repository set for this build; launching an empty game folder');
      await Directory(gameDir).create(recursive: true);
    } else {
      final sync = PackSync(paths: paths, downloader: _downloader, host: host);
      final git = await sync.ensureGit(log: log, cancel: cancel);
      await sync.sync(
        git: git,
        url: build.gitUrl.trim(),
        branch: build.gitBranch.trim().isEmpty ? 'main' : build.gitBranch.trim(),
        dir: gameDir,
        log: log,
        cancel: cancel,
      );
    }

    // 7. Launch
    step(5);
    cancel?.throwIfCancelled();
    final command = await LaunchBuilder(paths: paths, host: host).build(
      java: java,
      vanilla: vanilla,
      loader: forge,
      session: session,
      gameDir: gameDir,
      nativesDir: natives,
      assetIndex: assetIndex,
      memoryGb: memoryGb,
    );
    log('[launcher] ${command.describe(session.accessToken)}');
    final process = await Process.start(command.executable, command.arguments, workingDirectory: command.workingDirectory);
    process.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(log);
    process.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(log);
    report(1, 1);
    log('[launcher] game started (pid ${process.pid})');
    return RunningGame.fromProcess(process);
  }
}
