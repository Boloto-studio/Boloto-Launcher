import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app/settings.dart';
import 'shell/shell.dart';
import 'ui/palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'Boloto Launcher',
      size: Size(1360, 860),
      minimumSize: Size(1200, 780),
      center: true,
      backgroundColor: kBg,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(BolotoApp(settings: settings));
}

class BolotoApp extends StatelessWidget {
  const BolotoApp({super.key, required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: settings,
      child: MaterialApp(
        title: 'Boloto Launcher',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: kPlex,
          scaffoldBackgroundColor: kBg,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        builder: (context, child) => _PaletteHost(child: child!),
        home: const Shell(),
      ),
    );
  }
}

/// Eases phosphor changes across the whole UI and sets the base text style.
class _PaletteHost extends StatelessWidget {
  const _PaletteHost({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: settings.phosphor.color),
      duration: const Duration(milliseconds: 350),
      builder: (context, ph, _) {
        final pal = Palette(ph!, crt: settings.crt);
        return PaletteScope(
          palette: pal,
          child: Theme(
            data: Theme.of(context).copyWith(
              hoverColor: pal.a(.12),
              focusColor: pal.a(.12),
              textSelectionTheme: TextSelectionThemeData(
                cursorColor: pal.ph,
                selectionColor: pal.a(.3),
                selectionHandleColor: pal.ph,
              ),
            ),
            child: DefaultTextStyle(
              style: mono(13, color: pal.ph, shadows: pal.crtShadow),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
