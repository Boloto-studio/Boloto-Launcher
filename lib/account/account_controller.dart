import 'package:flutter/foundation.dart';

import '../api/launcher_api.dart';

/// Who is signed in on this launcher. [onSessionChanged] fires after a
/// sign-in or sign-out so the rack can reload with that account's unlocks.
class AccountController extends ChangeNotifier {
  AccountController({required this.api, this.onSessionChanged});

  final LauncherApi api;
  final VoidCallback? onSessionChanged;

  Account? _account;
  bool _loaded = false;
  bool _disposed = false;

  Account? get account => _account;
  bool get signedIn => _account != null;

  /// False until the first [load] finishes, so the header doesn't flash
  /// "Sign in" for someone who is already signed in.
  bool get loaded => _loaded;

  Future<void> load() async {
    Account? account;
    try {
      account = await api.fetchAccount();
    } on ApiException {
      account = null; // offline: show as signed out, the token is kept
    }
    if (_disposed) return;
    _account = account;
    _loaded = true;
    notifyListeners();
  }

  /// Throws [ApiException] (e.g. `invalid_credentials`) on failure.
  Future<void> signIn(String username, String password) async {
    final account = await api.signIn(username, password);
    if (_disposed) return;
    _account = account;
    _loaded = true;
    notifyListeners();
    onSessionChanged?.call();
  }

  Future<void> signOut() async {
    await api.signOut();
    if (_disposed) return;
    _account = null;
    notifyListeners();
    onSessionChanged?.call();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
