import 'package:flutter/widgets.dart';

import 'motion.dart';
import 'palette.dart';
import 'widgets.dart';

/// The left `<aside>` column: title row, DIR line, a list of entries and a
/// footnote pinned to the bottom behind a dashed rule.
class SideRack extends StatelessWidget {
  const SideRack({
    super.key,
    required this.title,
    required this.meta,
    required this.dir,
    required this.children,
    this.note,
    this.width = 352,
  });

  final String title;
  final String meta;
  final String dir;
  final List<Widget> children;
  final String? note;
  final double width;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      width: width,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: pal.rule))),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 40),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Reveal.type(
                          n: title.length,
                          d: .9,
                          child: Text(title, style: mono(13, weight: FontWeight.w700, ls: .14)),
                        ),
                        Reveal.type(n: meta.length, d: 1.05, child: Text(meta, style: mono(11, color: pal.dim))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Reveal.type(
                        n: dir.length,
                        s: 14,
                        d: 1.1,
                        child: Text(dir, style: mono(11, ls: .06, color: pal.dim)),
                      ),
                    ),
                  ),
                  for (final c in children) ...[const SizedBox(height: 14), c],
                  const Spacer(),
                  if (note != null) ...[
                    const SizedBox(height: 14),
                    Reveal.fade(
                      d: 2,
                      child: CustomPaint(
                        foregroundPainter: DashedBorderPainter(
                          color: pal.rule,
                          right: false,
                          bottom: false,
                          left: false,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
                          child: Text(note!, style: mono(11, height: 1.6, color: pal.dim)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dim path / channel line along the top of a CRT screen.
class ScreenTopRow extends StatelessWidget {
  const ScreenTopRow({super.key, required this.path, required this.channel});
  final String path;
  final String channel;

  @override
  Widget build(BuildContext context) {
    final style = mono(11, ls: .12, color: context.pal.dim);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Reveal.type(n: 24, s: 18, d: 1, child: Text(path, style: style)),
        Reveal.type(n: channel.length, d: 1.2, child: Text(channel, style: style)),
      ],
    );
  }
}

/// Big centered VT323 headline with a blinking-cursor subtitle
/// ("NO MEDIA / SELECT A TAPE FROM THE RACK _").
class BigMessage extends StatelessWidget {
  const BigMessage({
    super.key,
    required this.title,
    required this.titleN,
    required this.subtitle,
    required this.subtitleN,
    this.delay = 0,
  });

  final String title;
  final int titleN;
  final String subtitle;
  final int subtitleN;
  final double delay;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Reveal.type(n: titleN, s: 70, d: delay, child: Text(title, style: vt(64, height: 1))),
            const SizedBox(height: 10),
            Reveal.type(
              n: subtitleN,
              s: 30,
              d: delay + .7,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text(subtitle, style: vt(26)), BlinkCursor(style: vt(26))],
              ),
            ),
          ],
        ),
      );
}
