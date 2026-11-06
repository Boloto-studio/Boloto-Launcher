import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Thrown when installing or launching fails; [message] is shown to players.
class GameException implements Exception {
  const GameException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Lets the player stop a long install.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const GameException('Cancelled.');
  }
}

class DownloadTask {
  const DownloadTask({required this.url, required this.path, this.sha1, this.size});
  final String url;
  final String path;
  final String? sha1;
  final int? size;
}

typedef ProgressCallback = void Function(int done, int total);

/// Downloads files in parallel into place, skipping ones already present.
///
/// Files are written to `<path>.part` and renamed when complete (and, when a
/// SHA-1 is known, verified), so an interrupted download never leaves a
/// truncated file that later looks finished. Existing files are trusted when
/// their size matches; hashing hundreds of MB of assets on every launch
/// would make starting the game slow.
class Downloader {
  Downloader({http.Client? client, this.concurrency = 12, this.retries = 3}) : _client = client ?? http.Client();

  final http.Client _client;
  final int concurrency;
  final int retries;

  Future<void> downloadAll(
    List<DownloadTask> tasks, {
    ProgressCallback? onProgress,
    CancelToken? cancel,
  }) async {
    // Same file listed twice (it happens in Forge + vanilla library lists).
    final unique = {for (final t in tasks) t.path: t}.values.toList();
    final todo = unique.where((t) => !_isPresent(t)).toList();
    final total = unique.length;
    var done = total - todo.length;
    onProgress?.call(done, total);
    if (todo.isEmpty) return;

    var next = 0;
    Future<void> worker() async {
      while (true) {
        cancel?.throwIfCancelled();
        if (next >= todo.length) return;
        final task = todo[next++];
        await download(task, cancel: cancel);
        done++;
        onProgress?.call(done, total);
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  }

  bool _isPresent(DownloadTask t) {
    final f = File(t.path);
    if (!f.existsSync()) return false;
    return t.size == null || f.lengthSync() == t.size;
  }

  /// Downloads one file (with retries), verifying SHA-1 when known.
  Future<void> download(DownloadTask task, {CancelToken? cancel}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= retries; attempt++) {
      cancel?.throwIfCancelled();
      try {
        await _downloadOnce(task);
        return;
      } on GameException {
        rethrow;
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
    throw GameException('Download failed: ${task.url} ($lastError)');
  }

  Future<void> _downloadOnce(DownloadTask task) async {
    final target = File(task.path);
    await target.parent.create(recursive: true);
    final part = File('${task.path}.part');
    final response = await _client.send(http.Request('GET', Uri.parse(task.url)));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(task.url));
    }
    final digestSink = _DigestSink();
    final hasher = sha1.startChunkedConversion(digestSink);
    final out = part.openWrite();
    try {
      await for (final chunk in response.stream) {
        out.add(chunk);
        hasher.add(chunk);
      }
    } finally {
      await out.close();
    }
    hasher.close();
    if (task.sha1 != null && digestSink.value.toString() != task.sha1!.toLowerCase()) {
      await part.delete();
      throw StateError('Checksum mismatch for ${task.url}');
    }
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
  }

  Future<String> getText(String url) async {
    final r = await _client.get(Uri.parse(url));
    if (r.statusCode != 200) throw GameException('Could not fetch $url (HTTP ${r.statusCode}).');
    return r.body;
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// SHA-1 of a file on disk, as lowercase hex.
Future<String> sha1OfFile(String path) async => (await sha1.bind(File(path).openRead()).first).toString();

/// SHA-256 of a file on disk, as lowercase hex.
Future<String> sha256OfFile(String path) async => (await sha256.bind(File(path).openRead()).first).toString();
