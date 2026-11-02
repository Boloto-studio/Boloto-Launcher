import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/shared_preferences.dart';
import '../library/packs.dart';

/// Thrown for any failed API call. [code] is the server's error code
/// (`invalid_key`, `key_used_up`, …) or `network` when it couldn't be reached.
class ApiException implements Exception {
  const ApiException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// A boloto.studio website account signed in on this launcher.
class Account {
  const Account({required this.username, this.avatarUrl, this.minecraftUsername});

  final String username;
  final String? avatarUrl;
  final String? minecraftUsername;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        username: json['username'] as String,
        avatarUrl: json['avatar'] as String?,
        minecraftUsername: json['minecraft_username'] as String?,
      );
}

class RedeemResult {
  const RedeemResult({required this.pack, required this.buildSlug, required this.alreadyRedeemed});
  final Pack pack;
  final String buildSlug;
  final bool alreadyRedeemed;
}

/// Talks to the website's `/api/launcher/` endpoints.
///
/// The launcher install is identified by a token the server hands out when
/// someone signs in, or the first time a key is redeemed while signed out.
/// It is kept in shared preferences and sent with every request, so the
/// catalog includes whatever this launcher (or its account) has unlocked.
class LauncherApi {
  LauncherApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? defaultBaseUrl;

  /// Override for local testing: `flutter run --dart-define=BOLOTO_API=http://127.0.0.1:8000`
  static const defaultBaseUrl = String.fromEnvironment('BOLOTO_API', defaultValue: 'https://boloto.studio');
  static const _timeout = Duration(seconds: 15);

  final http.Client _client;
  final String baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl/api/launcher/$path');

  Future<List<Pack>> fetchCatalog() async {
    final json = await _send('GET', 'modpacks/', token: await _storedToken());
    return [
      for (final entry in json['modpacks'] as List) Pack.fromJson(entry as Map<String, dynamic>),
    ];
  }

  Future<RedeemResult> redeemKey(String code) async {
    Future<Map<String, dynamic>> attempt(String token) =>
        _send('POST', 'keys/redeem/', token: token, body: {'code': code});

    Map<String, dynamic> json;
    try {
      json = await attempt(await _storedToken() ?? await _register());
    } on ApiException catch (e) {
      // The server no longer knows our token (e.g. the database was reset).
      if (e.code != 'unauthorized') rethrow;
      json = await attempt(await _register());
    }
    return RedeemResult(
      pack: Pack.fromJson(json['modpack'] as Map<String, dynamic>),
      buildSlug: (json['unlocked'] as Map<String, dynamic>)['slug'] as String,
      alreadyRedeemed: json['already_redeemed'] as bool? ?? false,
    );
  }

  /// The account signed in on this launcher, or null when signed out.
  Future<Account?> fetchAccount() async {
    final token = await _storedToken();
    if (token == null) return null;
    try {
      final json = await _send('GET', 'auth/me/', token: token);
      final account = json['account'];
      return account is Map<String, dynamic> ? Account.fromJson(account) : null;
    } on ApiException catch (e) {
      if (e.code != 'unauthorized') rethrow;
      // The server forgot this launcher; start over as a new one.
      await _prefs().then((p) => p.remove(PrefKeys.launcherToken));
      return null;
    }
  }

  /// Signs in with a website account. Sends the current token (if any) so
  /// keys redeemed here while signed out move into the account.
  Future<Account> signIn(String username, String password) async {
    final json = await _send(
      'POST',
      'auth/login/',
      token: await _storedToken(),
      body: {'username': username, 'password': password},
    );
    await _prefs().then((p) => p.setString(PrefKeys.launcherToken, json['token'] as String));
    return Account.fromJson(json['account'] as Map<String, dynamic>);
  }

  Future<void> signOut() async {
    final token = await _storedToken();
    if (token == null) return;
    try {
      await _send('POST', 'auth/logout/', token: token);
    } on ApiException catch (e) {
      // Unknown token means we're already signed out as far as the server cares.
      if (e.code != 'unauthorized') rethrow;
      await _prefs().then((p) => p.remove(PrefKeys.launcherToken));
    }
  }

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<String?> _storedToken() async => (await SharedPreferences.getInstance()).getString(PrefKeys.launcherToken);

  Future<String> _register() async {
    final json = await _send('POST', 'clients/');
    final token = json['token'] as String;
    await (await SharedPreferences.getInstance()).setString(PrefKeys.launcherToken, token);
    return token;
  }

  Future<Map<String, dynamic>> _send(String method, String path, {String? token, Object? body}) async {
    final request = http.Request(method, _uri(path))
      ..headers['Accept'] = 'application/json'
      ..followRedirects = false;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(_timeout));
    } on Exception {
      throw const ApiException('network', 'Could not reach boloto.studio.');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300 && decoded is Map<String, dynamic>) {
      return decoded;
    }
    final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
    if (error is Map<String, dynamic>) {
      throw ApiException(error['code'] as String? ?? 'error', error['message'] as String? ?? 'Request failed.');
    }
    throw ApiException('http_${response.statusCode}', 'Server error (${response.statusCode}).');
  }
}
