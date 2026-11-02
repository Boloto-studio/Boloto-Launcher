import 'package:flutter/material.dart';

import 'palette.dart';

/// A bordered terminal-style dialog: big title, dim blurb, body, actions.
class TermDialog extends StatelessWidget {
  const TermDialog({
    super.key,
    required this.title,
    this.blurb,
    required this.children,
    required this.actions,
    this.width = 460,
  });

  final String title;
  final String? blurb;
  final List<Widget> children;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Dialog(
      backgroundColor: kBg,
      shape: RoundedRectangleBorder(side: BorderSide(color: pal.a(.5))),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: vt(36, height: 1, color: pal.ph, shadows: pal.crtShadow)),
              if (blurb != null) ...[
                const SizedBox(height: 8),
                Text(blurb!, style: mono(12, height: 1.5, color: pal.dim)),
              ],
              const SizedBox(height: 18),
              ...children,
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 12), a],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The `.field` text input used in settings and dialogs.
class TermField extends StatelessWidget {
  const TermField({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.enabled = true,
    this.onSubmitted,
    this.fontSize = 15,
    this.letterSpacing = .12,
    this.label,
  });

  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  final double fontSize;
  final double letterSpacing;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    OutlineInputBorder border(Color c) =>
        OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: c));
    return TextField(
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      onSubmitted: onSubmitted,
      cursorColor: pal.ph,
      style: mono(fontSize, ls: letterSpacing, color: pal.ph),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: kBg,
        labelText: label,
        labelStyle: mono(12, ls: .12, color: pal.dim),
        floatingLabelStyle: mono(12, ls: .12, color: pal.ph),
        hintText: hint,
        hintStyle: mono(fontSize, ls: letterSpacing, color: pal.dim),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        enabledBorder: border(pal.a(.5)),
        disabledBorder: border(pal.a(.3)),
        focusedBorder: border(pal.ph),
      ),
    );
  }
}

/// One status line under a form: dim while busy, phosphor for errors.
class FormStatus extends StatelessWidget {
  const FormStatus({super.key, required this.busy, required this.busyText, this.error});
  final bool busy;
  final String busyText;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final text = busy ? busyText : (error == null ? '' : '> ${error!.toUpperCase()}');
    return SizedBox(
      height: 18,
      child: Text(text, style: mono(11, ls: .08, color: error == null || busy ? pal.dim : pal.ph)),
    );
  }
}

/// Opens [child] as a dialog that keeps the app's phosphor palette.
Future<T?> showTermDialog<T>(BuildContext context, Widget child) {
  return showDialog<T>(
    context: context,
    barrierColor: const Color.fromRGBO(0, 0, 0, .7),
    builder: (_) => PaletteScope(palette: context.pal, child: child),
  );
}
