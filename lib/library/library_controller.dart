import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/launcher_api.dart';
import 'packs.dart';

enum DeckPhase { empty, loading, ready, installing, running }

enum RunGlyph { none, play, stop }

enum RackState { loading, ready, error }

/// The tape deck state machine from the reference. The rack comes from the
/// website's catalog; install/run are still simulated with timers until the
/// real download + launch code is wired in.
class LibraryController extends ChangeNotifier {
  LibraryController({required this.api});

  final LauncherApi api;

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

  List<String> get runLines {
    final p = pack;
    if (p == null) return const [];
    return [
      '[launcher] starting ${p.title} (${build?.label ?? '—'})',
      '[launcher] account: ${accountName ?? 'guest'}',
      '[game] loading mods...',
      '[game] sound engine started',
      '[game] world list ready',
    ].take(_step).toList();
  }

  static const _files = [
    'mods/core.jar',
    'config/',
    'resourcepacks/',
    'assets/index.json',
    'mods/boloto-exclusive.jar',
    'options.txt',
  ];
  String get installFile => '  ↳ ${_files[(_prog ~/ 17) % _files.length]}';

  String get statusLine => switch (_phase) {
        DeckPhase.empty => 'IDLE // NO MEDIA',
        DeckPhase.loading => 'READING TAPE…',
        DeckPhase.ready => 'READY',
        DeckPhase.installing => 'DOWNLOADING $_prog%',
        DeckPhase.running => 'GAME RUNNING',
      };

  String get runLabel {
    final p = pack;
    return switch (_phase) {
      DeckPhase.running => 'Stop',
      DeckPhase.installing => 'Spooling…',
      _ => p != null && !isInstalled(p) ? 'Install & run' : 'Run',
    };
  }

  /// ■ / ▶ — drawn as icons since the mono font has no such glyphs.
  RunGlyph get runGlyph => switch (_phase) {
        DeckPhase.running => RunGlyph.stop,
        DeckPhase.installing => RunGlyph.none,
        _ => RunGlyph.play,
      };

  bool get canRun => _phase == DeckPhase.ready || _phase == DeckPhase.running;
  bool get canEject => _sel != null && _phase != DeckPhase.installing;

  void pick(Pack p) {
    if (p.disabled || p.id == _sel) return;
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
  }

  void eject() {
    _clear();
    _set(() {
      _sel = _shown = null;
      _phase = DeckPhase.empty;
      _step = _prog = 0;
    });
  }

  void run() {
    if (_phase == DeckPhase.running) {
      _set(() {
        _phase = DeckPhase.ready;
        _step = 0;
      });
      return;
    }
    if (_phase != DeckPhase.ready) return;
    final id = build?.slug;
    if (id == null) return;
    _set(() {
      _phase = DeckPhase.installing;
      _prog = _installed.contains(id) ? 70 : 0;
    });
    _timers.add(Timer.periodic(const Duration(milliseconds: 90), (t) {
      final np = (_prog + 3).clamp(0, 100);
      if (np < 100) return _set(() => _prog = np);
      t.cancel();
      _set(() {
        _prog = 100;
        _phase = DeckPhase.running;
        _installed.add(id);
        _step = 0;
      });
      for (var n = 1; n <= 5; n++) {
        _later(n * 300, () => _step = n);
      }
    }));
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
    _clear();
    super.dispose();
  }
}
