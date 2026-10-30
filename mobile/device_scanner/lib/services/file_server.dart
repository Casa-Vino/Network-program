import 'dart:async';
import 'dart:io';
import 'dart:math';

/// A file to offer over the local web server.
class SharedFile {
  SharedFile({required this.name, required this.path, required this.size});
  final String name;
  final String path;
  final int size;
}

/// A tiny HTTP server that serves a chosen set of the phone's files to any
/// browser on the same Wi-Fi — a no-install way to copy files off the phone
/// when USB/MTP won't cooperate.
///
/// Access is gated by a random token in the URL path (LAN-only convenience,
/// not strong security). Stop the server when the transfer is done.
class FileServer {
  HttpServer? _server;
  String token = '';
  List<SharedFile> files = [];

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  Future<void> start(List<SharedFile> files, {int preferredPort = 8080}) async {
    this.files = files;
    token = _randomToken();
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort,
          shared: true);
    } on SocketException {
      // Port busy — take any free port.
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
    // Drop empty segments so a trailing slash (/token/) still matches the
    // index route; browsers routinely add or keep it.
    final segs = req.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    try {
      if (segs.isEmpty || segs[0] != token) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
      if (segs.length == 1) {
        _serveIndex(res);
        return;
      }
      if (segs.length == 3 && segs[1] == 'file') {
        final idx = int.tryParse(segs[2]);
        if (idx != null && idx >= 0 && idx < files.length) {
          await _serveFile(res, files[idx]);
          return;
        }
      }
      res.statusCode = HttpStatus.notFound;
      await res.close();
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  void _serveIndex(HttpResponse res) {
    final rows = StringBuffer();
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      rows.writeln('<li><a href="/$token/file/$i" download>'
          '${_esc(f.name)}</a> <span>(${_fmt(f.size)})</span></li>');
    }
    final html = '''
<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Files from phone</title>
<style>
  body{font-family:system-ui,sans-serif;max-width:640px;margin:32px auto;padding:0 16px;}
  h1{font-size:1.3rem;} li{margin:.5rem 0;} a{font-size:1.05rem;}
  span{color:#777;font-size:.9rem;}
</style></head><body>
<h1>Files shared from the phone (${files.length})</h1>
<p>Click a file to download it to this computer.</p>
<ul>${rows.toString()}</ul>
</body></html>''';
    res.headers.contentType = ContentType.html;
    res.write(html);
    res.close();
  }

  Future<void> _serveFile(HttpResponse res, SharedFile f) async {
    final file = File(f.path);
    if (!await file.exists()) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    res.headers.contentType = ContentType('application', 'octet-stream');
    res.headers.set('Content-Disposition', 'attachment; filename="${f.name}"');
    res.headers.set(HttpHeaders.contentLengthHeader, f.size.toString());
    await file.openRead().pipe(res); // pipe closes the response
  }

  static String _randomToken() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(5, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1048576).toStringAsFixed(1)} MB';
  }
}
