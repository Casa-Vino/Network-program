import 'dart:convert';
import 'dart:io';

import 'discovery_beacon.dart';
import 'file_server.dart';

/// Pushes files to a drop-box device by streaming each one as a raw PUT body.
///
/// Resumable: before sending, it fetches the drop box's manifest and **skips
/// any file already present at the same size**, re-sending only missing or
/// partial ones (overwriting partials). So re-running after an interruption
/// resumes with no wasted re-sending.
///
/// Reports (filesDone, filesTotal, bytesSent). filesDone counts skipped files
/// too, so the counter reflects overall progress.
Future<void> pushFiles(
  ShareInfo target,
  List<SharedFile> files, {
  bool skipExisting = true,
  void Function(int done, int total, int bytes)? onProgress,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  var done = 0;
  var bytes = 0;
  try {
    // 1) Ask the drop box what it already has (name -> size).
    final existing = <String, int>{};
    if (skipExisting) {
      try {
        final req =
            await client.getUrl(Uri.parse('${target.baseUrl}/manifest.json'));
        final resp = await req.close();
        if (resp.statusCode == HttpStatus.ok) {
          final body = await resp.transform(utf8.decoder).join();
          final j = jsonDecode(body) as Map<String, dynamic>;
          j.forEach((k, v) {
            if (v is num) existing[k] = v.toInt();
          });
        } else {
          await resp.drain<void>();
        }
      } catch (_) {
        // No manifest (older drop box) — just send everything.
      }
    }

    // 2) Send what's missing/incomplete.
    for (final f in files) {
      final name = f.downloadName; // matches the drop box's saved filename
      if (skipExisting && existing[name] == f.size) {
        done++;
        onProgress?.call(done, files.length, bytes);
        continue;
      }
      final file = File(f.path);
      if (!await file.exists()) {
        done++;
        continue;
      }
      final uri = Uri.parse(
          '${target.baseUrl}/put?name=${Uri.encodeQueryComponent(name)}&overwrite=1');
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
