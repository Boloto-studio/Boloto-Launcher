import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lib_boloto_launcher/game/downloader.dart';
import 'package:lib_boloto_launcher/game/forge.dart';
import 'package:lib_boloto_launcher/game/launch.dart';
import 'package:lib_boloto_launcher/game/maven.dart';
import 'package:lib_boloto_launcher/game/pack_sync.dart';
import 'package:lib_boloto_launcher/game/paths.dart';
import 'package:lib_boloto_launcher/game/platform.dart';
import 'package:lib_boloto_launcher/game/rules.dart';
import 'package:lib_boloto_launcher/game/vanilla.dart';
import 'package:lib_boloto_launcher/minecraft/microsoft_auth.dart';
import 'package:lib_boloto_launcher/minecraft/minecraft_account.dart';
import 'package:path/path.dart' as p;

const windows = HostPlatform(os: 'windows', arch: 'x86_64');
const linux = HostPlatform(os: 'linux', arch: 'x86_64');

void main() {
  group('maven', () {
    test('paths for plain, classifier and @ext coordinates', () {
      expect(MavenArtifact.parse('org.lwjgl:lwjgl:3.3.1').path, 'org/lwjgl/lwjgl/3.3.1/lwjgl-3.3.1.jar');
      expect(MavenArtifact.parse('net.minecraftforge:forge:1.20.1-47.3.0:client').path,
          'net/minecraftforge/forge/1.20.1-47.3.0/forge-1.20.1-47.3.0-client.jar');
      expect(MavenArtifact.parse('de.oceanlabs.mcp:mcp_config:1.20.1-20230612.114412:mappings@txt').path,
          'de/oceanlabs/mcp/mcp_config/1.20.1-20230612.114412/mcp_config-1.20.1-20230612.114412-mappings.txt');
      expect(MavenArtifact.parse('org.lwjgl:lwjgl:3.3.1:natives-windows').key, 'org.lwjgl:lwjgl:natives-windows');
    });
  });

  group('rules', () {
    final windowsOnly = [
      {'action': 'allow', 'os': {'name': 'windows'}},
    ];
    test('os rules', () {
      expect(rulesAllow(null, linux), isTrue);
      expect(rulesAllow(windowsOnly, windows), isTrue);
      expect(rulesAllow(windowsOnly, linux), isFalse);
      expect(
        rulesAllow([
          {'action': 'allow'},
          {'action': 'disallow', 'os': {'name': 'osx'}},
        ], linux),
        isTrue,
      );
    });

    test('feature-gated arguments are dropped, plain ones kept', () {
      final args = flattenArguments([
        '--username',
        r'${auth_player_name}',
        {
          'rules': [
            {'action': 'allow', 'features': {'is_demo_user': true}},
          ],
          'value': '--demo',
        },
        {'rules': windowsOnly, 'value': ['-XX:HeapDumpPath=x']},
      ], windows);
      expect(args, ['--username', r'${auth_player_name}', '-XX:HeapDumpPath=x']);
      expect(substitute(r'--username ${auth_player_name} ${unknown}', {'auth_player_name': 'Mavka'}),
          r'--username Mavka ${unknown}');
    });
  });

  group('libraries', () {
    test('1.19+ native artifacts are both on the classpath and extracted', () {
      final files = libraryFiles({
        'name': 'org.lwjgl:lwjgl:3.3.1:natives-windows',
        'downloads': {
          'artifact': {'path': 'org/lwjgl/lwjgl/3.3.1/lwjgl-3.3.1-natives-windows.jar', 'url': 'https://x/y.jar', 'sha1': 'abc', 'size': 1},
        },
        'rules': [
          {'action': 'allow', 'os': {'name': 'windows'}},
        ],
      }, windows);
      expect(files.single.isNative, isTrue);
      expect(files.single.onClasspath, isTrue);
    });

    test('old-style natives map is extracted only; rules can exclude the OS', () {
      final lib = {
        'name': 'org.lwjgl.lwjgl:lwjgl-platform:2.9.4',
        'natives': {'windows': r'natives-windows-${arch}', 'linux': 'natives-linux'},
        'downloads': {
          'classifiers': {
            'natives-windows-64': {'path': 'a/natives-windows-64.jar', 'url': 'https://x/w64.jar'},
            'natives-linux': {'path': 'a/natives-linux.jar', 'url': 'https://x/l.jar'},
          },
        },
      };
      final files = libraryFiles(lib, windows);
      expect(files.single.path, 'a/natives-windows-64.jar');
      expect(files.single.onClasspath, isFalse);
      expect(libraryFiles({...lib, 'rules': [{'action': 'allow', 'os': {'name': 'osx'}}]}, windows), isEmpty);
    });

    test('Forge libraries without a URL are expected to be produced locally', () {
      final files = libraryFiles({
        'name': 'net.minecraftforge:forge:1.20.1-47.3.0:client',
        'downloads': {
          'artifact': {'path': 'net/minecraftforge/forge/1.20.1-47.3.0/forge-1.20.1-47.3.0-client.jar', 'url': ''},
        },
      }, windows);
      expect(files.single.url, isNull);
    });
  });

  group('launch command', () {
    late Directory tmp;
    late LauncherPaths paths;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('boloto-test');
      paths = LauncherPaths(root: tmp.path, instancesDir: p.join(tmp.path, 'instances'));
      await File(paths.versionJar('1.20.1')).create(recursive: true);
    });
    tearDown(() => tmp.delete(recursive: true));

    final vanilla = {
      'id': '1.20.1',
      'type': 'release',
      'mainClass': 'net.minecraft.client.main.Main',
      'libraries': [
        {'name': 'org.ow2.asm:asm:9.3', 'downloads': {'artifact': {'path': 'org/ow2/asm/asm/9.3/asm-9.3.jar', 'url': 'u'}}},
        {'name': 'com.mojang:brigadier:1.1.8', 'downloads': {'artifact': {'path': 'com/mojang/brigadier/1.1.8/brigadier-1.1.8.jar', 'url': 'u'}}},
      ],
      'arguments': {
        'game': ['--username', r'${auth_player_name}', '--accessToken', r'${auth_access_token}', '--version', r'${version_name}'],
        'jvm': [r'-Djava.library.path=${natives_directory}', '-cp', r'${classpath}'],
      },
    };
    final forge = {
      'id': '1.20.1-forge-47.3.0',
      'inheritsFrom': '1.20.1',
      'mainClass': 'cpw.mods.bootstraplauncher.BootstrapLauncher',
      'libraries': [
        {'name': 'org.ow2.asm:asm:9.5', 'downloads': {'artifact': {'path': 'org/ow2/asm/asm/9.5/asm-9.5.jar', 'url': 'u'}}},
      ],
      'arguments': {
        'game': ['--launchTarget', 'forgeclient'],
        'jvm': [r'-DlibraryDirectory=${library_directory}', r'-DignoreList=forge-,${version_name}.jar'],
      },
    };

    test('merges vanilla + Forge: Forge main class, Forge libraries win, args substituted', () async {
      final cmd = await LaunchBuilder(paths: paths, host: windows).build(
        java: 'javaw.exe',
        vanilla: vanilla,
        loader: forge,
        session: const LaunchSession(username: 'Mavka_UA', uuid: 'u', accessToken: 'SECRET'),
        gameDir: paths.instance('vatra-dev'),
        nativesDir: 'N',
        assetIndex: '5',
        memoryGb: 8,
      );
      final args = cmd.arguments;
      expect(args.first, '-Xmx8G');
      final cp = args[args.indexOf('-cp') + 1].split(';');
      expect(cp.where((e) => e.contains('asm')).single, endsWith('asm-9.5.jar')); // Forge's newer asm wins
      expect(cp.last, paths.versionJar('1.20.1-forge-47.3.0')); // vanilla jar copied under Forge's id
      expect(File(paths.versionJar('1.20.1-forge-47.3.0')).existsSync(), isTrue);
      expect(args, contains('-DlibraryDirectory=${paths.libraries}'));
      expect(args, contains('-DignoreList=forge-,1.20.1-forge-47.3.0.jar'));
      final main = args.indexOf('cpw.mods.bootstraplauncher.BootstrapLauncher');
      expect(main, greaterThan(args.indexOf('-cp')));
      expect(args.sublist(main + 1), [
        '--username', 'Mavka_UA', '--accessToken', 'SECRET', '--version', '1.20.1-forge-47.3.0',
        '--launchTarget', 'forgeclient',
      ]);
      expect(cmd.workingDirectory, paths.instance('vatra-dev'));
      expect(cmd.describe('SECRET'), isNot(contains('SECRET')));
    });

    test('Forge processor args resolve {DATA} and [maven] references', () {
      final forgeInstaller = ForgeInstaller(paths: paths, downloader: Downloader(), host: windows);
      expect(forgeInstaller.resolveArg('{SIDE}', {'SIDE': 'client'}), 'client');
      expect(forgeInstaller.resolveArg('--in={MINECRAFT_JAR}', {'MINECRAFT_JAR': 'mc.jar'}), '--in=mc.jar');
      expect(forgeInstaller.resolveArg('[net.minecraft:client:1.20.1-20230612.114412:srg]', {}),
          paths.library('net/minecraft/client/1.20.1-20230612.114412/client-1.20.1-20230612.114412-srg.jar'));
      expect(() => forgeInstaller.resolveArg('{NOPE}', {}), throwsA(isA<GameException>()));
    });
  });

  group('pack sync', () {
    test('first sync: init, fetch the branch shallow, reset, pull LFS, install defaults', () async {
      final tmp = await Directory.systemTemp.createTemp('boloto-pack');
      addTearDown(() => tmp.delete(recursive: true));
      final dir = p.join(tmp.path, 'vatra-dev');
      final calls = <String>[];
      final sync = PackSync(
        paths: LauncherPaths(root: tmp.path, instancesDir: tmp.path),
        downloader: Downloader(),
        host: windows,
        run: (exe, args, {required workingDirectory, environment = const {}, log}) async {
          calls.add(args.join(' '));
          if (args.first == 'reset') {
            expect(environment['GIT_LFS_SKIP_SMUDGE'], '1');
            await File(p.join(dir, 'options.default.txt')).writeAsString('fov:90');
          }
        },
      );
      await sync.sync(
        git: const GitTools('git'),
        url: 'https://github.com/Boloto-studio/Vatra',
        branch: 'dev',
        dir: dir,
      );
      expect(calls, [
        'init --quiet',
        'remote add origin https://github.com/Boloto-studio/Vatra',
        'config core.longpaths true',
        'lfs install --local',
        'fetch --depth 1 --no-tags origin dev',
        'reset --hard FETCH_HEAD',
        'lfs pull',
      ]);
      expect(await File(p.join(dir, 'options.txt')).readAsString(), 'fov:90');

      // A player's own options.txt is never replaced.
      await File(p.join(dir, 'options.txt')).writeAsString('fov:70');
      await sync.installDefaults(dir);
      expect(await File(p.join(dir, 'options.txt')).readAsString(), 'fov:70');
    });
  });

  group('microsoft sign-in', () {
    http.Response j(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

    test('device code → Xbox → XSTS → Minecraft profile', () async {
      var polls = 0;
      final seen = <String>[];
      final auth = MicrosoftAuth(
        clientId: 'client-123',
        client: MockClient((req) async {
          seen.add(req.url.host + req.url.path);
          switch (req.url.path) {
            case '/consumers/oauth2/v2.0/devicecode':
              expect(req.bodyFields['scope'], 'XboxLive.signin offline_access');
              return j({'user_code': 'ABCD-EFGH', 'device_code': 'dev', 'verification_uri': 'https://www.microsoft.com/link', 'interval': 0, 'expires_in': 900});
            case '/consumers/oauth2/v2.0/token':
              polls++;
              if (polls == 1) return j({'error': 'authorization_pending'}, 400);
              return j({'access_token': 'ms-access', 'refresh_token': 'ms-refresh'});
            case '/user/authenticate':
              expect((jsonDecode(req.body) as Map)['Properties']['RpsTicket'], 'd=ms-access');
              return j({'Token': 'xbl', 'DisplayClaims': {'xui': [{'uhs': 'hash'}]}});
            case '/xsts/authorize':
              return j({'Token': 'xsts', 'DisplayClaims': {'xui': [{'uhs': 'hash'}]}});
            case '/authentication/login_with_xbox':
              expect((jsonDecode(req.body) as Map)['identityToken'], 'XBL3.0 x=hash;xsts');
              return j({'access_token': 'mc-token', 'expires_in': 86400});
            case '/minecraft/profile':
              expect(req.headers['Authorization'], 'Bearer mc-token');
              return j({'id': '069a79f444e94726a5befca90e38aaf5', 'name': 'Mavka_UA'});
          }
          return http.Response('?', 404);
        }),
      );
      final code = await auth.startDeviceCode();
      expect(code.userCode, 'ABCD-EFGH');
      final account = await auth.completeDeviceCode(code);
      expect(polls, 2);
      expect(account.name, 'Mavka_UA');
      expect(account.accessToken, 'mc-token');
      expect(account.refreshToken, 'ms-refresh');
      expect(account.isFresh, isTrue);
    });

    test('readable errors: no Xbox profile, unapproved app, no game', () async {
      Future<String> failWith(int xsts, int mc, int profile) async {
        final auth = MicrosoftAuth(
          clientId: 'c',
          client: MockClient((req) async => switch (req.url.path) {
                '/consumers/oauth2/v2.0/token' => j({'access_token': 'a', 'refresh_token': 'r'}),
                '/user/authenticate' => j({'Token': 'x', 'DisplayClaims': {'xui': [{'uhs': 'h'}]}}),
                '/xsts/authorize' => xsts == 200
                    ? j({'Token': 's', 'DisplayClaims': {'xui': [{'uhs': 'h'}]}})
                    : j({'XErr': 2148916233}, 401),
                '/authentication/login_with_xbox' => mc == 200 ? j({'access_token': 't'}) : j({}, mc),
                _ => profile == 200 ? j({'id': 'i', 'name': 'n'}) : j({}, profile),
              }),
        );
        try {
          await auth.refresh(MinecraftAccount(uuid: 'u', name: 'n', accessToken: 'a', expiresAt: DateTime(2000), refreshToken: 'r'));
          return 'ok';
        } on MinecraftAuthException catch (e) {
          return e.message;
        }
      }

      expect(await failWith(401, 200, 200), contains('no Xbox profile'));
      expect(await failWith(200, 403, 200), contains('aka.ms/mce-reviewappid'));
      expect(await failWith(200, 200, 404), contains('doesn\'t own Minecraft'));
      expect(await failWith(200, 200, 200), 'ok');
    });

    test('offline UUID matches Minecraft\'s', () {
      expect(offlineUuid('Notch'), 'b50ad385829d3141a2167e7d7539ba7f');
    });

    test('expired session refreshes and is stored; a dead refresh token signs out', () async {
      final store = MemoryAccountStore(jsonEncode(MinecraftAccount(
        uuid: 'u', name: 'Mavka_UA', accessToken: 'old', expiresAt: DateTime(2000), refreshToken: 'r',
      ).toJson()));
      var refreshWorks = true;
      final mc = MinecraftAccountController(
        store: store,
        auth: MicrosoftAuth(
          clientId: 'c',
          client: MockClient((req) async => switch (req.url.path) {
                '/consumers/oauth2/v2.0/token' => refreshWorks ? j({'access_token': 'a', 'refresh_token': 'r2'}) : j({'error': 'invalid_grant'}, 400),
                '/user/authenticate' || '/xsts/authorize' => j({'Token': 'x', 'DisplayClaims': {'xui': [{'uhs': 'h'}]}}),
                '/authentication/login_with_xbox' => j({'access_token': 'fresh', 'expires_in': 86400}),
                _ => j({'id': 'u', 'name': 'Mavka_UA'}),
              }),
        ),
      );
      await mc.load();
      expect((await mc.session()).accessToken, 'fresh');
      expect(store.value, contains('r2'));

      await store.write(jsonEncode(MinecraftAccount(uuid: 'u', name: 'n', accessToken: 'old', expiresAt: DateTime(2000), refreshToken: 'r').toJson()));
      await mc.load();
      refreshWorks = false;
      await expectLater(mc.session(), throwsA(isA<MinecraftAuthException>()));
      expect(mc.signedIn, isFalse);
      expect(store.value, isNull);
    });
  });
}
