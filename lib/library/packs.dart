import 'dart:ui';

enum PackMark { none, vatra }

/// One build of a pack, as served by the website: the release (the pack
/// itself) or a child build such as dev or beta.
class PackBuild {
  const PackBuild({
    required this.slug,
    required this.name,
    required this.gitUrl,
    required this.gitBranch,
    this.version = '',
    this.isRelease = false,
    this.unlockedByKey = false,
    this.minecraftVersion = '',
    this.modLoader = '',
    this.loaderVersion = '',
  });

  final String slug;
  final String name;
  final String version;
  final bool isRelease;
  final bool unlockedByKey;
  final String gitUrl;
  final String gitBranch;
  final String minecraftVersion;
  final String modLoader;
  final String loaderVersion;

  /// What the BUILD selector shows, e.g. `RELEASE 1.2.0` or `DEV`.
  String get label => [name, if (version.isNotEmpty) version].join(' ').toUpperCase();

  factory PackBuild.fromJson(Map<String, dynamic> json) => PackBuild(
        slug: json['slug'] as String,
        name: json['name'] as String? ?? '',
        version: json['version'] as String? ?? '',
        isRelease: json['is_release'] as bool? ?? false,
        unlockedByKey: json['unlocked_by_key'] as bool? ?? false,
        gitUrl: json['git_url'] as String? ?? '',
        gitBranch: json['git_branch'] as String? ?? '',
        minecraftVersion: json['minecraft_version'] as String? ?? '',
        modLoader: json['mod_loader'] as String? ?? '',
        loaderVersion: json['loader_version'] as String? ?? '',
      );
}

/// A modpack "tape" on the rack. Built from the website's catalog; the
/// stats in brackets are slots for values the server doesn't send yet.
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
    this.builds = const [],
    this.iconUrl,
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
  final List<PackBuild> builds;
  final String? iconUrl;
  final String mods, size;
  final bool disabled;

  bool get hasLogo => mark != PackMark.none || iconUrl != null;

  PackBuild? buildFor(String? slug) {
    for (final b in builds) {
      if (b.slug == slug) return b;
    }
    return builds.isEmpty ? null : builds.first;
  }

  factory Pack.fromJson(Map<String, dynamic> json) {
    final slug = json['slug'] as String;
    final title = (json['name'] as String? ?? slug).toUpperCase();
    final builds = [
      for (final b in json['builds'] as List? ?? const []) PackBuild.fromJson(b as Map<String, dynamic>),
    ];
    final color = _parseHex(json['color'] as String?) ?? _fallbackColor(slug);
    final code = (json['code'] as String?)?.trim() ?? '';
    final status = (json['status'] as String?)?.trim() ?? '';
    final hasRelease = builds.any((b) => b.isRelease);
    return Pack(
      id: slug,
      code: code.isNotEmpty ? code.toUpperCase() : _codeFrom(slug),
      title: title,
      short: title.split(' ').last,
      mark: slug == 'vatra' || slug.startsWith('vatra-') ? PackMark.vatra : PackMark.none,
      color: color,
      ink: Color.lerp(const Color(0xFF000000), color, .1)!,
      status: status.isNotEmpty
          ? status.toUpperCase()
          : (hasRelease ? 'AVAILABLE' : 'KEY ACCESS'),
      tag: json['description'] as String? ?? '',
      feats: [for (final f in json['features'] as List? ?? const []) f as String],
      builds: builds,
      iconUrl: json['icon'] as String?,
    );
  }
}

Color? _parseHex(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

const _labelColors = [Color(0xFF39FF6A), Color(0xFFFFB000), Color(0xFF7FE7FF), Color(0xFFFF6A8A)];

Color _fallbackColor(String slug) => _labelColors[slug.codeUnits.fold(0, (a, b) => a + b) % _labelColors.length];

String _codeFrom(String slug) {
  final letters = slug.replaceAll(RegExp(r'[^a-zA-Z]'), '').toUpperCase();
  return letters.length <= 3 ? letters : letters.substring(0, 3);
}

/// Used to preview the media style in settings.
const samplePack = Pack(
  id: 'sample',
  code: 'SWP-01',
  title: 'PROJECT SWAMP',
  short: 'SWAMP',
  mark: PackMark.none,
  color: Color(0xFF39FF6A),
  ink: Color(0xFF06120A),
  status: 'FLAGSHIP',
);
