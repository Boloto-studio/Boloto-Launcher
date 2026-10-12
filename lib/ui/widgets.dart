import 'package:flutter/material.dart';

import 'icons.dart';
import 'motion.dart';
import 'palette.dart';

/// Hover / focus / press plumbing for every clickable thing. Keyboard
/// activation (Enter/Space) works through [ActivateIntent].
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.onTap, required this.builder, this.semanticLabel});

  /// Null means disabled (CSS `cursor: not-allowed`).
  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool hot) builder;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap?.call();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: widget.builder(context, enabled && (_hover || _focus)),
        ),
      ),
    );
  }
}

/// `.btn`
class TermButton extends StatelessWidget {
  const TermButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.semanticLabel,
  });

  final String label;
  final TermIcon? icon;
  final VoidCallback? onTap;
  final double fontSize;
  final EdgeInsets padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder: (context, hot) => Opacity(
        opacity: onTap == null ? .35 : 1,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: padding,
          decoration: BoxDecoration(
            color: hot ? pal.a(.12) : null,
            border: Border.all(color: pal.a(.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                TermIconView(icon!, size: fontSize > 12 ? 16 : 14, color: pal.ph),
                const SizedBox(width: 8),
              ],
              Text(label.toUpperCase(), style: mono(fontSize, ls: .08, color: pal.ph)),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.btn.btn-run` — the big filled primary action.
class RunButton extends StatelessWidget {
  const RunButton({super.key, required this.label, this.icon, this.onTap});
  final String label;
  final TermIcon? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final enabled = onTap != null;
    return Pressable(
      onTap: onTap,
      builder: (context, hot) => Opacity(
        opacity: enabled ? 1 : .35,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: !enabled ? null : (hot ? pal.mix(.82, kWhite) : pal.ph),
            border: Border.all(color: pal.ph),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                TermIconView(icon!, size: 13, color: enabled ? kBg : pal.ph),
                const SizedBox(width: 10),
              ],
              Text(
                label.toUpperCase(),
                style: mono(15, weight: FontWeight.w700, ls: .08, color: enabled ? kBg : pal.ph, shadows: const []),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.nav` — header tab with an underline when active.
class NavTab extends StatelessWidget {
  const NavTab({super.key, required this.label, required this.icon, required this.active, required this.onTap});
  final String label;
  final TermIcon icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Pressable(
      onTap: onTap,
      builder: (context, hot) {
        final c = active || hot ? pal.ph : pal.dim;
        return Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: active ? pal.ph : const Color(0x00000000), width: 2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TermIconView(icon, color: c),
              const SizedBox(width: 8),
              Text(label.toUpperCase(), style: mono(13, ls: .1, color: c)),
            ],
          ),
        );
      },
    );
  }
}

/// `.chip`
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: pal.a(.45))),
      child: Text(label, style: mono(11, ls: .12)),
    );
  }
}

enum LedState { off, on, busy }

/// `.led`
class Led extends StatelessWidget {
  const Led(this.state, {super.key});
  final LedState state;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    Widget dot(Color c, {bool glow = false}) => Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c,
            boxShadow: glow ? [BoxShadow(color: c, blurRadius: 10)] : null,
          ),
        );
    return switch (state) {
      LedState.off => dot(pal.mix(.18, kBg)),
      LedState.on => dot(pal.ph, glow: true),
      LedState.busy => Blink(period: const Duration(milliseconds: 400), child: dot(kAmber, glow: true)),
    };
  }
}

/// A dashed rectangle border (CSS `border: 1px dashed`). Set [sides] to draw
/// only some edges.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    this.width = 1,
    this.dash = 3,
    this.gap = 3,
    this.top = true,
    this.right = true,
    this.bottom = true,
    this.left = true,
  });

  final Color color;
  final double width, dash, gap;
  final bool top, right, bottom, left;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final p = Paint()
      ..color = color
      ..strokeWidth = width;
    final h = width / 2;
    void run(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (double d = 0; d < len; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * (d + dash).clamp(0, len), p);
      }
    }

    if (top) run(Offset(0, h), Offset(size.width, h));
    if (bottom) run(Offset(0, size.height - h), Offset(size.width, size.height - h));
    if (left) run(Offset(h, 0), Offset(h, size.height));
    if (right) run(Offset(size.width - h, 0), Offset(size.width - h, size.height));
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color || old.width != width || old.top != top || old.bottom != bottom;
}

/// A selectable row with the `.tape-btn` treatment: dashed outline on hover,
/// solid outline + faint fill when selected.
class SelectFrame extends StatelessWidget {
  const SelectFrame({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.semanticLabel,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final EdgeInsets padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder: (context, hot) => CustomPaint(
        foregroundPainter: selected ? null : DashedBorderPainter(color: hot ? pal.a(.45) : const Color(0x00000000)),
        child: Container(
          padding: padding,
          decoration: selected
              ? BoxDecoration(color: pal.a(.07), border: Border.all(color: pal.ph))
              : BoxDecoration(border: Border.all(color: const Color(0x00000000))),
          child: child,
        ),
      ),
    );
  }
}

/// `.field` dropdown. Opens a bordered popup menu under the field.
class TermSelect extends StatelessWidget {
  const TermSelect({super.key, required this.value, required this.options, required this.onChanged, this.label});
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String? label;

  Future<void> _open(BuildContext context) async {
    final pal = context.pal;
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset(0, box.size.height - 1), ancestor: overlay);
    final picked = await showMenu<String>(
      context: context,
      color: kBg,
      elevation: 0,
      menuPadding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: box.size.width, maxWidth: box.size.width),
      shape: RoundedRectangleBorder(side: BorderSide(color: pal.a(.5))),
      position: RelativeRect.fromRect(topLeft & box.size, Offset.zero & overlay.size),
      items: [
        for (final o in options)
          PopupMenuItem(
            value: o,
            height: 40,
            child: Text(
              o,
              style: mono(13, ls: .06, color: o == value ? pal.ph : pal.dim, shadows: pal.crtShadow),
            ),
          ),
      ],
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Builder(
      builder: (context) => Pressable(
        onTap: () => _open(context),
        semanticLabel: label,
        builder: (context, hot) => Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.only(left: 12, right: 8),
          decoration: BoxDecoration(
            color: hot ? Color.alphaBlend(pal.a(.08), kBg) : kBg,
            border: Border.all(color: pal.a(.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value.toUpperCase(), style: mono(13, ls: .06)),
              const SizedBox(width: 10),
              TermIconView(TermIcon.chevron, size: 14, color: pal.ph),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dim, letter-spaced caption (the many 10–11px uppercase labels).
class Caption extends StatelessWidget {
  const Caption(this.text, {super.key, this.size = 11, this.ls = .14, this.dim = true});
  final String text;
  final double size;
  final double ls;
  final bool dim;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: mono(size, ls: ls, color: dim ? context.pal.dim : null));
}
