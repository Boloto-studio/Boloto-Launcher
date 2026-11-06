import 'dart:convert';

import 'package:http/http.dart' as http;

/// Azure app (client) ID for Microsoft sign-in. Set at build time:
/// `flutter run --dart-define=BOLOTO_MS_CLIENT_ID=<id>`.
const msClientId = String.fromEnvironment('BOLOTO_MS_CLIENT_ID');

const _msBase = 'https://login.microsoftonline.com/consumers/oauth2/v2.0';
const _scope = 'XboxLive.signin offline_access';

class MinecraftAuthException implements Exception {
  const MinecraftAuthException(this.message, {this.signInAgain = false});
  final String message;

  /// The stored session is no good; the player has to sign in again.
  final bool signInAgain;

  @override
  String toString() => message;
}

/// What to show the player during device-code sign-in.
class DeviceCode {
  const DeviceCode({
    required this.userCode,
    required this.deviceCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresAt,
  });

  final String userCode;
  final String deviceCode;
  final Uri verificationUri;
  final Duration interval;
  final DateTime expiresAt;
}

/// A signed-in Minecraft account, as stored between launches.
class MinecraftAccount {
  const MinecraftAccount({
    required this.uuid,
    required this.name,
    required this.accessToken,
    required this.expiresAt,
    required this.refreshToken,
    this.xuid = '',
    this.offline = false,
  });

  final String uuid;
  final String name;

  /// Minecraft services token (~24h).
  final String accessToken;
  final DateTime expiresAt;

  /// Microsoft refresh token, used to get a fresh access token.
  final String refreshToken;
  final String xuid;

  /// Debug-only offline profile (no Microsoft account).
  final bool offline;

  bool get isFresh => offline || DateTime.now().isBefore(expiresAt.subtract(const Duration(minutes: 5)));

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'name': name,
        'accessToken': accessToken,
        'expiresAt': expiresAt.toIso8601String(),
        'refreshToken': refreshToken,
        'xuid': xuid,
        'offline': offline,
      };

  factory MinecraftAccount.fromJson(Map<String, dynamic> j) => MinecraftAccount(
        uuid: j['uuid'] as String,
        name: j['name'] as String,
        accessToken: j['accessToken'] as String,
        expiresAt: DateTime.parse(j['expiresAt'] as String),
        refreshToken: j['refreshToken'] as String,
        xuid: j['xuid'] as String? ?? '',
        offline: j['offline'] as bool? ?? false,
      );
}

/// Microsoft → Xbox Live → XSTS → Minecraft services sign-in.
class MicrosoftAuth {
  MicrosoftAuth({http.Client? client, String? clientId})
      : _client = client ?? http.Client(),
        clientId = clientId ?? msClientId;

  final http.Client _client;
  final String clientId;

  bool get isConfigured => clientId.isNotEmpty;

  void _requireConfigured() {
    if (!isConfigured) {
      throw const MinecraftAuthException(
        'Microsoft sign-in isn\'t set up in this build (missing BOLOTO_MS_CLIENT_ID).',
      );
    }
  }

  /// Step 1: ask Microsoft for a code the player types at microsoft.com/link.
  Future<DeviceCode> startDeviceCode() async {
    _requireConfigured();
    final r = await _client.post(Uri.parse('$_msBase/devicecode'), body: {'client_id': clientId, 'scope': _scope});
    final j = _json(r);
    if (r.statusCode != 200) throw MinecraftAuthException(_msError(j) ?? 'Microsoft sign-in failed (${r.statusCode}).');
    return DeviceCode(
      userCode: j['user_code'] as String,
      deviceCode: j['device_code'] as String,
      verificationUri: Uri.parse(j['verification_uri'] as String? ?? 'https://www.microsoft.com/link'),
      interval: Duration(seconds: (j['interval'] as num?)?.toInt() ?? 5),
      expiresAt: DateTime.now().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 900)),
    );
  }

  /// Step 2: wait until the player approves, then sign in to Minecraft.
  Future<MinecraftAccount> completeDeviceCode(DeviceCode code, {bool Function()? isCancelled}) async {
    var interval = code.interval;
    while (true) {
      await Future<void>.delayed(interval);
      if (isCancelled?.call() ?? false) throw const MinecraftAuthException('Sign-in cancelled.');
      if (DateTime.now().isAfter(code.expiresAt)) {
        throw const MinecraftAuthException('The code expired. Try signing in again.');
      }
      final r = await _client.post(Uri.parse('$_msBase/token'), body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        'client_id': clientId,
        'device_code': code.deviceCode,
      });
      final j = _json(r);
      if (r.statusCode == 200) return _minecraftFromMicrosoft(j);
      switch (j['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += const Duration(seconds: 5);
          continue;
        case 'authorization_declined':
          throw const MinecraftAuthException('Sign-in was declined.');
        case 'expired_token':
          throw const MinecraftAuthException('The code expired. Try signing in again.');
        default:
          throw MinecraftAuthException(_msError(j) ?? 'Microsoft sign-in failed (${r.statusCode}).');
      }
    }
  }

  /// Gets a fresh Minecraft token from a stored Microsoft refresh token.
  Future<MinecraftAccount> refresh(MinecraftAccount account) async {
    _requireConfigured();
    final r = await _client.post(Uri.parse('$_msBase/token'), body: {
      'grant_type': 'refresh_token',
      'client_id': clientId,
      'refresh_token': account.refreshToken,
      'scope': _scope,
    });
    final j = _json(r);
    if (r.statusCode != 200) {
      throw MinecraftAuthException(
        'Your Microsoft sign-in expired. Sign in again.',
        signInAgain: true,
      );
    }
    return _minecraftFromMicrosoft(j);
  }

  Future<MinecraftAccount> _minecraftFromMicrosoft(Map<String, dynamic> ms) async {
    final msToken = ms['access_token'] as String;
    final refreshToken = ms['refresh_token'] as String? ?? '';

    // Xbox Live
    final xbl = await _postJson('https://user.auth.xboxlive.com/user/authenticate', {
      'Properties': {'AuthMethod': 'RPS', 'SiteName': 'user.auth.xboxlive.com', 'RpsTicket': 'd=$msToken'},
      'RelyingParty': 'http://auth.xboxlive.com',
      'TokenType': 'JWT',
    });
    if (xbl.$1 != 200) throw MinecraftAuthException('Xbox Live sign-in failed (${xbl.$1}).');
    final xblToken = xbl.$2['Token'] as String;

    // XSTS for Minecraft services
    final xsts = await _postJson('https://xsts.auth.xboxlive.com/xsts/authorize', {
      'Properties': {'SandboxId': 'RETAIL', 'UserTokens': [xblToken]},
      'RelyingParty': 'rp://api.minecraftservices.com/',
      'TokenType': 'JWT',
    });
    if (xsts.$1 != 200) throw MinecraftAuthException(_xstsError(xsts.$2) ?? 'Xbox sign-in failed (${xsts.$1}).');
    final xstsToken = xsts.$2['Token'] as String;
    final claims = ((xsts.$2['DisplayClaims'] as Map<String, dynamic>)['xui'] as List<dynamic>).first as Map<String, dynamic>;
    final uhs = claims['uhs'] as String;

    // Minecraft services
    final mc = await _postJson('https://api.minecraftservices.com/authentication/login_with_xbox', {
      'identityToken': 'XBL3.0 x=$uhs;$xstsToken',
    });
    if (mc.$1 == 403) {
      throw const MinecraftAuthException(
        'Minecraft refused this launcher\'s app registration. The Azure app ID needs Mojang\'s approval '
        '(apply at https://aka.ms/mce-reviewappid).',
      );
    }
    if (mc.$1 != 200) throw MinecraftAuthException('Minecraft sign-in failed (${mc.$1}).');
    final mcToken = mc.$2['access_token'] as String;
    final expiresIn = (mc.$2['expires_in'] as num?)?.toInt() ?? 86400;

    // Profile: also tells us whether they own the game.
    final profile = await _client.get(
      Uri.parse('https://api.minecraftservices.com/minecraft/profile'),
      headers: {'Authorization': 'Bearer $mcToken'},
    );
    if (profile.statusCode == 404) {
      throw const MinecraftAuthException(
        'This Microsoft account doesn\'t own Minecraft: Java Edition (or hasn\'t picked a name yet).',
      );
    }
    if (profile.statusCode != 200) throw MinecraftAuthException('Could not load the Minecraft profile (${profile.statusCode}).');
    final pj = _json(profile);

    return MinecraftAccount(
      uuid: pj['id'] as String,
      name: pj['name'] as String,
      accessToken: mcToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      refreshToken: refreshToken,
      xuid: (claims['xid'] as String?) ?? '',
    );
  }

  Future<(int, Map<String, dynamic>)> _postJson(String url, Map<String, dynamic> body) async {
    final r = await _client.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode(body),
    );
    return (r.statusCode, _json(r));
  }

  static Map<String, dynamic> _json(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      return d is Map<String, dynamic> ? d : const {};
    } on FormatException {
      return const {};
    }
  }

  static String? _msError(Map<String, dynamic> j) => j['error_description'] as String? ?? j['error'] as String?;

  static String? _xstsError(Map<String, dynamic> j) => switch ((j['XErr'] as num?)?.toInt()) {
        2148916233 => 'This Microsoft account has no Xbox profile yet. Sign in once at minecraft.net to create one.',
        2148916235 => 'Xbox Live isn\'t available in your country.',
        2148916236 || 2148916237 => 'This account needs adult verification on the Xbox website first.',
        2148916238 => 'This is a child account; an adult needs to add it to a Microsoft family first.',
        _ => null,
      };
}
