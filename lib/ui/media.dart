import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../library/packs.dart';
import 'motion.dart';
import 'palette.dart';
import 'widgets.dart';

enum MediaKind { cassette, floppy }

/// `.mark` — the pack logo, tinted to the label ink (a CSS mask in the
/// reference), or a dashed placeholder square.
class PackMarkView extends StatelessWidget {
  const PackMarkView({super.key, required this.mark, required this.color, this.size = 34});
  final PackMark mark;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (mark == PackMark.none) {
      return Opacity(
        opacity: .7,
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: DashedBorderPainter(color: color, width: 1.5, dash: 4.5, gap: 3)),
        ),
      );
    }
    return Image.asset(
      'assets/images/vatra_mark.png',
      width: size,
      height: size,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// The large glowing pack emblem on the ready screen (`.emblem`).
class PackEmblem extends StatelessWidget {
  const PackEmblem({super.key, required this.pack});
  final Pack pack;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final img = PackMarkView(mark: pack.mark, color: pal.ph, size: 132);
    return Reveal.scan(
      steps: 14,
      ms: 900,
      child: Stack(
        children: [
          // drop-shadow(0 0 10px ph/70%) drop-shadow(0 0 2px ph)
          ImageFiltered(
            imageFilter: _blur(5),
            child: PackMarkView(mark: pack.mark, color: pal.a(.7), size: 132),
          ),
          ImageFiltered(imageFilter: _blur(1), child: img),
          img,
        ],
      ),
    );
  }
}

ImageFilter _blur(double sigma) => ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal);

class _Reel extends StatelessWidget {
  const _Reel({required this.spinning});
  final bool spinning;

  @override
  Widget build(BuildContext context) => Spin(
        spinning: spinning,
        child: SizedBox.square(dimension: 24, child: CustomPaint(painter: _ReelPainter(context.pal.ph))),
      );
}

/// `border: 3px dotted` on a 24px circle.
class _ReelPainter extends CustomPainter {
  _ReelPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dots = 11;
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 1.5;
    final p = Paint()..color = color;
    for (var i = 0; i < dots; i++) {
      final a = i * 2 * math.pi / dots - math.pi / 2;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r, 1.5, p);
    }
  }

  @override
  bool shouldRepaint(_ReelPainter old) => old.color != color;
}

class _LabelText extends StatelessWidget {
  const _LabelText({required this.code, required this.title, required this.ink, this.titleSize = 19});
  final String code, title;
  final Color ink;
  final double titleSize;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(code, maxLines: 1, softWrap: false, overflow: TextOverflow.clip,
                style: mono(9, weight: FontWeight.w700, ls: .14, height: 1.2, color: ink)),
            Text(title, maxLines: 1, softWrap: false, overflow: TextOverflow.clip,
                style: vt(titleSize, height: 1, color: ink)),
          ],
        ),
      );
}

/// `.cas` — a compact cassette, 184×116.
class Cassette extends StatelessWidget {
  const Cassette({super.key, required this.pack, this.spinning = false});
  final Pack pack;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      width: 184,
      height: 116,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: kCase,
        border: Border.all(color: pal.ph, width: 2),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.fromLTRB(5, 0, 7, 0),
            decoration: BoxDecoration(color: pack.color, borderRadius: BorderRadius.circular(2)),
            child: Row(
              children: [
                PackMarkView(mark: pack.mark, color: pack.ink),
                const SizedBox(width: 7),
                _LabelText(code: '${pack.code} · SIDE A', title: pack.title, ink: pack.ink),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border.all(color: pal.a(.5)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _Reel(spinning: spinning),
                  Expanded(
                    child: Container(
                      height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.symmetric(horizontal: BorderSide(color: pal.a(.5))),
                      ),
                    ),
                  ),
                  _Reel(spinning: spinning),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.flp` — a 3.5" floppy, 108×112.
class Floppy extends StatelessWidget {
  const Floppy({super.key, required this.pack});
  final Pack pack;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      width: 108,
      height: 112,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: kCase,
        border: Border.all(color: pal.ph, width: 2),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(3),
          bottomRight: Radius.circular(3),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            alignment: Alignment.topRight,
            decoration: BoxDecoration(
              color: pal.mix(.12, kCase),
              border: Border(
                left: BorderSide(color: pal.ph, width: 2),
                right: BorderSide(color: pal.ph, width: 2),
                bottom: BorderSide(color: pal.ph, width: 2),
              ),
            ),
            child: Container(
              width: 11,
              height: 22,
              decoration: BoxDecoration(color: kCase, border: Border.all(color: pal.ph)),
            ),
          ),
          const Spacer(),
          Container(
            height: 48,
            padding: const EdgeInsets.fromLTRB(4, 5, 6, 5),
            decoration: BoxDecoration(color: pack.color, borderRadius: BorderRadius.circular(2)),
            child: Row(
              children: [
                PackMarkView(mark: pack.mark, color: pack.ink, size: 30),
                const SizedBox(width: 5),
                _LabelText(code: pack.code, title: pack.short, ink: pack.ink, titleSize: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MediaView extends StatelessWidget {
  const MediaView({super.key, required this.kind, required this.pack, this.spinning = false});
  final MediaKind kind;
  final Pack pack;
  final bool spinning;

  @override
  Widget build(BuildContext context) => switch (kind) {
        MediaKind.cassette => Cassette(pack: pack, spinning: spinning),
        MediaKind.floppy => Floppy(pack: pack),
      };
}
