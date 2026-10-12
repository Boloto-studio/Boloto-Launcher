import 'dart:ui';

enum PackMark { none, vatra }

/// A modpack "tape" on the rack. Static placeholder data for now — the
/// stats in brackets are slots for real values from the CDN manifest.
class Pack {
  const Pack({
    required this.id,
    required this.code,
    required this.title,
    required this.short,
    required this.mark,
    required this.color,
    required this.ink,
    required this.status,
    this.tag = '',
    this.feats = const [],
    this.mc = '[MC VERSION]',
    this.loader = '[LOADER]',
    this.mods = '[MOD COUNT]',
    this.size = '[SIZE]',
    this.disabled = false,
  });

  final String id;
  final String code;
  final String title;
  final String short;
  final PackMark mark;
  final Color color;
  final Color ink;
  final String status;
  final String tag;
  final List<String> feats;
  final String mc, loader, mods, size;
  final bool disabled;

  bool get hasLogo => mark != PackMark.none;
}

const packs = <Pack>[
  Pack(
    id: 'swamp',
    code: 'SWP-01',
    title: 'PROJECT SWAMP',
    short: 'SWAMP',
    mark: PackMark.none,
    color: Color(0xFF39FF6A),
    ink: Color(0xFF06120A),
    status: 'FLAGSHIP',
    tag: 'Survival systems, uncanny folklore and hostile wetlands. Mud on your boots, mystery in the fog.',
    feats: ['Survival systems', 'Uncanny folklore', 'Hostile wetlands'],
  ),
  Pack(
    id: 'vatra',
    code: 'VTR-02',
    title: 'VATRA',
    short: 'VATRA',
    mark: PackMark.vatra,
    color: Color(0xFFFFB000),
    ink: Color(0xFF1A1000),
    status: 'IN DEVELOPMENT',
    tag: 'A Carpathian fantasy RPG rooted in Hutsul mythology. Build villages, lead squads, survive what wakes in the mountains.',
    feats: ['Village building & hired squads', 'Souls-like combat & bosses', 'Steam-era engineering', 'Magic & dragons'],
  ),
  Pack(
    id: 'blank',
    code: 'NO-SIG',
    title: 'BLANK',
    short: 'BLANK',
    mark: PackMark.none,
    color: Color(0xFF16211A),
    ink: Color(0xFF8FB59A),
    status: 'NEXT TRANSMISSION PENDING',
    disabled: true,
  ),
];
