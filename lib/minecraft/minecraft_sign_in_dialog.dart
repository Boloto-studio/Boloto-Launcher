import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/dialog.dart';
import '../ui/icons.dart';
import '../ui/palette.dart';
import '../ui/widgets.dart';
import 'microsoft_auth.dart';
import 'minecraft_account.dart';

/// Microsoft device-code sign-in: shows a code to enter at microsoft.com/link
/// and waits. Resolves to true once signed in.
Future<bool> showMinecraftSignInDialog(BuildContext context, MinecraftAccountController controller) async =>
    await showTermDialog<bool>(context, _MinecraftSignInDialog(controller: controller)) ?? false;

class _MinecraftSignInDialog extends StatefulWidget {
  const _MinecraftSignInDialog({required this.controller});
  final MinecraftAccountController controller;

  @override
  State<_MinecraftSignInDialog> createState() => _MinecraftSignInDialogState();
}

class _MinecraftSignInDialogState extends State<_MinecraftSignInDialog> {
  DeviceCode? _code;
  String? _error;
  bool _cancelled = false;
  bool _copied = false;
  final _offlineName = TextEditingController();

  bool get _configured => widget.controller.auth.isConfigured;

  @override
  void initState() {
    super.initState();
    if (_configured) _start();
  }

  @override
  void dispose() {
    _cancelled = true;
    _offlineName.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _code = null;
      _copied = false;
    });
    try {
      await widget.controller.signIn(
        onCode: (code) {
          if (mounted) setState(() => _code = code);
        },
        isCancelled: () => _cancelled,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on MinecraftAuthException catch (e) {
      if (mounted && !_cancelled) setState(() => _error = e.message);
    } catch (e) {
      if (mounted && !_cancelled) setState(() => _error = 'Could not reach Microsoft ($e).');
    }
  }

  Future<void> _offline() async {
    try {
      await widget.controller.signInOffline(_offlineName.text);
      if (mounted) Navigator.of(context).pop(true);
    } on MinecraftAuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final code = _code;
    return TermDialog(
      title: 'MINECRAFT',
      width: 520,
      blurb: _configured
          ? 'Sign in with the Microsoft account that owns Minecraft: Java Edition. '
              'Open the link, enter the code, and this window finishes on its own.'
          : 'Microsoft sign-in isn\'t configured in this build (BOLOTO_MS_CLIENT_ID).',
      actions: [
        TermButton(label: 'Cancel', onTap: () => Navigator.of(context).pop(false)),
        if (_configured && _error != null) TermButton(label: 'Try again', onTap: _start),
      ],
      children: [
        if (_configured && code != null) ...[
          Center(
            child: SelectableText(
              code.userCode,
              style: vt(56, height: 1, color: pal.ph, shadows: pal.glow),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TermButton(
                label: _copied ? 'Copied' : 'Copy code',
                fontSize: 11,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: code.userCode));
                  if (mounted) setState(() => _copied = true);
                },
              ),
              const SizedBox(width: 12),
              TermButton(
                label: 'Open ${code.verificationUri.host}',
                icon: TermIcon.globe,
                fontSize: 11,
                onTap: () => launchUrl(code.verificationUri, mode: LaunchMode.externalApplication),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_error == null) Text('> WAITING FOR MICROSOFT…', style: mono(11, ls: .08, color: pal.dim)),
        ] else if (_configured && _error == null)
          Text('> CONTACTING MICROSOFT…', style: mono(11, ls: .08, color: pal.dim)),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text('> ${_error!.toUpperCase()}', style: mono(11, ls: .06, height: 1.5, color: pal.ph)),
        ],
        if (widget.controller.offlineAllowed) ...[
          const SizedBox(height: 18),
          Text('DEV BUILD · OFFLINE PROFILE (SINGLEPLAYER ONLY)', style: mono(10, ls: .14, color: pal.dim)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: TermField(controller: _offlineName, hint: 'Username', fontSize: 13, onSubmitted: (_) => _offline())),
              const SizedBox(width: 10),
              TermButton(label: 'Play offline', fontSize: 11, onTap: _offline),
            ],
          ),
        ],
      ],
    );
  }
}
