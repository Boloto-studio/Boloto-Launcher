/// A Maven coordinate such as `net.minecraftforge:forge:1.20.1-47.3.0:client`
/// or `de.oceanlabs.mcp:mcp_config:1.20.1-20230612.114412:mappings@txt`.
class MavenArtifact {
  MavenArtifact._(this.group, this.artifact, this.version, this.classifier, this.extension);

  factory MavenArtifact.parse(String coordinate) {
    var coord = coordinate.trim();
    var ext = 'jar';
    final at = coord.indexOf('@');
    if (at >= 0) {
      ext = coord.substring(at + 1);
      coord = coord.substring(0, at);
    }
    final parts = coord.split(':');
    if (parts.length < 3) throw FormatException('Not a Maven coordinate: $coordinate');
    return MavenArtifact._(parts[0], parts[1], parts[2], parts.length > 3 ? parts[3] : null, ext);
  }

  final String group;
  final String artifact;
  final String version;
  final String? classifier;
  final String extension;

  /// `group:artifact` plus classifier — two libraries with the same key are
  /// the same library in different versions.
  String get key => classifier == null ? '$group:$artifact' : '$group:$artifact:$classifier';

  /// Relative path inside a Maven repository / the libraries folder, always
  /// with forward slashes.
  String get path {
    final file = classifier == null ? '$artifact-$version.$extension' : '$artifact-$version-$classifier.$extension';
    return '${group.replaceAll('.', '/')}/$artifact/$version/$file';
  }

  @override
  String toString() => classifier == null ? '$group:$artifact:$version' : '$group:$artifact:$version:$classifier';
}
