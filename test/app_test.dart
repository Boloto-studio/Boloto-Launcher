import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lib_boloto_launcher/api/launcher_api.dart';
import 'package:lib_boloto_launcher/app/settings.dart';
import 'package:lib_boloto_launcher/main.dart';
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
MockClient fakeServer() {
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
    final account = {'username': 'mavka', 'avatar': null, 'minecraft_username': null};
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
          'modpacks': [vatra(builds())],
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

Future<void> boot(WidgetTester t, [Map<String, Object> prefs = const {}, Size size = const Size(1360, 860)]) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final api = LauncherApi(client: fakeServer(), baseUrl: 'https://test.invalid');
  await t.pumpWidget(BolotoApp(settings: await AppSettings.load(), api: api));
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
    await wait(t, 4500);
    expect(find.text('GAME RUNNING'), findsOneWidget);

    await t.tap(find.text('STOP'));
    await wait(t, 100);
    await t.tap(find.text('EJECT'));
    await wait(t, 1500);
    expect(find.text('NO MEDIA'), findsOneWidget);
  });

  testWidgets('redeeming a key adds the dev build and loads it', (t) async {
    await boot(t);
    expect(find.text('NO MEDIA'), findsOneWidget);

    await t.tap(find.text('REDEEM KEY'));
    await wait(t, 500);
    await t.enterText(find.byType(TextField), 'nope');
    await t.tap(find.text('REDEEM').last);
    await wait(t, 300);
    expect(find.text('> THAT KEY IS NOT VALID.'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'DEV-KEY');
    await t.tap(find.text('REDEEM').last);
    await wait(t, 2800);

    // Dialog closed, Vatra loaded with the dev build picked.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('launcher.token'), 'tok');
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
    expect(find.text('SIGNED IN AS'), findsOneWidget);
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
    await boot(t, saved);
    final s = await AppSettings.load();
    expect(s.phosphor, Phosphor.amber);
    expect(s.crt, isFalse);
    expect(find.text(r'INSTANCES: D:\Games\Boloto'), findsOneWidget);
  });

  testWidgets('every screen fits the minimum window size', (t) async {
    await boot(t, const {'ui.media': 'floppy'}, const Size(1200, 780));
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
    // Any RenderFlex overflow would have failed the test by now.
  });
}
