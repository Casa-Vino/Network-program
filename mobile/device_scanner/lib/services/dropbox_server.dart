import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'net_util.dart';

/// A receive-side "drop box": an HTTP server that accepts file uploads and
/// saves them into Downloads/DeviceScanner/Inbox. Senders (this app, or any
/// browser via the served form) push files with:
///   PUT /<token>/put?name=<filename>   (raw body = file bytes)
///
/// Pair it with a ShareBeacon advertising role "dropbox" so senders can find
/// it by name.
class DropBoxServer {
  HttpServer? _server;
  String token = '';
  Directory? inbox;

  /// Number of files received this session (for live UI).
  final ValueNotifier<int> received = ValueNotifier<int>(0);

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  Future<void> start({int preferredPort = 8081}) async {
    token = _token();
    received.value = 0;
    final base = await downloadsDir();
    inbox = Directory('${base.path}/DeviceScanner/Inbox');
    await inbox!.create(recursive: true);
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort,
          shared: true);
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    }
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final segs = req.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    try {
      if (segs.isEmpty || segs[0] != token) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
      if (req.method == 'GET' && segs.length == 1) {
        _serveForm(res);
        return;
      }
      if (req.method == 'GET' &&
          segs.length == 2 &&
          segs[1] == 'manifest.json') {
        await _serveManifest(res);
        return;
      }
      if ((req.method == 'PUT' || req.method == 'POST') &&
          segs.length == 2 &&
          segs[1] == 'put') {
        await _receiveFile(req);
        return;
      }
      res.statusCode = HttpStatus.notFound;
      await res.close();
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  /// Lists files already in the Inbox (basename -> size) so a sender can skip
  /// what's already fully received (resumable push).
  Future<void> _serveManifest(HttpResponse res) async {
    final map = <String, int>{};
    try {
      if (inbox != null && await inbox!.exists()) {
        await for (final e in inbox!.list(followLinks: false)) {
          if (e is File) {
            final base = e.path.split(RegExp(r'[/\\]')).last;
            map[base] = await e.length();
          }
        }
      }
    } catch (_) {}
    res.headers.contentType = ContentType('application', 'json');
    res.write(jsonEncode(map));
    await res.close();
  }

  Future<void> _receiveFile(HttpRequest req) async {
    final res = req.response;
    final raw = req.uri.queryParameters['name'] ??
        'file-${DateTime.now().millisecondsSinceEpoch}';
    final name = _safeName(raw);
    // overwrite=1 (used by resumable push) replaces a partial file in place;
    // otherwise avoid clobbering by picking a unique name.
    final overwrite = req.uri.queryParameters['overwrite'] == '1';
    final target = overwrite
        ? '${inbox!.path}/$name'
        : await _uniquePath('${inbox!.path}/$name');

    final out = File(target).openWrite();
    var total = 0;
    try {
      await for (final chunk in req) {
        out.add(chunk);
        total += chunk.length;
      }
      await out.flush();
    } finally {
      await out.close();
    }

    received.value = received.value + 1;
    res.statusCode = HttpStatus.ok;
    res.headers.contentType = ContentType('application', 'json');
    res.write('{"ok":true,"bytes":$total}');
    await res.close();
  }

  void _serveForm(HttpResponse res) {
    final html = '''
<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Drop files to device</title>
<style>
  body{font-family:system-ui,sans-serif;max-width:640px;margin:40px auto;padding:0 16px;}
  input{font-size:1rem;} button{font-size:1.05rem;padding:.7rem 1.1rem;border-radius:8px;
    border:0;background:#0E8388;color:#fff;cursor:pointer;margin-top:12px;}
  #s{margin-top:16px;color:#555;}
</style></head><body>
<h1>Send files to this device</h1>
<p>Pick files and upload — they land in the device's Inbox.</p>
<input type="file" id="f" multiple>
<br><button onclick="up()">Upload</button>
<div id="s"></div>
<script>
async function up(){
  const files=document.getElementById('f').files, s=document.getElementById('s');
  if(!files.length){s.textContent='Choose files first.';return;}
  for(let i=0;i<files.length;i++){
    s.textContent='Uploading '+(i+1)+'/'+files.length+': '+files[i].name;
    try{ await fetch('/$token/put?name='+encodeURIComponent(files[i].name),
        {method:'PUT',body:files[i]}); }
    catch(e){ s.textContent='Failed on '+files[i].name; return; }
  }
  s.textContent='Done — '+files.length+' file(s) uploaded.';
}
</script>
</body></html>''';
    res.headers.contentType = ContentType.html;
    res.write(html);
    res.close();
  }

  String _safeName(String n) {
    n = n.replaceAll('\\', '/').replaceAll('..', '');
    n = n.replaceAll(RegExp(r'^/+'), '').replaceAll('/', '_');
    return n.isEmpty ? 'file' : n;
  }

  Future<String> _uniquePath(String path) async {
    if (!await File(path).exists()) return path;
    final slash = path.lastIndexOf('/');
    final dot = path.lastIndexOf('.');
    final hasExt = dot > slash;
    final stem = hasExt ? path.substring(0, dot) : path;
    final ext = hasExt ? path.substring(dot) : '';
    var i = 1;
    while (await File('$stem ($i)$ext').exists()) {
      i++;
    }
    return '$stem ($i)$ext';
  }

  static String _token() {
    const c = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(5, (_) => c[r.nextInt(c.length)]).join();
  }
}
