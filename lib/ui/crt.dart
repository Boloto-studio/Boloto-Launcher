import 'package:flutter/widgets.dart';

import 'motion.dart';
import 'palette.dart';

/// Horizontal scanlines. [period] px per line; the dark band sits at the end
/// of each period, matching the `repeating-linear-gradient`s in the CSS.
class ScanlinePainter extends CustomPainter {
  const ScanlinePainter({required this.period, required this.alpha, this.thickness = 1});
  final double period;
  final double alpha;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var y = period - thickness; y < size.height; y += period) {
      path.addRect(Rect.fromLTWH(0, y, size.width, thickness));
    }
    canvas.drawPath(path, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
  }

  @override
  bool shouldRepaint(ScanlinePainter old) => old.period != period || old.alpha != alpha || old.thickness != thickness;
}

/// Stretches a circular [RadialGradient] into an ellipse that fills its box,
/// i.e. CSS `radial-gradient(ellipse at center, …)` (farthest-corner).
class _EllipseFill extends GradientTransform {
  const _EllipseFill();
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final s = bounds.shortestSide;
    final c = bounds.center;
    return Matrix4.identity()
      ..translate(c.dx, c.dy)
      ..scale(bounds.width / s, bounds.height / s)
      ..translate(-c.dx, -c.dy);
  }
}

BoxDecoration vignette(double from, double alpha) => BoxDecoration(
      gradient: RadialGradient(
        radius: .7072,
        transform: const _EllipseFill(),
        colors: [const Color(0x00000000), Color.fromRGBO(0, 0, 0, alpha)],
        stops: [from, 1],
      ),
    );

/// The full-window `.crt-overlay`: scanlines, a slow rolling bright band and
/// an edge vignette. Pointer-transparent.
class CrtOverlay extends StatefulWidget {
  const CrtOverlay({super.key});

  @override
  State<CrtOverlay> createState() => _CrtOverlayState();
}

class _CrtOverlayState extends State<CrtOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _roll =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: CustomPaint(painter: ScanlinePainter(period: 4, alpha: .12, thickness: 2)),
          ),
          RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, box) => AnimatedBuilder(
                animation: _roll,
                builder: (context, child) => Transform.translate(
                  // translateY(-140px) → translateY(1100px) on an 820px canvas;
                  // scale the travel to the real window height.
                  offset: Offset(0, -140 + _roll.value * (box.maxHeight + 280)),
                  child: child,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [const Color(0x00FFFFFF), pal.a(.06), const Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          DecoratedBox(decoration: vignette(.65, .45)),
        ],
      ),
    );
  }
}

/// Paints a background fill plus a CSS-style `inset` box-shadow.
class InsetShadowPainter extends CustomPainter {
  const InsetShadowPainter({
    required this.fill,
    required this.radius,
    required this.color,
    required this.blur,
    this.offset = Offset.zero,
  });
  final Color fill;
  final double radius;
  final Color color;
  final double blur;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(blur * 2 + offset.distance))
      ..addRRect(rrect.shift(offset));
    canvas.drawPath(
      ring,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(InsetShadowPainter old) =>
      old.fill != fill || old.radius != radius || old.color != color || old.blur != blur || old.offset != offset;
}

/// The rounded "tube" screen (`.crt`). Its own scanlines sit under the
/// content and the vignette sits over it, as in the CSS stacking order.
class CrtPanel extends StatelessWidget {
  const CrtPanel({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(30, 26, 30, 26)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    const r = 18.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        boxShadow: [
          BoxShadow(color: pal.a(.28), spreadRadius: 2),
          BoxShadow(color: pal.a(.10), blurRadius: 40),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const RepaintBoundary(
              child: CustomPaint(
                painter: InsetShadowPainter(fill: kTube, radius: r, color: Color.fromRGBO(0, 0, 0, .95), blur: 90),
              ),
            ),
            const RepaintBoundary(
              child: CustomPaint(painter: ScanlinePainter(period: 3, alpha: .16)),
            ),
            KeyframeFlicker(
              period: const Duration(seconds: 5),
              frames: KeyframeFlicker.panel,
              enabled: pal.crt,
              child: DefaultTextStyle.merge(
                style: TextStyle(shadows: pal.glow),
                child: Padding(padding: padding, child: child),
              ),
            ),
            IgnorePointer(child: DecoratedBox(decoration: vignette(.62, .55))),
          ],
        ),
      ),
    );
  }
}
