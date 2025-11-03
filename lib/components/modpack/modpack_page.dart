import 'package:flutter/material.dart';
import 'package:lib_boloto_launcher/theme/boloto_theme.dart';
import 'dart:ui';
import 'package:lib_boloto_launcher/components/modpack/patch-notes-section.dart';
import 'package:lib_boloto_launcher/pages.dart';
import 'package:lib_boloto_launcher/helpers/shared_preferences.dart';
import 'package:lib_boloto_launcher/helpers/version_check.dart';

class ModpackData {
  final PageType page;
  final String title;
  final String description;
  final String logoPath;
  final String bgPath;

  ModpackData({
    required this.page,
    required this.title,
    required this.description,
    required this.logoPath,
    required this.bgPath,
  });
}

final List<ModpackData> modpacks = [
  ModpackData(
    page: PageType.echoes,
    title: "Echoes Untamed",
    description:
        "A thrilling adventure awaits in Echoes Untamed. Explore vast worlds, conquer challenges, and uncover secrets. Join the journey today!",
    logoPath: "assets/images/echoes_logo.png",
    bgPath: "assets/images/echoes_bg.png",
  ),
];

class ModpackPage extends StatefulWidget {
  final PageType page;

  const ModpackPage({super.key, required this.page});

  @override
  State<ModpackPage> createState() => _ModpackPageState();
}

class _ModpackPageState extends State<ModpackPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;

  String packPath = '';
  LoadState loadState = LoadState.initial;
  int hoursPlayed = 0;
  ElevatedButton actionButton = ElevatedButton.icon(
    onPressed: () {},
    icon: Icon(Icons.play_arrow),
    label: Text("Loading..."),
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
    ),
  );

  ModpackData get modpack =>
      modpacks.firstWhere((modpack) => modpack.page == widget.page);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    _initPreferences();
  }

  void _updateLoadState({LoadState? state}) async {
    LoadState newState;
    if (state != null) {
      newState = state;
    } else {
      newState = await checkModpackManifest(packPath);
    }
    print('Load state updated: $newState');
    setState(() {
      if (newState == LoadState.downloaded) {
        actionButton = ElevatedButton.icon(
          onPressed: () {},
          icon: Icon(Icons.play_arrow),
          label: Text("Play"),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 32.0,
              vertical: 16.0,
            ),
          ),
        );
      } else if (newState == LoadState.outdated) {
        print("Outdated modpack detected");
        actionButton = ElevatedButton.icon(
          onPressed: () {},
          icon: Icon(Icons.download),
          label: Text("Update"),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 32.0,
              vertical: 16.0,
            ),
          ),
        );
      } else if (newState == LoadState.initial) {
        print("Initial state, no modpack found");
        actionButton = ElevatedButton.icon(
          onPressed: () {},
          icon: Icon(Icons.download),
          label: Text("Install"),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 32.0,
              vertical: 16.0,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Error loading modpack. Please check your installation path or try re-downloading the modpack.',
              style: TextStyle(color: BolotoTheme.background),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            backgroundColor: BolotoTheme.textOnDark,
            showCloseIcon: true,
          ),
        );
        actionButton = ElevatedButton.icon(
          onPressed: () {},
          icon: Icon(Icons.error),
          label: Text("Re-Install"),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 32.0,
              vertical: 16.0,
            ),
          ),
        );
      }
      loadState = newState;
    });
  }

  Future<void> _initPreferences() async {
    final preferences = await SharedPreferencesHelper.getInstance();
    final loadedPackPath = preferences.getString(PrefKeys.packPath) ?? '';
    final loadedHoursPlayed = preferences.getInt(PrefKeys.hoursPlayed) ?? 0;
    setState(() {
      packPath = loadedPackPath;
      hoursPlayed = loadedHoursPlayed;
    });
    _updateLoadState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(32),
        bottomLeft: Radius.circular(32),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _scaleAnim,
              builder: (context, child) {
                return Transform.scale(scale: _scaleAnim.value, child: child);
              },
              child: Image.asset(
                'assets/images/echoes_bg.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Vignette overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: const [
                    Color.fromRGBO(0, 0, 0, 0.0),
                    Color.fromRGBO(0, 0, 0, 0.55),
                  ],
                  stops: const [0.6, 1.0],
                ),
              ),
            ),
          ),
          // Your foreground content
          Padding(
            padding: const EdgeInsets.all(50.0),
            child: Column(
              children: [
                // Top area with logo
                Align(
                  alignment: Alignment.topLeft,
                  child: Image.asset(
                    'assets/images/echoes_logo.png',
                    height: 200,
                  ),
                ),
                const SizedBox(height: 20),

                // Spacer to push play/info to bottom
                Expanded(child: Container()),

                // Bottom row: play + info + updates
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Play/info/description
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        loadState == LoadState.downloaded
                            ? ElevatedButton.icon(
                                onPressed: () {},
                                icon: Icon(Icons.play_arrow),
                                label: Text("Play"),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0,
                                    vertical: 16.0,
                                  ),
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: () {},
                                icon: Icon(Icons.download),
                                label: Text("Install"),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0,
                                    vertical: 16.0,
                                  ),
                                ),
                              ),
                        const SizedBox(height: 8),
                        Text("Odessa Server · 🟢 Online"),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 500,
                          child: hoursPlayed < 10
                              ? Text(
                                  modpack.description,
                                  style: TextStyle(
                                    color: BolotoTheme.textOnDark,
                                    fontSize: 16,
                                  ),
                                )
                              : Text(
                                  "Played for $hoursPlayed hours.",
                                  style: TextStyle(
                                    color: BolotoTheme.textOnDark,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ],
                    ),

                    Spacer(),

                    // Patch notes link
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 300),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: 300,
                            color: BolotoTheme.background.withOpacity(0.3),
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.update,
                                      color: BolotoTheme.textOnDark,
                                    ),
                                    SizedBox(width: 15),
                                    Text(
                                      "Recent Updates",
                                      style: TextStyle(fontSize: 18),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 15),
                                PatchNotesSection(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
