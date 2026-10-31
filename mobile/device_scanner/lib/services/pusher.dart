import 'dart:io';

import 'discovery_beacon.dart';
import 'file_server.dart';

/// Pushes files to a drop-box device by streaming each one as a raw PUT body.
/// Reports (filesDone, filesTotal, bytesSent) as it goes.
Future<void> pushFiles(
  ShareInfo target,
  List<SharedFile> files, {
  void Function(int done, int total, int bytes)? onProgress,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  var done = 0;
  var bytes = 0;
  try {
    for (final f in files) {
      final uri = Uri.parse(
          '${target.baseUrl}/put?name=${Uri.encodeQueryComponent(f.rel)}');
      final file = File(f.path);
      if (!await file.exists()) {
        done++;
        continue;
      }
      final req = await client.putUrl(uri);
      req.headers.contentType = ContentType('application', 'octet-stream');
      req.headers.contentLength = await file.length();
      await req.addStream(file.openRead().map((chunk) {
        bytes += chunk.length;
        onProgress?.call(done, files.length, bytes);
        return chunk;
      }));
      final resp = await req.close();
      await resp.drain<void>();
      if (resp.statusCode != HttpStatus.ok) {
        throw 'Upload of ${f.rel} failed (HTTP ${resp.statusCode}).';
      }
      done++;
      onProgress?.call(done, files.length, bytes);
    }
  } finally {
    client.close(force: true);
  }
}
