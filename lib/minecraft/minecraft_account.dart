import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../game/launch.dart';
import 'microsoft_auth.dart';

/// Where the signed-in account is kept between launches.
abstract class AccountStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// OS keychain / Windows Credential Manager.
class SecureAccountStore implements AccountStore {
  static const _key = 'minecraft.account';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// For tests.
class MemoryAccountStore implements AccountStore {
  MemoryAccountStore([this.value]);
  String? value;

  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

/// The Minecraft (Microsoft) account used to launch the game. Separate from
/// the boloto.studio account in the header, which unlocks packs.
class MinecraftAccountController extends ChangeNotifier {
  MinecraftAccountController({MicrosoftAuth? auth, AccountStore? store})
      : auth = auth ?? MicrosoftAuth(),
        _store = store ?? SecureAccountStore();

  final MicrosoftAuth auth;
  final AccountStore _store;

  MinecraftAccount? _account;
  bool _loaded = false;
  bool _disposed = false;

  MinecraftAccount? get account => _account;
  bool get signedIn => _account != null;
  bool get loaded => _loaded;

  /// Offline profiles exist only in debug builds, to test launching before
  /// the Azure app is approved by Mojang. They can't join online servers.
  bool get offlineAllowed => kDebugMode;

  Future<void> load() async {
    try {
      final raw = await _store.read();
      _account = raw == null ? null : MinecraftAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (_account != null && _account!.offline && !offlineAllowed) _account = null;
    } catch (_) {
      _account = null; // unreadable / old format: just sign in again
    }
    _loaded = true;
    _notify();
  }

  /// Device-code sign-in. [onCode] is called once with what to show the
  /// player; the future completes when they've approved it.
  Future<void> signIn({required void Function(DeviceCode) onCode, bool Function()? isCancelled}) async {
    final code = await auth.startDeviceCode();
    onCode(code);
    final account = await auth.completeDeviceCode(code, isCancelled: isCancelled);
    await _save(account);
  }

  /// Debug-only offline profile (no Microsoft account).
  Future<void> signInOffline(String name) async {
    if (!offlineAllowed) throw const MinecraftAuthException('Offline play is only available in development builds.');
    final clean = name.trim();
    if (!RegExp(r'^[A-Za-z0-9_]{3,16}$').hasMatch(clean)) {
      throw const MinecraftAuthException('Use 3–16 letters, numbers or underscores.');
    }
    await _save(MinecraftAccount(
      uuid: offlineUuid(clean),
      name: clean,
      accessToken: '0',
      expiresAt: DateTime(9999),
      refreshToken: '',
      offline: true,
    ));
  }

  Future<void> signOut() async {
    await _store.delete();
    _account = null;
    _notify();
  }

  /// A session good for launching, refreshing the token when needed.
  Future<LaunchSession> session() async {
    var account = _account;
    if (account == null) throw const MinecraftAuthException('Sign in with Microsoft first.', signInAgain: true);
    if (!account.isFresh) {
      try {
        account = await auth.refresh(account);
        await _save(account);
      } on MinecraftAuthException catch (e) {
        if (e.signInAgain) await signOut();
        rethrow;
      }
    }
    return LaunchSession(
      username: account.name,
      uuid: account.uuid,
      accessToken: account.accessToken,
      xuid: account.xuid,
      userType: account.offline ? 'legacy' : 'msa',
    );
  }

  Future<void> _save(MinecraftAccount account) async {
    await _store.write(jsonEncode(account.toJson()));
    _account = account;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Minecraft's offline-mode UUID: v3 UUID of "OfflinePlayer:<name>", no dashes.
String offlineUuid(String name) {
  final bytes = md5.convert(utf8.encode('OfflinePlayer:$name')).bytes.toList();
  bytes[6] = (bytes[6] & 0x0f) | 0x30;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
