import 'dart:async';

import 'package:flutter/material.dart';

import '../app/settings.dart';
import '../library/library_controller.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';
import '../ui/crt.dart';
import '../ui/icons.dart';
import '../ui/motion.dart';
import '../ui/palette.dart';
import '../ui/widgets.dart';
import 'off_air_screen.dart';

enum AppScreen {
  library('Library', TermIcon.library),
  servers('Servers', TermIcon.servers),
  frogs('frogs.net', TermIcon.globe),
  settings('Settings', TermIcon.settings);

  const AppScreen(this.label, this.icon);
  final String label;
  final TermIcon icon;
}

const _logo = r''' ___  ___  _    ___ _____ ___
| _ )/ _ \| |  / _ \_   _/ _ \
| _ \ (_) | |_| (_) || || (_) |
|___/\___/|____\___/ |_| \___/''';

/// App frame: header with nav, the active screen, footer, and the CRT overlay.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  AppScreen _screen = AppScreen.library;
  final _library = LibraryController();
  late final Timer _introTimer;

  @override
  void initState() {
    super.initState();
    // Once the cold-start intro has played, later screens stagger in faster.
    _introTimer = Timer(const Duration(seconds: 3), () => Motion.delayScale = .3);
  }

  @override
  void dispose() {
    _introTimer.cancel();
    _library.dispose();
    super.dispose();
  }

  void _go(AppScreen s) {
    if (s != _screen) setState(() => _screen = s);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final settings = SettingsScope.of(context);

    final body = switch (_screen) {
      AppScreen.library => LibraryScreen(controller: _library),
      AppScreen.servers => const OffAirScreen(
          path: '/dev/net0 → servers.list',
          channel: 'CH-02 // SERVERS',
          title: 'NO CARRIER',
          subtitle: 'SERVER BROWSER COMING SOON ',
        ),
      AppScreen.frogs => const OffAirScreen(
          path: '/dev/net0 → frogs.net',
          channel: 'CH-03 // UPLINK',
          title: 'OFF AIR',
          subtitle: 'UPLINK NOT YET ESTABLISHED ',
        ),
      AppScreen.settings => const SettingsScreen(),
    };

    return Material(
      color: kBg,
      textStyle: DefaultTextStyle.of(context).style,
      child: KeyframeFlicker(
        period: const Duration(seconds: 7),
        frames: KeyframeFlicker.app,
        enabled: pal.crt,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(screen: _screen, onGo: _go),
                Expanded(child: KeyedSubtree(key: ValueKey(_screen), child: body)),
                _Footer(
                  instances: settings.instancesDirOrDefault,
                  status: _screen == AppScreen.library
                      ? ListenableBuilder(listenable: _library, builder: (_, _) => Text(_library.statusLine))
                      : Text(switch (_screen) {
                          AppScreen.settings => settings.revision == 0 ? 'CONFIG LOADED' : 'CONFIG SAVED',
                          _ => 'NO CARRIER',
                        }),
                ),
              ],
            ),
            if (pal.crt) const CrtOverlay(),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.screen, required this.onGo});
  final AppScreen screen;
  final ValueChanged<AppScreen> onGo;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.rule))),
      child: Row(
        children: [
          Pressable(
            onTap: () => onGo(AppScreen.library),
            semanticLabel: 'Boloto Launcher home',
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Reveal.scan(
                  child: Text(
                    _logo,
                    style: mono(7.5, weight: FontWeight.w700, height: 1.05, shadows: pal.glow),
                  ),
                ),
                const SizedBox(width: 14),
                Reveal.type(
                  n: 12,
                  d: .3,
                  child: Text('[ LAUNCHER ]', style: mono(11, ls: .14, color: pal.dim)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Row(
              children: [
                for (final (i, s) in AppScreen.values.indexed) ...[
                  if (i > 0) const SizedBox(width: 22),
                  Reveal.type(
                    n: s.label.length + 6,
                    d: .45 + i * .15,
                    child: NavTab(label: s.label, icon: s.icon, active: s == screen, onTap: () => onGo(s)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 24),
          Reveal.type(n: 15, d: .5, child: Text('SYS.VER: 4.2.0', style: mono(11, ls: .1, color: pal.dim))),
          const SizedBox(width: 18),
          Reveal.type(
            n: 17,
            d: .8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Led(LedState.on),
                const SizedBox(width: 6),
                Text('STATUS: ONLINE', style: mono(11, ls: .1)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Reveal.fade(
            d: 1.1,
            child: TermButton(
              label: 'Collert',
              icon: TermIcon.user,
              fontSize: 11,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              semanticLabel: 'Account: Collert',
              onTap: () {}, // account menu: not wired yet
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.instances, required this.status});
  final String instances;
  final Widget status;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final inst = 'INSTANCES: $instances';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.rule))),
      child: DefaultTextStyle.merge(
        style: mono(11, ls: .1, color: pal.dim),
        child: Row(
          children: [
            Flexible(
              child: Reveal.type(
                n: inst.length,
                s: 14,
                d: 2,
                child: Text(inst, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 24),
            Reveal.type(n: 18, s: 14, d: 2.3, child: const Text('JAVA: AUTO-MANAGED')),
            const SizedBox(width: 24),
            Reveal.type(n: 18, s: 14, d: 2.5, child: const Text('CDN: boloto.studio')),
            const Spacer(),
            Reveal.type(n: 16, d: 2.6, child: status),
          ],
        ),
      ),
    );
  }
}
