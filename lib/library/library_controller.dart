import 'dart:async';

import 'package:flutter/foundation.dart';

import 'packs.dart';

enum DeckPhase { empty, loading, ready, installing, running }

enum RunGlyph { none, play, stop }

/// The tape deck state machine from the reference. Install/run are simulated
/// with timers until the real download + launch code is wired in.
class LibraryController extends ChangeNotifier {
  String? _sel;
  String? _shown;
  DeckPhase _phase = DeckPhase.empty;
  int _step = 0;
  int _prog = 0;
  final Set<String> _installed = {'swamp'};
  final List<Timer> _timers = [];

  DeckPhase get phase => _phase;
  int get step => _step;
  int get progress => _prog;
  Pack? get pack => _sel == null ? null : packs.firstWhere((p) => p.id == _sel);
  bool isSelected(Pack p) => p.id == _sel;
  bool isInstalled(Pack p) => _installed.contains(p.id);

  /// The tape appears in the slot a beat after selection so it can drop in.
  bool get showDeckTape => _sel != null && _shown == _sel;

  bool get reelsSpinning =>
      _phase == DeckPhase.loading || _phase == DeckPhase.installing || _phase == DeckPhase.running;

  List<String> get bootLines {
    final p = pack;
    if (p == null) return const [];
    return [
      '> MOUNT /dev/tape0 .......... OK',
      '> READING HEADER: ${p.code}',
      '> VERIFYING MANIFEST ........ OK',
      '> SYNCING MODS FROM CDN ..... ${isInstalled(p) ? 'CACHED' : 'PENDING'}',
      '> JAVA RUNTIME .............. OK',
      '> BOOT COMPLETE',
    ].take(_step).toList();
  }

  List<String> get runLines {
    final p = pack;
    if (p == null) return const [];
    return [
      '[launcher] starting ${p.title}',
      '[launcher] session: Collert (Microsoft)',
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
    final id = _sel!;
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
    fn();
    notifyListeners();
  }

  void _clear() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }
}
