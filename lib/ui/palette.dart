import 'package:flutter/widgets.dart';

/// Fixed (non-phosphor) colors from the design.
const kBg = Color(0xFF050806);
const kCase = Color(0xFF0B130D);
const kTube = Color(0xFF020402);
const kAmber = Color(0xFFFFB000);
const kWhite = Color(0xFFFFFFFF);

const kPlex = 'IBMPlexMono';
const kVt = 'VT323';

/// Everything that tints with the phosphor color. Mirrors the CSS
/// `color-mix(in srgb, var(--ph) X%, …)` expressions in the reference.
@immutable
class Palette {
  const Palette(this.ph, {this.crt = true});

  final Color ph;
  final bool crt;

  /// `color-mix(in srgb, ph pct, transparent)`
  Color a(double pct) => ph.withValues(alpha: pct);

  /// `color-mix(in srgb, ph pct, other)`
  Color mix(double pct, Color other) => Color.lerp(other, ph, pct)!;

  Color get dim => mix(.62, kBg);
  Color get rule => a(.35);

  /// `.glow` text-shadow: 0 0 8px ph/55%.
  List<Shadow> get glow => [Shadow(color: a(.55), blurRadius: 6)];

  /// `.app.crt-on` text-shadow: 0 0 4px ph/30%.
  List<Shadow> get crtShadow => crt ? [Shadow(color: a(.30), blurRadius: 3)] : const [];

  @override
  bool operator ==(Object other) => other is Palette && other.ph == ph && other.crt == crt;

  @override
  int get hashCode => Object.hash(ph, crt);
}

class PaletteScope extends InheritedWidget {
  const PaletteScope({super.key, required this.palette, required super.child});

  final Palette palette;

  static Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaletteScope>()!.palette;

  @override
  bool updateShouldNotify(PaletteScope oldWidget) => oldWidget.palette != palette;
}

extension PaletteContext on BuildContext {
  Palette get pal => PaletteScope.of(this);
}

/// IBM Plex Mono at [size] px. [ls] is letter-spacing in em, like the CSS.
TextStyle mono(
  double size, {
  FontWeight? weight,
  double ls = 0,
  Color? color,
  double? height,
  List<Shadow>? shadows,
}) =>
    TextStyle(
      fontFamily: kPlex,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: ls * size,
      color: color,
      height: height,
      shadows: shadows,
    );

/// VT323 at [size] px.
TextStyle vt(double size, {Color? color, double? height, List<Shadow>? shadows}) =>
    TextStyle(
      fontFamily: kVt,
      fontFamilyFallback: const [kPlex],
      fontSize: size,
      color: color,
      height: height,
      shadows: shadows,
    );
