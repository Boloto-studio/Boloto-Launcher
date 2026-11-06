import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/launcher_api.dart';
import '../ui/dialog.dart';
import '../ui/icons.dart';
import '../ui/palette.dart';
import '../ui/widgets.dart';
import 'account_controller.dart';

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

  Future<void> _openRegister() async {
    final url = widget.controller.api.registerUrl;
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Exception {
      opened = false;
    }
    if (!opened && mounted) setState(() => _error = 'Could not open $url');
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
        Row(
          children: [
            Expanded(child: Text('NO ACCOUNT YET?', style: mono(11, ls: .08, color: pal.dim))),
            TermButton(
              label: 'Create account',
              icon: TermIcon.globe,
              fontSize: 11,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              semanticLabel: 'Create an account on boloto.studio (opens your browser)',
              onTap: _openRegister,
            ),
          ],
        ),
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

  @override
  void initState() {
    super.initState();
    widget.controller.refresh(); // pick up a new avatar, friends, unlocks…
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.signOut();
      _close();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  /// Closes this dialog once, even if sign-out and the controller both ask.
  void _close() {
    if (mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
  }

  Future<void> _openProfile(Uri url) async {
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Exception {
      opened = false;
    }
    if (!opened && mounted) setState(() => _error = 'Could not open $url');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final account = widget.controller.account;
        if (account == null) {
          // Signed out (here or because the server dropped the session).
          WidgetsBinding.instance.addPostFrameCallback((_) => _close());
          return const SizedBox.shrink();
        }
        final pal = context.pal;
        final profileUrl = account.profileUrl;
        return TermDialog(
          title: 'ACCOUNT',
          width: 580,
          actions: [
            TermButton(label: 'Sign out', onTap: _busy ? null : _signOut),
            TermButton(label: 'Close', onTap: _busy ? null : _close),
            TermButton(
              label: 'View full profile',
              icon: TermIcon.globe,
              semanticLabel: 'Open your frogs.net profile in the browser',
              onTap: profileUrl == null ? null : () => _openProfile(profileUrl),
            ),
          ],
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(account: account, size: 104),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.displayName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: vt(42, height: .95, color: pal.ph, shadows: pal.glow),
                      ),
                      const SizedBox(height: 4),
                      Text('@${account.username}', style: mono(12, ls: .06, color: pal.dim)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (account.tier != null) TagChip(account.tier!.toUpperCase()),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Led(LedState.on),
                              const SizedBox(width: 6),
                              Text('SIGNED IN', style: mono(11, ls: .12, color: pal.ph)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (account.bio != null) ...[
              const SizedBox(height: 16),
              Text(
                account.bio!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: mono(13, height: 1.55, color: pal.ph),
              ),
            ],
            const SizedBox(height: 18),
            CustomPaint(
              foregroundPainter: DashedBorderPainter(color: pal.rule, right: false, bottom: false, left: false),
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Wrap(
                  spacing: 18,
                  runSpacing: 14,
                  children: [
                    _Stat('MINECRAFT', account.minecraftUsername ?? '[NOT LINKED]', dim: account.minecraftUsername == null),
                    _Stat('LOCATION', account.location ?? '[UNKNOWN]', dim: account.location == null),
                    _Stat('MEMBER SINCE', _monthYear(account.memberSince)),
                    _Stat('FRIENDS', '${account.friendsCount}'),
                    _Stat('UNLOCKED PACKS', '${account.unlockedCount}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            FormStatus(busy: _busy, busyText: '> SIGNING OUT…', error: _error),
          ],
        );
      },
    );
  }
}

const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

String _monthYear(DateTime? d) => d == null ? '—' : '${_months[d.month - 1]} ${d.year}';

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.dim = false});
  final String label;
  final String value;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: mono(10, ls: .14, color: pal.dim)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono(13, ls: .04, color: dim ? pal.dim : pal.ph),
          ),
        ],
      ),
    );
  }
}

/// The frogs.net avatar, tinted to the phosphor like everything else on the
/// tube. Falls back to the user's initials when there's no picture.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.account, required this.size});
  final Account account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final initials = account.displayName.trim().isEmpty ? '?' : account.displayName.trim()[0].toUpperCase();
    final fallback = ColoredBox(
      color: pal.a(.08),
      child: Center(child: Text(initials, style: vt(size * .55, height: 1, color: pal.ph, shadows: pal.glow))),
    );
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kBg,
        border: Border.all(color: pal.a(.6), width: 1.5),
        boxShadow: [BoxShadow(color: pal.a(.22), blurRadius: 14)],
      ),
      child: ClipRect(
        child: account.avatarUrl == null
            ? fallback
            : ColorFiltered(
                colorFilter: ColorFilter.mode(pal.ph, BlendMode.color),
                child: Image.network(
                  account.avatarUrl!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => fallback,
                  loadingBuilder: (context, child, progress) => progress == null ? child : fallback,
                ),
              ),
      ),
    );
  }
}
