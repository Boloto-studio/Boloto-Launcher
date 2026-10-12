import 'package:flutter/widgets.dart';

/// The line icons from the reference, ported from their 24×24 SVG paths
/// (`fill="none" stroke="currentColor" stroke-width="2"`).
enum TermIcon { library, servers, globe, settings, user, eject, chevron, play, stop }

class TermIconView extends StatelessWidget {
  const TermIconView(this.icon, {super.key, this.size = 16, required this.color});
  final TermIcon icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _IconPainter(icon, color)));
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color);
  final TermIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    void circle(double x, double y, double r) => canvas.drawCircle(Offset(x, y), r, p);
    void line(double x1, double y1, double x2, double y2) => canvas.drawLine(Offset(x1, y1), Offset(x2, y2), p);

    switch (icon) {
      case TermIcon.library:
        canvas.drawRRect(RRect.fromLTRBR(3, 6, 21, 18, const Radius.circular(1)), p);
        circle(8.5, 12, 2);
        circle(15.5, 12, 2);
      case TermIcon.servers:
        canvas.drawRect(const Rect.fromLTWH(3, 4, 18, 7), p);
        canvas.drawRect(const Rect.fromLTWH(3, 13, 18, 7), p);
      case TermIcon.globe:
        circle(12, 12, 9);
        line(3, 12, 21, 12);
        canvas.drawPath(
          Path()
            ..moveTo(12, 3)
            ..cubicTo(15, 6, 15, 18, 12, 21)
            ..moveTo(12, 3)
            ..cubicTo(9, 6, 9, 18, 12, 21),
          p,
        );
      case TermIcon.settings:
        line(4, 6, 14, 6);
        line(18, 6, 20, 6);
        line(4, 12, 8, 12);
        line(12, 12, 20, 12);
        line(4, 18, 16, 18);
        circle(16, 6, 2);
        circle(10, 12, 2);
        circle(18, 18, 2);
      case TermIcon.user:
        circle(12, 8, 4);
        canvas.drawPath(
          Path()
            ..moveTo(4, 21)
            ..cubicTo(5.5, 17, 8.5, 15, 12, 15)
            ..cubicTo(15.5, 15, 18.5, 17, 20, 21),
          p,
        );
      case TermIcon.eject:
        canvas.drawPath(
          Path()
            ..moveTo(5, 14)
            ..lineTo(12, 6)
            ..lineTo(19, 14)
            ..close(),
          p,
        );
        line(5, 18, 19, 18);
      case TermIcon.play:
        canvas.drawPath(
          Path()
            ..moveTo(6, 4)
            ..lineTo(20, 12)
            ..lineTo(6, 20)
            ..close(),
          p..style = PaintingStyle.fill,
        );
      case TermIcon.stop:
        canvas.drawRect(const Rect.fromLTWH(5, 5, 14, 14), p..style = PaintingStyle.fill);
      case TermIcon.chevron:
        canvas.drawPath(
          Path()
            ..moveTo(6, 9)
            ..lineTo(12, 15)
            ..lineTo(18, 9),
          p,
        );
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.icon != icon || old.color != color;
}
