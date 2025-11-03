import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

enum LoadState { initial, downloading, downloaded, error, outdated }

const String currentVersion = '1.0.0'; // Replace with your actual version

Future<LoadState> checkModpackManifest(String folderPath) async {
  try {
    final manifestFile = File(p.join(folderPath, 'manifest.json'));

    if (!await manifestFile.exists()) {
      return LoadState.initial; // No modpack yet
    }

    final contents = await manifestFile.readAsString();
    final jsonData = json.decode(contents);

    if (jsonData is! Map || !jsonData.containsKey('version')) {
      return LoadState.error;
    }

    final manifestVersion = jsonData['version'];
    if (manifestVersion != currentVersion) {
      return LoadState.outdated;
    }

    return LoadState.downloaded;
  } catch (e) {
    print('Error reading manifest: $e');
    return LoadState.error;
  }
}
