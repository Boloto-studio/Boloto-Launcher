import 'package:flutter/material.dart';

import '../api/launcher_api.dart';
import '../ui/dialog.dart';
import '../ui/icons.dart';
import '../ui/palette.dart';
import '../ui/widgets.dart';
import 'account_controller.dart';

const registerUrl = 'boloto.studio/frogs/register/';

/// Sign-in form when signed out; account details and Sign out when signed in.
Future<void> showAccountDialog(BuildContext context, AccountController controller) => showTermDialog<void>(
      context,
      controller.signedIn ? _AccountDialog(controller: controller) : _SignInDialog(controller: controller),
    );

class _SignInDialog extends StatefulWidget {
  const _SignInDialog({required this.controller});
  final AccountController controller;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.signIn(_username.text.trim(), _password.text);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
          _password.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return TermDialog(
      title: 'ACCOUNT',
      blurb: 'Sign in with your boloto.studio account. Packs you unlock with keys stay on your account on every PC.',
      actions: [
        TermButton(label: 'Cancel', onTap: _busy ? null : () => Navigator.of(context).pop()),
        TermButton(label: 'Sign in', icon: TermIcon.user, onTap: _busy ? null : _submit),
      ],
      children: [
        TermField(
          controller: _username,
          autofocus: true,
          enabled: !_busy,
          label: 'USERNAME',
          fontSize: 14,
          letterSpacing: .04,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        TermField(
          controller: _password,
          obscure: true,
          enabled: !_busy,
          label: 'PASSWORD',
          fontSize: 14,
          letterSpacing: .04,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 10),
        FormStatus(busy: _busy, busyText: '> AUTHENTICATING…', error: _error),
        const SizedBox(height: 6),
        Text('NO ACCOUNT? REGISTER AT $registerUrl', style: mono(11, ls: .08, color: pal.dim)),
      ],
    );
  }
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.controller});
  final AccountController controller;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.signOut();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final account = widget.controller.account!;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(width: 120, child: Text(k, style: mono(12, ls: .12, color: pal.dim))),
              Expanded(child: Text(v, style: mono(13, ls: .04, color: pal.ph), overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
    return TermDialog(
      title: 'ACCOUNT',
      actions: [
        TermButton(label: 'Close', onTap: _busy ? null : () => Navigator.of(context).pop()),
        TermButton(label: 'Sign out', onTap: _busy ? null : _signOut),
      ],
      children: [
        row('SIGNED IN AS', account.username),
        row('MINECRAFT', account.minecraftUsername ?? '[NOT LINKED]'),
        const SizedBox(height: 4),
        FormStatus(busy: _busy, busyText: '> SIGNING OUT…', error: _error),
      ],
    );
  }
}
