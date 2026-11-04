import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lib_boloto_launcher/api/launcher_api.dart';
import 'package:lib_boloto_launcher/app/settings.dart';
import 'package:lib_boloto_launcher/game/downloader.dart';
import 'package:lib_boloto_launcher/game/forge.dart' show LogCallback;
import 'package:lib_boloto_launcher/game/game_service.dart';
import 'package:lib_boloto_launcher/game/launch.dart';
import 'package:lib_boloto_launcher/library/packs.dart';
import 'package:lib_boloto_launcher/main.dart';
import 'package:lib_boloto_launcher/minecraft/microsoft_auth.dart';
import 'package:lib_boloto_launcher/minecraft/minecraft_account.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Steps through time without pumpAndSettle (the CRT effects loop forever).
Future<void> wait(WidgetTester t, int ms) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Tests default to the wide Ahem font; layout only makes sense with the real ones.
Future<void> loadFonts() async {
  for (final (family, files) in [
    ('IBMPlexMono', ['IBMPlexMono-Regular', 'IBMPlexMono-Medium', 'IBMPlexMono-Bold']),
    ('VT323', ['VT323-Regular']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(File('assets/fonts/$f.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }
}

Map<String, Object?> build(String slug, String name, {bool release = false, bool key = false}) => {
      'slug': slug,
      'name': name,
      'version': '',
      'is_release': release,
      'is_published': !key,
      'unlocked_by_key': key,
      'git_url': 'https://github.com/boloto-studio/vatra',
      'git_branch': release ? 'main' : 'dev',
      'minecraft_version': '1.20.1',
      'mod_loader': 'forge',
      'loader_version': '47.3.0',
      'updated_at': '2026-11-02T00:00:00Z',
    };

Map<String, Object?> vatra(List<Map<String, Object?>> builds) => {
      'slug': 'vatra',
      'name': 'Vatra',
      'description': 'A Carpathian fantasy RPG rooted in Hutsul mythology.',
      'code': 'VTR-02',
      'status': 'IN DEVELOPMENT',
      'color': '#FFB000',
      'features': ['Village building & hired squads', 'Magic & dragons'],
      'icon': null,
      'logo': null,
      'background': null,
      'builds': builds,
    };

/// Every request the fake server saw, as `METHOD path [token]`.
final requests = <String>[];

/// Stand-in for boloto.studio: Vatra's release is public, the key `DEV-KEY`
/// unlocks its dev build, and `mavka` / `pisnya` is a website account.
MockClient fakeServer({bool emptyRack = false}) {
  var unlocked = false;
  var signedIn = false;
  requests.clear();
  http.Response ok(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
  List<Map<String, Object?>> builds() => [
        build('vatra', 'Release', release: true),
        if (unlocked) build('vatra-dev', 'Dev', key: true),
      ];
  return MockClient((req) async {
    requests.add('${req.method} ${req.url.path} ${req.headers['Authorization'] ?? '-'}');
    final account = {
      'username': 'mavka',
      'display_name': 'Lisova Mavka',
      'avatar': null,
      'minecraft_username': 'Mavka_UA',
      'bio': 'Forest spirit. Do not follow the singing.',
      'tier': 'Frog',
      'location': null,
      'member_since': '2026-09-14',
      'friends_count': 3,
      'unlocked_count': 1,
      'profile_url': 'https://test.invalid/frogs/profile/42/',
    };
    switch (req.url.path) {
      case '/api/launcher/auth/login/':
        final body = jsonDecode(req.body);
        if (body['username'] != 'mavka' || body['password'] != 'pisnya') {
          return ok({'error': {'code': 'invalid_credentials', 'message': 'Wrong username or password.'}}, 401);
        }
        signedIn = true;
        return ok({'token': 'acct', 'account': account});
      case '/api/launcher/auth/logout/':
        signedIn = false;
        return ok({'account': null});
      case '/api/launcher/auth/me/':
        return ok({'account': signedIn ? account : null});
      case '/api/launcher/modpacks/':
        return ok({
          'modpacks': [if (!emptyRack) vatra(builds())],
        });
      case '/api/launcher/clients/':
        return ok({'token': 'tok', 'client_id': 1}, 201);
      case '/api/launcher/keys/redeem/':
        if (req.headers['Authorization'] != 'Bearer tok') {
          return ok({'error': {'code': 'unauthorized', 'message': 'Register first.'}}, 401);
        }
        if (jsonDecode(req.body)['code'] != 'DEV-KEY') {
          return ok({'error': {'code': 'invalid_key', 'message': 'That key is not valid.'}}, 404);
        }
        unlocked = true;
        return ok({
          'already_redeemed': false,
          'unlocked': {'slug': 'vatra-dev', 'name': 'Vatra / Dev'},
          'modpack': vatra(builds()),
        });
    }
    return http.Response('not found', 404);
  });
}

/// Stands in for Mojang/Forge/git: reports progress, logs a few lines, and
/// "runs" until stopped. Set [failWith] to make the install fail.
class FakeGameService implements GameService {
  String? failWith;
  final launched = <String>[];
  LaunchSession? lastSession;
  Completer<int>? _exit;

  @override
  Future<bool> isInstalled(PackBuild build) async => false;

  @override
  Future<RunningGame> launch(
    PackBuild build, {
    required LaunchSession session,
    required int memoryGb,
    required void Function(InstallProgress) onProgress,
    required LogCallback log,
    CancelToken? cancel,
  }) async {
    launched.add(build.slug);
    lastSession = session;
    onProgress(const InstallProgress('ASSETS', .5));
    log('[minecraft] assets');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (failWith != null) throw GameException(failWith!);
    log('[main/INFO]: Loading Minecraft 1.20.1 with Fabric… just kidding, Forge 47.3.0');
    final exit = Completer<int>();
    _exit = exit;
    return RunningGame(exitCode: exit.future, stop: () => exit.complete(0));
  }

  void crash(int code) => _exit?.complete(code);
}

/// A signed-in Minecraft account, already in the store.
MinecraftAccountController signedInMinecraft() => MinecraftAccountController(
      auth: MicrosoftAuth(clientId: ''),
      store: MemoryAccountStore(jsonEncode(MinecraftAccount(
        uuid: '069a79f444e94726a5befca90e38aaf5',
        name: 'Mavka_UA',
        accessToken: 'mc-token',
        expiresAt: DateTime(2999),
        refreshToken: 'ms-refresh',
      ).toJson())),
    );

late FakeGameService game;

Future<void> boot(
  WidgetTester t, {
  Map<String, Object> prefs = const {},
  Size size = const Size(1360, 860),
  bool emptyRack = false,
  MinecraftAccountController? minecraft,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final api = LauncherApi(client: fakeServer(emptyRack: emptyRack), baseUrl: 'https://test.invalid');
  game = FakeGameService();
  await t.pumpWidget(BolotoApp(
    settings: await AppSettings.load(),
    api: api,
    game: game,
    minecraft: minecraft ?? signedInMinecraft(),
  ));
  await wait(t, 3500);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('tape goes empty → ready → running → ejected', (t) async {
    await boot(t);
    expect(find.text('NO MEDIA'), findsOneWidget);

    await t.tap(find.text('VATRA').first);
    await wait(t, 2500);
    expect(find.text('INSTALL & RUN'), findsOneWidget);
    expect(find.text('READY'), findsOneWidget);

    await t.tap(find.text('INSTALL & RUN'));
    await wait(t, 100);
    expect(find.text('ASSETS 50%'), findsOneWidget); // install progress in the footer
    await wait(t, 500);
    expect(find.text('GAME RUNNING'), findsOneWidget);
    expect(find.text('> GAME RUNNING — LIVE LOG'), findsOneWidget);
    expect(find.textContaining('Forge 47.3.0'), findsOneWidget); // game output streamed in
    expect(game.launched, ['vatra']);
    expect(game.lastSession!.username, 'Mavka_UA');
    expect(find.text('EJECT'), findsOneWidget);

    await t.tap(find.text('STOP'));
    await wait(t, 300);
    expect(find.text('GAME CLOSED'), findsOneWidget);
    await t.tap(find.text('EJECT'));
    await wait(t, 1500);
    expect(find.text('NO MEDIA'), findsOneWidget);
  });

  testWidgets('a crash or failed install leaves the log up with the error', (t) async {
    await boot(t);
    await t.tap(find.text('VATRA').first);
    await wait(t, 2500);
    await t.tap(find.text('INSTALL & RUN'));
    await wait(t, 600);
    game.crash(1);
    await wait(t, 300);
    expect(find.text('GAME CRASHED (EXIT 1)'), findsOneWidget);
    expect(find.text('> game exited (code 1)'), findsOneWidget);

    game.failWith = 'Forge install step failed.';
    await t.tap(find.text('RUN'));
    await wait(t, 600);
    expect(find.text('FAILED'), findsOneWidget);
    expect(find.text('> ERROR: Forge install step failed.'), findsOneWidget);
  });

  testWidgets('Run asks for a Minecraft account first (offline profile in dev builds)', (t) async {
    final mc = MinecraftAccountController(auth: MicrosoftAuth(clientId: ''), store: MemoryAccountStore());
    await boot(t, minecraft: mc);
    await t.tap(find.text('VATRA').first);
    await wait(t, 2500);
    await t.tap(find.text('INSTALL & RUN'));
    await wait(t, 500);
    expect(find.text('MINECRAFT'), findsWidgets); // dialog title
    expect(find.textContaining('BOLOTO_MS_CLIENT_ID'), findsOneWidget); // no Azure app in tests

    await t.enterText(find.byType(TextField), 'Mavka_UA');
    await t.tap(find.text('PLAY OFFLINE'));
    await wait(t, 800);
    expect(game.launched, ['vatra']);
    expect(game.lastSession!.userType, 'legacy');
    expect(mc.account!.offline, isTrue);
  });

  testWidgets('an empty rack says so instead of showing a blank tape', (t) async {
    await boot(t, emptyRack: true);
    expect(find.text('RACK EMPTY'), findsOneWidget);
    expect(find.text('BLANK'), findsNothing);
    expect(find.text('0 ON RACK'), findsOneWidget);
  });

  testWidgets('redeeming a key in Settings › Keys adds the dev build and loads it', (t) async {
    await boot(t);
    expect(find.text('BLANK'), findsNothing);
    expect(find.text('REDEEM KEY'), findsNothing); // no longer on the rack

    await t.tap(find.text('SETTINGS'));
    await wait(t, 2000);
    await t.tap(find.text('03 · KEYS'));
    await wait(t, 1500);
    expect(find.text('[NONE YET]'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'nope');
    await t.tap(find.text('REDEEM'));
    await wait(t, 300);
    expect(find.text('> THAT KEY IS NOT VALID.'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'DEV-KEY');
    await t.tap(find.text('REDEEM'));
    await wait(t, 300);
    expect(find.text("> VATRA / DEV UNLOCKED. IT'S IN THE DECK ON THE LIBRARY TAB."), findsOneWidget);
    expect(find.text('01  VATRA / DEV'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('launcher.token'), 'tok');

    await wait(t, 2500);
    await t.tap(find.text('LIBRARY'));
    await wait(t, 1500);
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget);
  });

  testWidgets('rescan lives in Settings › Keys and reloads the rack', (t) async {
    await boot(t);
    final before = requests.where((r) => r.startsWith('GET /api/launcher/modpacks/')).length;
    await t.tap(find.text('SETTINGS'));
    await wait(t, 2000);
    await t.tap(find.text('03 · KEYS'));
    await wait(t, 1500);
    await t.tap(find.text('RESCAN'));
    await wait(t, 300);
    expect(requests.where((r) => r.startsWith('GET /api/launcher/modpacks/')).length, before + 1);
    expect(find.text('> 1 ON RACK'), findsOneWidget);
  });

  testWidgets('signing in and out from the header', (t) async {
    await boot(t);
    await t.tap(find.text('SIGN IN'));
    await wait(t, 500);

    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'mavka');
    await t.enterText(fields.at(1), 'wrong');
    await t.tap(find.text('SIGN IN').last);
    await wait(t, 300);
    expect(find.text('> WRONG USERNAME OR PASSWORD.'), findsOneWidget);

    await t.enterText(fields.at(1), 'pisnya');
    await t.tap(find.text('SIGN IN').last);
    await wait(t, 500);

    expect(find.byType(TextField), findsNothing);
    expect(find.text('MAVKA'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('launcher.token'), 'acct');
    // The rack reloaded with the account's token.
    expect(requests, contains('GET /api/launcher/modpacks/ Bearer acct'));

    await t.tap(find.text('MAVKA'));
    await wait(t, 500);
    // Mini profile: name, handle, tier, bio, stats and a link to the full profile.
    expect(find.text('LISOVA MAVKA'), findsOneWidget);
    expect(find.text('@mavka'), findsOneWidget);
    expect(find.text('FROG'), findsOneWidget);
    expect(find.text('Forest spirit. Do not follow the singing.'), findsOneWidget);
    expect(find.text('Mavka_UA'), findsOneWidget);
    expect(find.text('[UNKNOWN]'), findsOneWidget); // no location set
    expect(find.text('SEP 2026'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('VIEW FULL PROFILE'), findsOneWidget);
    expect(find.text('L'), findsOneWidget); // initials stand in for the missing avatar
    await t.tap(find.text('SIGN OUT'));
    await wait(t, 500);
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(requests, contains('POST /api/launcher/auth/logout/ Bearer acct'));
  });

  testWidgets('settings are written through and restored on boot', (t) async {
    await boot(t);
    await t.tap(find.text('SETTINGS'));
    await wait(t, 2000);
    await t.tap(find.text('P3 AMBER'));
    await t.tap(find.text('FLOPPY'));
    await t.tap(find.text('OFF'));
    await t.tap(find.text('02 · LAUNCHER'));
    await wait(t, 500);
    await t.tap(find.text('12 GB'));
    await t.enterText(find.byType(TextField), r'D:\Games\Boloto');
    await wait(t, 500);

    final prefs = await SharedPreferences.getInstance();
    final saved = {for (final k in prefs.getKeys()) k: prefs.get(k)!};
    expect(saved, {
      'ui.phosphor': 'amber',
      'ui.media': 'floppy',
      'ui.crt': false,
      'launcher.ramGb': 12,
      'packPath': r'D:\Games\Boloto',
    });

    // Fresh app from the same prefs comes back with them.
    await t.pumpWidget(const SizedBox());
    await boot(t, prefs: saved);
    final s = await AppSettings.load();
    expect(s.phosphor, Phosphor.amber);
    expect(s.crt, isFalse);
    expect(find.text(r'INSTANCES: D:\Games\Boloto'), findsOneWidget);
  });

  testWidgets('every screen fits the minimum window size', (t) async {
    await boot(t, prefs: const {'ui.media': 'floppy'}, size: const Size(1200, 780));
    await t.tap(find.text('VATRA').first);
    await wait(t, 2500);
    for (final tab in ['SERVERS', 'FROGS.NET', 'SETTINGS', 'LIBRARY']) {
      await t.tap(find.text(tab));
      await wait(t, 1500);
    }
    await t.tap(find.text('SETTINGS'));
    await wait(t, 500);
    await t.tap(find.text('02 · LAUNCHER'));
    await wait(t, 1500);
    expect(find.text('Mavka_UA'), findsOneWidget); // Minecraft account row
    await t.tap(find.text('03 · KEYS'));
    await wait(t, 1500);
    // Any RenderFlex overflow would have failed the test by now.
  });
}
