import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/launcher_api.dart';
import '../game/downloader.dart' show CancelToken, GameException;
import '../game/game_service.dart';
import '../minecraft/microsoft_auth.dart' show MinecraftAuthException;
import '../minecraft/minecraft_account.dart';
import 'packs.dart';

/// `stopped`: the game exited, crashed or failed to install; the log stays up.
enum DeckPhase { empty, loading, ready, installing, running, stopped }

enum RunGlyph { none, play, stop }

enum RackState { loading, ready, error }

/// The tape deck state machine from the reference. The rack comes from the
/// website's catalog; Run installs the selected build (Java, Minecraft,
/// Forge, pack files) and starts the game, streaming everything to [log].
class LibraryController extends ChangeNotifier {
  LibraryController({required this.api, required this.game, required this.minecraft, required this.memoryGb});

  final LauncherApi api;
  final GameService game;
  final MinecraftAccountController minecraft;

  /// Settings › Memory, read at launch.
  final int Function() memoryGb;

  /// Install + game output for the current run (capped).
  final List<String> _log = [];
  static const _maxLog = 5000;
  Timer? _logFlush;
  String _stage = '';
  String _exitNote = '';
  RunningGame? _running;
  CancelToken? _cancel;

  String? _sel;
  String? _shown;
  DeckPhase _phase = DeckPhase.empty;
  int _step = 0;
  int _prog = 0;
  final Set<String> _installed = {};
  final List<Timer> _timers = [];

  /// Website account signed in on this launcher, for the run log.
  String? accountName;

  List<Pack> _packs = const [];
  RackState _rack = RackState.loading;
  String _rackError = '';
  final Map<String, String> _buildSel = {};
  bool _disposed = false;

  /// Packs from the server, in the server's order.
  List<Pack> get packs => _packs;
  RackState get rackState => _rack;
  String get rackError => _rackError;

  /// Reloads the rack from the website. Keeps the current list on failure.
  Future<void> refresh() async {
    _set(() {
      _rack = RackState.loading;
      _rackError = '';
    });
    try {
      final fetched = await api.fetchCatalog();
      if (_disposed) return;
      _set(() {
        _packs = fetched;
        _rack = RackState.ready;
      });
      if (_sel != null && !_packs.any((p) => p.id == _sel)) eject();
    } on ApiException catch (e) {
      if (_disposed) return;
      _set(() {
        _rack = RackState.error;
        _rackError = e.message;
      });
    }
  }

  /// Redeems a game key, puts the unlocked pack on the rack and loads the
  /// unlocked build into the deck. Throws [ApiException] on failure.
  Future<RedeemResult> redeem(String code) async {
    final result = await api.redeemKey(code);
    if (_disposed) return result;
    final i = _packs.indexWhere((p) => p.id == result.pack.id);
    _set(() {
      _packs = i < 0 ? [..._packs, result.pack] : [..._packs.sublist(0, i), result.pack, ..._packs.sublist(i + 1)];
      _rack = RackState.ready;
      _buildSel[result.pack.id] = result.buildSlug;
    });
    if (_phase != DeckPhase.installing && _phase != DeckPhase.running) {
      if (_sel == result.pack.id) {
        // Same tape already in the deck; just switch builds.
        notifyListeners();
      } else {
        pick(result.pack);
      }
    }
    return result;
  }

  /// The build the deck will install/run for [p].
  PackBuild? buildOf(Pack p) => p.buildFor(_buildSel[p.id]);
  PackBuild? get build => pack == null ? null : buildOf(pack!);

  void selectBuild(PackBuild b) {
    final p = pack;
    if (p == null || _phase == DeckPhase.installing || _phase == DeckPhase.running) return;
    _set(() => _buildSel[p.id] = b.slug);
    _checkInstalled(p);
  }

  bool get canSelectBuild =>
      pack != null && pack!.builds.length > 1 && _phase != DeckPhase.installing && _phase != DeckPhase.running;

  DeckPhase get phase => _phase;
  int get step => _step;
  int get progress => _prog;
  Pack? get pack {
    for (final p in _packs) {
      if (p.id == _sel) return p;
    }
    return null;
  }
  bool isSelected(Pack p) => p.id == _sel;
  bool isInstalled(Pack p) => _installed.contains(buildOf(p)?.slug);

  /// The tape appears in the slot a beat after selection so it can drop in.
  bool get showDeckTape => _sel != null && _shown == _sel;

  bool get reelsSpinning =>
      _phase == DeckPhase.loading || _phase == DeckPhase.installing || _phase == DeckPhase.running;

  List<String> get bootLines {
    final p = pack;
    if (p == null) return const [];
    return [
      '> MOUNT /dev/tape0 .......... OK',
      '> READING HEADER: ${p.code} [${build?.label ?? '—'}]',
      '> VERIFYING MANIFEST ........ OK',
      '> SYNC ${_shortRepo(build?.gitUrl)}@${build?.gitBranch ?? '—'} ... ${isInstalled(p) ? 'CACHED' : 'PENDING'}',
      '> JAVA RUNTIME .............. OK',
      '> BOOT COMPLETE',
    ].take(_step).toList();
  }

  /// Lines for the deck's log screen.
  List<String> get log => _log;

  /// Current install step, e.g. `ASSETS`.
  String get stage => _stage;

  void _appendLog(String line) {
    if (_disposed) return;
    _log.add(line);
    if (_log.length > _maxLog) _log.removeRange(0, _log.length - _maxLog);
    // Games log thousands of lines; repaint at most ~10 times a second.
    _logFlush ??= Timer(const Duration(milliseconds: 100), () {
      _logFlush = null;
      if (!_disposed) notifyListeners();
    });
  }

  String get statusLine => switch (_phase) {
        DeckPhase.empty => 'IDLE // NO MEDIA',
        DeckPhase.loading => 'READING TAPE…',
        DeckPhase.ready => 'READY',
        DeckPhase.installing => '$_stage $_prog%',
        DeckPhase.running => 'GAME RUNNING',
        DeckPhase.stopped => _exitNote,
      };

  String get runLabel {
    final p = pack;
    return switch (_phase) {
      DeckPhase.running => 'Stop',
      DeckPhase.installing => 'Cancel',
      _ => p != null && !isInstalled(p) ? 'Install & run' : 'Run',
    };
  }

  /// ■ / ▶ — drawn as icons since the mono font has no such glyphs.
  RunGlyph get runGlyph => switch (_phase) {
        DeckPhase.running || DeckPhase.installing => RunGlyph.stop,
        _ => RunGlyph.play,
      };

  /// Busy = installing or playing; the deck is locked to this tape.
  bool get busy => _phase == DeckPhase.installing || _phase == DeckPhase.running;

  bool get canRun => _phase == DeckPhase.ready || _phase == DeckPhase.stopped || busy;
  bool get canEject => _sel != null && !busy;

  /// Whether Run will start (and so needs a Minecraft account) rather than
  /// stop/cancel.
  bool get runStarts => _phase == DeckPhase.ready || _phase == DeckPhase.stopped;

  void pick(Pack p) {
    if (p.disabled || p.id == _sel || busy) return;
    _clear();
    _set(() {
      _sel = p.id;
      _shown = null;
      _phase = DeckPhase.loading;
      _step = 0;
      _prog = 0;
    });
    _later(60, () => _shown = p.id);
    for (var n = 1; n <= 6; n++) {
      _later(420 + n * 240, () => _step = n);
    }
    _later(420 + 7 * 240 + 200, () => _phase = DeckPhase.ready);
    _checkInstalled(p);
  }

  Future<void> _checkInstalled(Pack p) async {
    final b = buildOf(p);
    if (b == null) return;
    try {
      if (await game.isInstalled(b)) _set(() => _installed.add(b.slug));
    } catch (_) {
      // Unreadable folder etc.: treat as not installed.
    }
  }

  void eject() {
    if (busy) return;
    _clear();
    _set(() {
      _sel = _shown = null;
      _phase = DeckPhase.empty;
      _step = _prog = 0;
    });
  }

  /// Run / Stop / Cancel, depending on the phase.
  Future<void> run() async {
    if (_phase == DeckPhase.running) {
      _appendLog('> stopping the game…');
      _running?.stop();
      return;
    }
    if (_phase == DeckPhase.installing) {
      _appendLog('> cancelling…');
      _cancel?.cancel();
      return;
    }
    if (!runStarts) return;
    final b = build;
    if (b == null) return;

    final cancel = CancelToken();
    _cancel = cancel;
    _log.clear();
    _set(() {
      _phase = DeckPhase.installing;
      _prog = 0;
      _stage = 'STARTING';
    });

    try {
      final session = await minecraft.session();
      _appendLog('[launcher] playing as ${session.username}${accountName == null ? '' : ' (boloto.studio: $accountName)'}');
      final running = await game.launch(
        b,
        session: session,
        memoryGb: memoryGb(),
        cancel: cancel,
        log: _appendLog,
        onProgress: (p) => _set(() {
          _prog = (p.fraction * 100).round();
          _stage = p.stage;
        }),
      );
      _running = running;
      _set(() {
        _installed.add(b.slug);
        _phase = DeckPhase.running;
      });
      final code = await running.exitCode;
      _running = null;
      _appendLog('> game exited (code $code)');
      _set(() {
        _phase = DeckPhase.stopped;
        _exitNote = code == 0 ? 'GAME CLOSED' : 'GAME CRASHED (EXIT $code)';
      });
    } on GameException catch (e) {
      _fail(e.message);
    } on MinecraftAuthException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('$e');
    } finally {
      _cancel = null;
    }
  }

  void _fail(String message) {
    _appendLog('> ERROR: $message');
    _set(() {
      _phase = DeckPhase.stopped;
      _exitNote = message == 'Cancelled.' ? 'CANCELLED' : 'FAILED';
    });
  }

  void _later(int ms, VoidCallback fn) => _timers.add(Timer(Duration(milliseconds: ms), () => _set(fn)));

  void _set(VoidCallback fn) {
    if (_disposed) return;
    fn();
    notifyListeners();
  }

  static String _shortRepo(String? url) {
    if (url == null || url.isEmpty) return '—';
    final parts = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const [];
    return parts.isEmpty ? url : parts.last.replaceAll(RegExp(r'\.git$'), '');
  }

  void _clear() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _logFlush?.cancel();
    _cancel?.cancel();
    _clear();
    super.dispose();
  }
}
