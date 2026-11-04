import 'platform.dart';

/// Evaluates Mojang's `rules` arrays (on libraries and arguments).
///
/// No rules means allowed. Otherwise the last matching rule wins; a rule
/// matches when its `os` and `features` conditions match.
bool rulesAllow(List<dynamic>? rules, HostPlatform host, {Map<String, bool> features = const {}}) {
  if (rules == null || rules.isEmpty) return true;
  var allowed = false;
  for (final raw in rules) {
    final rule = raw as Map<String, dynamic>;
    if (!_matches(rule, host, features)) continue;
    allowed = rule['action'] == 'allow';
  }
  return allowed;
}

bool _matches(Map<String, dynamic> rule, HostPlatform host, Map<String, bool> features) {
  final os = rule['os'] as Map<String, dynamic>?;
  if (os != null) {
    final name = os['name'] as String?;
    if (name != null && name != host.os) return false;
    final arch = os['arch'] as String?;
    if (arch != null && !_archMatches(arch, host.arch)) return false;
  }
  final wanted = rule['features'] as Map<String, dynamic>?;
  if (wanted != null) {
    for (final e in wanted.entries) {
      if ((features[e.key] ?? false) != e.value) return false;
    }
  }
  return true;
}

bool _archMatches(String rule, String hostArch) => switch (rule) {
      'x86' => hostArch == 'x86',
      'x86_64' || 'amd64' => hostArch == 'x86_64',
      'arm64' || 'aarch64' => hostArch == 'arm64',
      _ => false,
    };

/// Flattens a modern `arguments.game` / `arguments.jvm` list: plain strings
/// pass through, `{rules, value}` objects are kept when their rules allow.
List<String> flattenArguments(List<dynamic>? args, HostPlatform host, {Map<String, bool> features = const {}}) {
  final out = <String>[];
  for (final a in args ?? const []) {
    if (a is String) {
      out.add(a);
    } else if (a is Map<String, dynamic>) {
      if (!rulesAllow(a['rules'] as List<dynamic>?, host, features: features)) continue;
      final value = a['value'];
      if (value is String) {
        out.add(value);
      } else if (value is List) {
        out.addAll(value.cast<String>());
      }
    }
  }
  return out;
}

/// Replaces `${name}` placeholders. Unknown placeholders are left as-is.
String substitute(String template, Map<String, String> values) =>
    template.replaceAllMapped(RegExp(r'\$\{([a-zA-Z0-9_]+)\}'), (m) => values[m[1]] ?? m[0]!);
