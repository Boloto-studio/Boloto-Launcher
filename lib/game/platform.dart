import 'dart:ffi' show Abi;
import 'dart:io';

/// The bits of the host platform Mojang's metadata cares about.
class HostPlatform {
  const HostPlatform({required this.os, required this.arch});

  /// `windows`, `osx` or `linux` — the names used in Mojang "rules".
  final String os;

  /// `x86_64`, `arm64` or `x86`.
  final String arch;

  static HostPlatform get current {
    final abi = Abi.current();
    final os = Platform.isWindows ? 'windows' : (Platform.isMacOS ? 'osx' : 'linux');
    final arch = switch (abi) {
      Abi.windowsArm64 || Abi.macosArm64 || Abi.linuxArm64 => 'arm64',
      Abi.windowsIA32 || Abi.linuxIA32 => 'x86',
      _ => 'x86_64',
    };
    return HostPlatform(os: os, arch: arch);
  }

  bool get isWindows => os == 'windows';

  /// Separator between classpath entries.
  String get classpathSeparator => isWindows ? ';' : ':';

  /// Key in Mojang's Java runtime index (`all.json`).
  String get javaRuntimeKey => switch ((os, arch)) {
        ('windows', 'arm64') => 'windows-arm64',
        ('windows', 'x86') => 'windows-x86',
        ('windows', _) => 'windows-x64',
        ('osx', 'arm64') => 'mac-os-arm64',
        ('osx', _) => 'mac-os',
        ('linux', 'x86') => 'linux-i386',
        _ => 'linux',
      };

  /// Classifier used by old-style `natives` maps (`natives-windows`, …).
  String get nativesKey => switch (os) { 'osx' => 'osx', 'linux' => 'linux', _ => 'windows' };
}
