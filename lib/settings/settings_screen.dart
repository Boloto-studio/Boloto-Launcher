import 'package:flutter/material.dart';

import '../app/settings.dart';
import '../library/packs.dart';
import '../ui/crt.dart';
import '../ui/layout.dart';
import '../ui/media.dart';
import '../ui/motion.dart';
import '../ui/palette.dart';
import '../ui/widgets.dart';

enum _Section {
  display('01 · DISPLAY', 'PHOSPHOR · MEDIA · CRT', 'display.cfg'),
  launcher('02 · LAUNCHER', 'INSTANCES · MEMORY · JAVA', 'launcher.cfg');

  const _Section(this.title, this.blurb, this.file);
  final String title;
  final String blurb;
  final String file;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _Section _section = _Section.display;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final pal = context.pal;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SideRack(
          title: '/config',
          meta: '${_Section.values.length} SECTIONS',
          dir: 'DIR: ~/.boloto/config',
          note: 'Changes are written to disk the moment you make them. No save button, no regrets.',
          children: [
            for (final (i, s) in _Section.values.indexed)
              SelectFrame(
                selected: s == _section,
                onTap: () => setState(() => _section = s),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Reveal.type(
                      n: s.title.length,
                      d: 1.2 + i * .25,
                      child: Text(s.title, style: mono(13, weight: FontWeight.w700, ls: .06)),
                    ),
                    const SizedBox(height: 6),
                    Reveal.type(
                      n: s.blurb.length,
                      s: 16,
                      d: 1.45 + i * .25,
                      child: Text(s.blurb, style: mono(11, color: pal.dim)),
                    ),
                  ],
                ),
              ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CrtPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ScreenTopRow(path: '/etc/boloto → ${_section.file}', channel: 'CH-04 // CONFIG'),
                        const SizedBox(height: 14),
                        Expanded(
                          child: ScrollConfiguration(
                            behavior: const ScrollBehavior().copyWith(scrollbars: false),
                            child: SingleChildScrollView(
                              key: ValueKey(_section),
                              child: switch (_section) {
                                _Section.display => _DisplaySection(settings: settings),
                                _Section.launcher => _LauncherSection(settings: settings),
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(border: Border.all(color: pal.rule)),
                  child: Row(
                    children: [
                      const Led(LedState.on),
                      const SizedBox(width: 8),
                      Reveal.type(
                        n: 26,
                        d: 1.4,
                        child: Text('CONFIG // ${_section.file}'.toUpperCase(), style: mono(11, ls: .12)),
                      ),
                      const Spacer(),
                      Reveal.fade(
                        d: 1.7,
                        child: TermButton(label: 'Reset to defaults', onTap: settings.resetDefaults),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Section heading in the big VT font.
class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Reveal.type(n: text.length, s: 55, child: Text(text, style: vt(56, height: .9))),
      );
}

/// One label/description + control row, with a dashed rule above it.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.desc, required this.child, required this.index});
  final String label;
  final String desc;
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Reveal.fade(
      d: .2 + index * .12,
      child: CustomPaint(
        foregroundPainter: DashedBorderPainter(color: pal.rule, right: false, bottom: false, left: false),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Caption(label),
                    const SizedBox(height: 6),
                    Text(desc, style: mono(12, height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(width: 28),
              Expanded(child: Align(alignment: Alignment.centerLeft, child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of mutually exclusive [SelectFrame]s.
class _Choice<T> extends StatelessWidget {
  const _Choice({required this.values, required this.selected, required this.onPick, required this.builder});
  final List<T> values;
  final T selected;
  final ValueChanged<T> onPick;
  final Widget Function(T value) builder;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final v in values)
            SelectFrame(
              selected: v == selected,
              onTap: () => onPick(v),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: builder(v),
            ),
        ],
      );
}

class _DisplaySection extends StatelessWidget {
  const _DisplaySection({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading('DISPLAY'),
          _Row(
            index: 0,
            label: 'PHOSPHOR',
            desc: 'Tube colour for the whole launcher.',
            child: _Choice<Phosphor>(
              values: Phosphor.all,
              selected: settings.phosphor,
              onPick: (v) => settings.phosphor = v,
              builder: (p) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: p.color,
                      boxShadow: [BoxShadow(color: p.color.withValues(alpha: .7), blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(p.label, style: mono(13, ls: .08)),
                ],
              ),
            ),
          ),
          _Row(
            index: 1,
            label: 'MEDIA',
            desc: 'How packs are drawn on the rack and in the deck.',
            child: _Choice<MediaKind>(
              values: MediaKind.values,
              selected: settings.media,
              onPick: (v) => settings.media = v,
              builder: (m) => Column(
                children: [
                  SizedBox(
                    width: 150,
                    height: 96,
                    child: FittedBox(child: MediaView(kind: m, pack: packs.first)),
                  ),
                  const SizedBox(height: 10),
                  Text(m.name.toUpperCase(), style: mono(13, ls: .08)),
                ],
              ),
            ),
          ),
          _Row(
            index: 2,
            label: 'CRT EFFECTS',
            desc: 'Scanlines, rolling band, flicker and glow. Turn off if it bothers your eyes.',
            child: _Choice<bool>(
              values: const [true, false],
              selected: settings.crt,
              onPick: (v) => settings.crt = v,
              builder: (on) => Text(on ? 'ON' : 'OFF', style: mono(13, ls: .08)),
            ),
          ),
        ],
      );
}

class _LauncherSection extends StatefulWidget {
  const _LauncherSection({required this.settings});
  final AppSettings settings;

  @override
  State<_LauncherSection> createState() => _LauncherSectionState();
}

class _LauncherSectionState extends State<_LauncherSection> {
  late final _path = TextEditingController(text: widget.settings.instancesDir);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_LauncherSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pick up external changes (e.g. reset) without fighting the user's typing.
    if (!_focus.hasFocus && _path.text != widget.settings.instancesDir) {
      _path.text = widget.settings.instancesDir;
    }
  }

  @override
  void dispose() {
    _path.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final s = widget.settings;
    OutlineInputBorder border(Color c) =>
        OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: c));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('LAUNCHER'),
        _Row(
          index: 0,
          label: 'INSTANCES',
          desc: 'Where packs are installed. Leave empty for the default.',
          child: TextField(
            controller: _path,
            focusNode: _focus,
            onChanged: (v) => s.instancesDir = v,
            cursorColor: pal.ph,
            style: mono(13, ls: .04, color: pal.ph),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: kBg,
              hintText: defaultInstancesDir,
              hintStyle: mono(13, ls: .04, color: pal.dim),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              enabledBorder: border(pal.a(.5)),
              focusedBorder: border(pal.ph),
              hoverColor: pal.a(.06),
            ),
          ),
        ),
        _Row(
          index: 1,
          label: 'MEMORY',
          desc: 'RAM handed to the game. Big packs want 8 GB or more.',
          child: _Choice<int>(
            values: ramOptions,
            selected: s.ramGb,
            onPick: (v) => s.ramGb = v,
            builder: (gb) => Text('$gb GB', style: mono(13, ls: .08)),
          ),
        ),
        _Row(
          index: 2,
          label: 'JAVA',
          desc: 'The right runtime is fetched for each Minecraft version.',
          child: const TagChip('AUTO-MANAGED'),
        ),
      ],
    );
  }
}
