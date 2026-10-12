import 'package:flutter/material.dart';

import '../app/settings.dart';
import '../ui/crt.dart';
import '../ui/icons.dart';
import '../ui/layout.dart';
import '../ui/media.dart';
import '../ui/motion.dart';
import '../ui/palette.dart';
import '../ui/widgets.dart';
import 'library_controller.dart';
import 'packs.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.controller});
  final LibraryController controller;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _channel = '[LATEST]';

  @override
  Widget build(BuildContext context) {
    final media = SettingsScope.of(context).media;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SideRack(
              title: '/tapes',
              meta: '${packs.length} ON RACK',
              dir: 'DIR: /usr/local/boloto/library',
              note: 'Tapes are pulled from the Boloto CDN, so mods that live nowhere else ship with the pack.',
              children: [
                for (final (i, p) in packs.indexed) _TapeTile(pack: p, index: i, controller: c, media: media),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: CrtPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ScreenTopRow(
                              path: c.pack == null ? '/dev/tape0 → —' : '/dev/tape0 → ${c.pack!.code.toLowerCase()}.boloto',
                              channel: 'CH-01 // CLASSIFIED',
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: KeyedSubtree(
                                key: ValueKey((c.phase, c.pack?.id)),
                                child: _screenFor(c),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _Deck(
                      controller: c,
                      media: media,
                      channel: _channel,
                      onChannel: (v) => setState(() => _channel = v),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _screenFor(LibraryController c) => switch (c.phase) {
        DeckPhase.empty => const BigMessage(
            title: 'NO MEDIA',
            titleN: 8,
            subtitle: 'SELECT A TAPE FROM THE RACK ',
            subtitleN: 29,
            delay: 1.3,
          ),
        DeckPhase.loading => _Console(lines: c.bootLines, size: 24, stepMs: 7),
        DeckPhase.ready => _Ready(pack: c.pack!),
        DeckPhase.installing => _Installing(controller: c),
        DeckPhase.running => _Console(lines: c.runLines, size: 22, stepMs: 9),
      };
}

class _TapeTile extends StatelessWidget {
  const _TapeTile({required this.pack, required this.index, required this.controller, required this.media});
  final Pack pack;
  final int index;
  final LibraryController controller;
  final MediaKind media;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final sel = controller.isSelected(pack);
    final base = 1.2 + index * .25;
    final install = pack.disabled
        ? 'EMPTY'
        : sel
            ? 'IN DECK'
            : controller.isInstalled(pack)
                ? 'INSTALLED'
                : 'NOT INSTALLED';
    return SelectFrame(
      selected: sel,
      onTap: pack.disabled ? null : () => controller.pick(pack),
      semanticLabel: '${pack.title}, $install',
      child: Row(
        children: [
          Reveal.fade(
            d: base,
            child: Opacity(
              opacity: sel ? .22 : (pack.disabled ? .45 : 1),
              child: MediaView(kind: media, pack: pack),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Reveal.type(
                  n: pack.title.length,
                  d: base,
                  child: Text(pack.title, style: mono(13, weight: FontWeight.w700, ls: .06)),
                ),
                const SizedBox(height: 6),
                Reveal.type(
                  n: pack.status.length,
                  s: 16,
                  d: base + .25,
                  child: Text(pack.status, style: mono(11, color: pal.dim)),
                ),
                const SizedBox(height: 6),
                Reveal.fade(d: base + .5, child: TagChip(install)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Boot / game log: lines type in one by one, then a blinking cursor.
class _Console extends StatelessWidget {
  const _Console({required this.lines, required this.size, required this.stepMs});
  final List<String> lines;
  final double size;
  final double stepMs;

  @override
  Widget build(BuildContext context) {
    final style = vt(size);
    return ClipRect(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, l) in lines.indexed) ...[
            Reveal.type(key: ValueKey(i), n: l.length, s: stepMs, child: Text(l, style: style)),
            const SizedBox(height: 6),
          ],
          BlinkCursor(style: style),
        ],
      ),
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({required this.pack});
  final Pack pack;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (pack.hasLogo) ...[PackEmblem(pack: pack), const SizedBox(width: 22)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Reveal.type(
                    n: 28,
                    s: 14,
                    child: Text('${pack.code} · ${pack.status}', style: mono(11, ls: .14, color: pal.dim)),
                  ),
                  const SizedBox(height: 10),
                  Reveal.type(
                    n: pack.title.length,
                    s: 55,
                    d: .2,
                    child: Text(pack.title, style: vt(76, height: .9)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Reveal.fade(
          d: .6,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Text(pack.tag, style: mono(14, height: 1.55)),
          ),
        ),
        const SizedBox(height: 18),
        Table(
          children: [
            TableRow(children: [_stat(pal, 'MINECRAFT', pack.mc), _stat(pal, 'LOADER', pack.loader)]),
            const TableRow(children: [SizedBox(height: 8), SizedBox(height: 8)]),
            TableRow(children: [_stat(pal, 'MODS', pack.mods), _stat(pal, 'DOWNLOAD', pack.size)]),
          ],
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomPaint(
          foregroundPainter: DashedBorderPainter(color: pal.rule),
          child: SizedBox(
            height: 170,
            child: Center(child: Text('[ TRAILER / SCREENSHOT ]', style: mono(12, ls: .12, color: pal.dim))),
          ),
        ),
        const SizedBox(height: 12),
        const Caption('TRACK LIST'),
        for (final (i, f) in pack.feats.indexed) ...[
          const SizedBox(height: 12),
          Text('${(i + 1).toString().padLeft(2, '0')}  $f', style: mono(13)),
        ],
      ],
    );

    return ScrollConfiguration(
      behavior: const ScrollBehavior().copyWith(scrollbars: false),
      child: SingleChildScrollView(
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth < 600
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 28), right])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 300, child: left),
                    const SizedBox(width: 28),
                    Expanded(flex: 260, child: right),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _stat(Palette pal, String k, String v) => Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: mono(12, color: pal.dim)),
            Text(v, style: mono(12)),
          ],
        ),
      );
}

class _Installing extends StatelessWidget {
  const _Installing({required this.controller});
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final n = (controller.progress / 100 * 32).round();
    final bar = '#' * n + '.' * (32 - n);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('> SPOOLING ${controller.pack!.title} TO DISK', style: vt(26)),
        const SizedBox(height: 12),
        Text('[$bar] ${controller.progress}%', style: vt(26), softWrap: false),
        const SizedBox(height: 12),
        Text(controller.installFile, style: vt(20, color: context.pal.dim)),
      ],
    );
  }
}

/// `DECK A // TAPE TRANSPORT` — slot, LEDs and transport controls.
class _Deck extends StatelessWidget {
  const _Deck({required this.controller, required this.media, required this.channel, required this.onChannel});
  final LibraryController controller;
  final MediaKind media;
  final String channel;
  final ValueChanged<String> onChannel;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = controller;

    final slot = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Reveal.type(n: 24, s: 18, d: 1.4, child: const Caption('DECK A // TAPE TRANSPORT', size: 10, ls: .16)),
        const SizedBox(height: 8),
        Container(
          width: 260,
          height: 136,
          decoration: BoxDecoration(border: Border.all(color: pal.a(.45), width: 2)),
          child: CustomPaint(
            painter: const InsetShadowPainter(
              fill: kTube,
              radius: 0,
              color: Color.fromRGBO(0, 0, 0, .9),
              blur: 18,
              offset: Offset(0, 10),
            ),
            child: ClipRect(
              child: Center(
                child: c.showDeckTape
                    ? InsertIn(
                        key: ValueKey(c.pack!.id),
                        child: MediaView(kind: media, pack: c.pack!, spinning: c.reelsSpinning),
                      )
                    : c.pack == null
                        ? Reveal.type(n: 16, d: 1.8, child: const Caption('— SLOT EMPTY —', ls: .16))
                        : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );

    Widget led(LedState s, String label, int n, double d) => Reveal.type(
          n: n,
          d: d,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Led(s), const SizedBox(width: 8), Text(label, style: mono(11, ls: .12))],
          ),
        );
    final leds = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        led(LedState.on, 'POWER', 7, 1.6),
        const SizedBox(height: 10),
        led(
          c.phase == DeckPhase.loading || c.phase == DeckPhase.installing
              ? LedState.busy
              : (c.pack != null ? LedState.on : LedState.off),
          'READ',
          6,
          1.75,
        ),
        const SizedBox(height: 10),
        led(c.phase == DeckPhase.running ? LedState.on : LedState.off, 'PLAY', 6, 1.9),
      ],
    );

    final controls = Reveal.fade(
      d: 1.7,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Caption('BUILD', ls: .12),
          const SizedBox(width: 12),
          TermSelect(value: channel, options: const ['[LATEST]', '[PREVIOUS]'], onChanged: onChannel, label: 'Build'),
          const SizedBox(width: 12),
          TermButton(
            label: 'Eject',
            icon: TermIcon.eject,
            onTap: c.canEject ? c.eject : null,
            semanticLabel: 'Eject tape',
          ),
          const SizedBox(width: 12),
          RunButton(
            label: c.runLabel,
            icon: switch (c.runGlyph) {
              RunGlyph.play => TermIcon.play,
              RunGlyph.stop => TermIcon.stop,
              RunGlyph.none => null,
            },
            onTap: c.canRun ? c.run : null,
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(border: Border.all(color: pal.rule)),
      child: LayoutBuilder(
        builder: (context, box) {
          final top = Row(
            mainAxisSize: MainAxisSize.min,
            children: [slot, const SizedBox(width: 20), leds],
          );
          if (box.maxWidth >= 880) {
            return Row(children: [top, const Spacer(), controls]);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [top, const SizedBox(height: 16), controls],
          );
        },
      ),
    );
  }
}
