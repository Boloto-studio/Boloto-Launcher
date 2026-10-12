import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

Future<void> boot(WidgetTester t, [Map<String, Object> prefs = const {}, Size size = const Size(1360, 860)]) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  await t.pumpWidget(BolotoApp(settings: await AppSettings.load()));
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
