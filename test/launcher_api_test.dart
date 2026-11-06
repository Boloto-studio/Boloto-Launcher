import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lib_boloto_launcher/api/launcher_api.dart';
import 'package:lib_boloto_launcher/library/packs.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response reply(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parses the catalog and only sends a token once it has one', () async {
    final seen = <String?>[];
    final api = LauncherApi(
      baseUrl: 'https://test.invalid',
      client: MockClient((req) async {
        seen.add(req.headers['Authorization']);
        return reply({
          'modpacks': [
            {
              'slug': 'vatra',
              'name': 'Vatra',
              'description': 'desc',
              'code': '',
              'status': '',
              'color': '#FFB000',
              'features': ['A', 'B'],
              'icon': null,
              'builds': [
                {
                  'slug': 'vatra-dev',
                  'name': 'Dev',
                  'version': '0.4',
                  'is_release': false,
                  'unlocked_by_key': true,
                  'git_url': 'https://github.com/boloto-studio/vatra',
                  'git_branch': 'dev',
                },
              ],
            },
          ],
        });
      }),
    );

    final packs = await api.fetchCatalog();
    expect(seen, [null]);
    final p = packs.single;
    expect(p.id, 'vatra');
    expect(p.title, 'VATRA');
    expect(p.code, 'VAT');
    expect(p.status, 'KEY ACCESS'); // no release build visible
    expect(p.color, const Color(0xFFFFB000));
    expect(p.mark, PackMark.vatra);
    expect(p.feats, ['A', 'B']);
    expect(p.builds.single.label, 'DEV 0.4');
    expect(p.builds.single.gitBranch, 'dev');

    SharedPreferences.setMockInitialValues({'launcher.token': 'abc'});
    await api.fetchCatalog();
    expect(seen.last, 'Bearer abc');
  });

  test('redeem registers, retries once on an unknown token, and surfaces errors', () async {
    SharedPreferences.setMockInitialValues({'launcher.token': 'stale'});
    var registrations = 0;
    final api = LauncherApi(
      baseUrl: 'https://test.invalid',
      client: MockClient((req) async {
        if (req.url.path.endsWith('/clients/')) {
          registrations++;
          return reply({'token': 'fresh', 'client_id': 2}, 201);
        }
        if (req.headers['Authorization'] != 'Bearer fresh') {
          return reply({'error': {'code': 'unauthorized', 'message': 'nope'}}, 401);
        }
        if (jsonDecode(req.body)['code'] == 'USED') {
          return reply({'error': {'code': 'key_used_up', 'message': 'That key has already been used.'}}, 409);
        }
        return reply({
          'already_redeemed': false,
          'unlocked': {'slug': 'vatra', 'name': 'Vatra'},
          'modpack': {'slug': 'vatra', 'name': 'Vatra', 'builds': []},
        });
      }),
    );

    final result = await api.redeemKey('ABCDE');
    expect(result.buildSlug, 'vatra');
    expect(registrations, 1);
    expect((await SharedPreferences.getInstance()).getString('launcher.token'), 'fresh');

    await expectLater(
      api.redeemKey('USED'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'key_used_up')),
    );
    expect(registrations, 1);
  });

  test('network failures become ApiException', () async {
    final api = LauncherApi(
      baseUrl: 'https://test.invalid',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(api.fetchCatalog(), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')));
  });

  test('sign in stores the new token and sends the old one', () async {
    SharedPreferences.setMockInitialValues({'launcher.token': 'anon'});
    String? sentWith;
    final api = LauncherApi(
      baseUrl: 'https://test.invalid',
      client: MockClient((req) async {
        if (req.url.path.endsWith('/auth/login/')) {
          sentWith = req.headers['Authorization'];
          return reply({
            'token': 'acct',
            'account': {'username': 'mavka', 'avatar': null, 'minecraft_username': 'Mavka_UA'},
          });
        }
        if (req.url.path.endsWith('/auth/me/')) {
          return req.headers['Authorization'] == 'Bearer acct'
              ? reply({'account': {'username': 'mavka'}})
              : reply({'error': {'code': 'unauthorized', 'message': 'Unknown launcher.'}}, 401);
        }
        return reply({'account': null});
      }),
    );

    final account = await api.signIn('mavka', 'pisnya');
    expect(sentWith, 'Bearer anon');
    expect(account.minecraftUsername, 'Mavka_UA');
    expect((await SharedPreferences.getInstance()).getString('launcher.token'), 'acct');
    expect((await api.fetchAccount())?.username, 'mavka');

    // A token the server no longer knows is dropped.
    SharedPreferences.setMockInitialValues({'launcher.token': 'stale'});
    expect(await api.fetchAccount(), isNull);
    expect((await SharedPreferences.getInstance()).getString('launcher.token'), isNull);
  });

  test('fetchAccount makes no request without a token', () async {
    final api = LauncherApi(
      baseUrl: 'https://test.invalid',
      client: MockClient((_) async => fail('should not be called')),
    );
    expect(await api.fetchAccount(), isNull);
  });

  test('a bare 404 says the site needs updating', () async {
    final api = LauncherApi(
      baseUrl: 'https://boloto.studio',
      client: MockClient((_) async => http.Response('<h1>Not Found</h1>', 404)),
    );
    await expectLater(
      api.signIn('mavka', 'pisnya'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'not_supported')
          .having((e) => e.message, 'message', contains('boloto.studio'))),
    );
    expect(api.registerUrl.toString(), 'https://boloto.studio/frogs/register/');
  });

  test('account parses the mini profile and tolerates older servers', () {
    final full = Account.fromJson({
      'username': 'mavka',
      'display_name': 'Lisova Mavka',
      'avatar': 'https://cdn.invalid/a.png',
      'minecraft_username': 'Mavka_UA',
      'bio': '  Forest spirit.  ',
      'tier': 'Frog',
      'location': '',
      'member_since': '2026-09-14',
      'friends_count': 3,
      'unlocked_count': 1,
      'profile_url': 'https://boloto.studio/frogs/profile/42/',
    });
    expect(full.displayName, 'Lisova Mavka');
    expect(full.bio, 'Forest spirit.');
    expect(full.location, isNull); // blank → null
    expect(full.memberSince, DateTime(2026, 9, 14));
    expect(full.friendsCount, 3);
    expect(full.profileUrl.toString(), 'https://boloto.studio/frogs/profile/42/');

    final old = Account.fromJson({'username': 'mavka', 'avatar': null, 'minecraft_username': null});
    expect(old.displayName, 'mavka');
    expect(old.profileUrl, isNull);
    expect(old.memberSince, isNull);
    expect(old.unlockedCount, 0);
  });
}
