import 'dart:async';

import 'package:flutter/widgets.dart';

/// Global motion knobs.
class Motion {
  /// Entrance delays are written for a cold start (the reference staggers
  /// things in over ~2.5s). After the first screen has played we shrink them
  /// so switching tabs doesn't feel sluggish.
  static double delayScale = 1.0;
}

Duration _ms(num ms) => Duration(microseconds: (ms * 1000).round());

enum RevealKind { wipeX, wipeY, fade }

/// One-shot entrance animation. Plays once when mounted, holding the hidden
/// state through the delay (CSS `animation-fill-mode: both`).
class Reveal extends StatefulWidget {
  const Reveal._({
    super.key,
    required this.child,
    required this.kind,
    required this.duration,
    required this.delay,
    this.steps = 0,
    this.curve = Curves.linear,
  });

  /// `.tw` / `.tw-flex` — typewriter wipe, left to right in [n] steps of [s] ms.
  factory Reveal.type({Key? key, required Widget child, required int n, double s = 24, double d = 0}) =>
      Reveal._(key: key, kind: RevealKind.wipeX, steps: n, duration: _ms(n * s), delay: _ms(d * 1000), child: child);

  /// `.scan` — top-to-bottom wipe in 4 steps over .4s.
  factory Reveal.scan({Key? key, required Widget child, double d = 0, int steps = 4, double ms = 400}) =>
      Reveal._(key: key, kind: RevealKind.wipeY, steps: steps, duration: _ms(ms), delay: _ms(d * 1000), child: child);

  /// `.fade` — .5s ease-out opacity.
  factory Reveal.fade({Key? key, required Widget child, double d = 0}) => Reveal._(
      key: key,
      kind: RevealKind.fade,
      curve: Curves.easeOut,
      duration: _ms(500),
      delay: _ms(d * 1000),
      child: child);

  final Widget child;
  final RevealKind kind;
  final Duration duration;
  final Duration delay;
  final int steps;
  final Curve curve;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final delay = widget.delay * Motion.delayScale;
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(delay, _c.forward);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  double get _progress {
    final v = _c.value;
    if (widget.steps <= 0) return widget.curve.transform(v);
    if (v >= 1) return 1;
    return (v * widget.steps).floor() / widget.steps;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kind == RevealKind.fade) {
      return FadeTransition(opacity: _c.drive(CurveTween(curve: widget.curve)), child: widget.child);
    }
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ClipRect(
        // Keep the tree shape stable once done so children keep their state.
        clipBehavior: _c.isCompleted ? Clip.none : Clip.hardEdge,
        clipper: _WipeClipper(_progress, widget.kind == RevealKind.wipeX ? Axis.horizontal : Axis.vertical),
        child: child,
      ),
    );
  }
}

class _WipeClipper extends CustomClipper<Rect> {
  _WipeClipper(this.p, this.axis);
  final double p;
  final Axis axis;

  // Pad generously on the unclipped sides so text glow isn't shaved off.
  @override
  Rect getClip(Size size) => axis == Axis.horizontal
      ? Rect.fromLTRB(-60, -60, size.width * p, size.height + 60)
      : Rect.fromLTRB(-60, -60, size.width + 60, size.height * p);

  @override
  bool shouldReclip(_WipeClipper old) => old.p != p || old.axis != axis;
}

/// A looping opacity animation defined by CSS-style keyframes
/// (offset in 0..1 → opacity). Used for the CRT flicker.
class KeyframeFlicker extends StatefulWidget {
  const KeyframeFlicker({super.key, required this.period, required this.frames, required this.enabled, required this.child});

  final Duration period;
  final List<(double, double)> frames;
  final bool enabled;
  final Widget child;

  static const app = [
    (0.0, 1.0), (.61, 1.0), (.614, .9), (.618, 1.0), (.623, .95), (.627, 1.0), //
    (.88, 1.0), (.883, .96), (.886, 1.0), (1.0, 1.0),
  ];
  static const panel = [(0.0, 1.0), (.48, 1.0), (.50, .94), (.52, 1.0), (1.0, 1.0)];

  @override
  State<KeyframeFlicker> createState() => _KeyframeFlickerState();
}

class _KeyframeFlickerState extends State<KeyframeFlicker> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(KeyframeFlicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.enabled && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.enabled && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _c.drive(_KeyframeTween(widget.frames)), child: widget.child);
}

class _KeyframeTween extends Animatable<double> {
  _KeyframeTween(this.frames);
  final List<(double, double)> frames;

  @override
  double transform(double t) {
    for (var i = 1; i < frames.length; i++) {
      final (t1, v1) = frames[i];
      if (t <= t1) {
        final (t0, v0) = frames[i - 1];
        final span = t1 - t0;
        return span <= 0 ? v1 : v0 + (v1 - v0) * ((t - t0) / span);
      }
    }
    return frames.last.$2;
  }
}

/// `.cursor::after` — a blinking underscore.
class BlinkCursor extends StatefulWidget {
  const BlinkCursor({super.key, this.style, this.period = const Duration(seconds: 1)});
  final TextStyle? style;
  final Duration period;

  @override
  State<BlinkCursor> createState() => _BlinkCursorState();
}

class _BlinkCursorState extends State<BlinkCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Opacity(opacity: _c.value < .5 ? 1 : 0, child: child),
        child: Text('_', style: widget.style),
      );
}

/// Steps(1) on/off blink for arbitrary children (the amber "busy" LED).
class Blink extends StatefulWidget {
  const Blink({super.key, required this.period, required this.child});
  final Duration period;
  final Widget child;

  @override
  State<Blink> createState() => _BlinkState();
}

class _BlinkState extends State<Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Opacity(opacity: _c.value < .5 ? 1 : 0, child: child),
        child: widget.child,
      );
}

/// Continuous rotation while [spinning]; snaps back to 0 when stopped,
/// like removing a CSS animation.
class Spin extends StatefulWidget {
  const Spin({super.key, required this.spinning, required this.child, this.period = const Duration(milliseconds: 1100)});
  final bool spinning;
  final Duration period;
  final Widget child;

  @override
  State<Spin> createState() => _SpinState();
}

class _SpinState extends State<Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _c.repeat();
  }

  @override
  void didUpdateWidget(Spin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_c.isAnimating) _c.repeat();
    if (!widget.spinning && _c.isAnimating) _c.reset();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _c, child: widget.child);
}

/// `.insert` — media drops into the slot from above with a slight overshoot.
class InsertIn extends StatefulWidget {
  const InsertIn({super.key, required this.child});
  final Widget child;

  @override
  State<InsertIn> createState() => _InsertInState();
}

class _InsertInState extends State<InsertIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SlideTransition(
        position: _c.drive(CurveTween(curve: const Cubic(.2, .9, .25, 1.15)))
            .drive(Tween(begin: const Offset(0, -1.3), end: Offset.zero)),
        child: widget.child,
      );
}
