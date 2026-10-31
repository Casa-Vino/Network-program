import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// A file to offer over the local web server.
class SharedFile {
  SharedFile({
    required this.name,
    required this.path,
    required this.size,
    String? rel,
  }) : rel = rel ?? name;

  final String name; // basename
  final String path; // absolute path on the phone
  final int size;
  final String rel; // path relative to a shared folder (for display)

  /// A safe, unique download filename (folder structure flattened).
  String get downloadName => rel.replaceAll('/', '_');
}

/// A tiny HTTP server that serves a chosen set of the phone's files to any
/// browser on the same Wi-Fi — a no-install way to copy files off the phone
/// when USB/MTP won't cooperate.
///
/// Features:
///  * individual downloads with HTTP Range support (resumable + seekable);
///  * `/all.zip` streams every file as one ZIP64 archive (store method, data
///    descriptors) — nothing is buffered, so multi-GB sets work.
///
/// Access is gated by a random token in the URL path (LAN convenience, not
/// strong security). Stop the server when the transfer is done.
class FileServer {
  HttpServer? _server;
  String token = '';
  List<SharedFile> files = [];

  /// Total bytes streamed to clients so far (for live sender-side feedback).
  final ValueNotifier<int> bytesServed = ValueNotifier<int>(0);

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  Future<void> start(List<SharedFile> files, {int preferredPort = 8080}) async {
    this.files = files;
    bytesServed.value = 0;
    token = _randomToken();
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
    // Drop empty segments so a trailing slash (/token/) still matches.
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
      if (segs.length == 2 && segs[1] == 'all.zip') {
        await _serveZip(res);
        return;
      }
      if (segs.length == 2 && segs[1] == 'list.json') {
        _serveList(res);
        return;
      }
      if (segs.length == 3 && segs[1] == 'file') {
        final idx = int.tryParse(segs[2]);
        if (idx != null && idx >= 0 && idx < files.length) {
          await _serveFile(req, files[idx]);
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
    var totalSize = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      totalSize += f.size;
      rows.writeln('<li><a href="/$token/file/$i" download="${_esc(f.downloadName)}">'
          '${_esc(f.rel)}</a> <span>(${_fmt(f.size)})</span></li>');
    }
    final html = '''
<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Files from phone</title>
<style>
  body{font-family:system-ui,sans-serif;max-width:720px;margin:32px auto;padding:0 16px;}
  h1{font-size:1.3rem;} li{margin:.4rem 0;} a{font-size:1rem;}
  span{color:#777;font-size:.9rem;}
  .zip{display:inline-block;font-size:1.05rem;padding:.7rem 1.1rem;border-radius:8px;
       background:#0E8388;color:#fff;text-decoration:none;}
</style></head><body>
<h1>Files shared from the phone (${files.length}, ${_fmt(totalSize)})</h1>
<p><a class="zip" href="/$token/all.zip" download="files.zip">⬇ Download all as .zip</a></p>
<p style="color:#777;font-size:.85rem">One archive with everything. Or grab
files individually below (each can resume if interrupted).</p>
<ul>${rows.toString()}</ul>
</body></html>''';
    res.headers.contentType = ContentType.html;
    res.write(html);
    res.close();
  }

  void _serveList(HttpResponse res) {
    final list = [
      for (var i = 0; i < files.length; i++)
        {'i': i, 'name': files[i].downloadName, 'rel': files[i].rel, 'size': files[i].size}
    ];
    res.headers.contentType = ContentType('application', 'json');
    res.write(jsonEncode({
      'count': files.length,
      'size': files.fold<int>(0, (s, f) => s + f.size),
      'files': list,
    }));
    res.close();
  }

  Future<void> _serveFile(HttpRequest req, SharedFile f) async {
    final res = req.response;
    final file = File(f.path);
    if (!await file.exists()) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final size = await file.length();
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

    var start = 0;
    var end = size - 1;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      if (m != null) {
        final s = m.group(1)!;
        final e = m.group(2)!;
        if (s.isEmpty && e.isNotEmpty) {
          start = size - int.parse(e);
          if (start < 0) start = 0;
        } else {
          start = s.isEmpty ? 0 : int.parse(s);
          end = e.isEmpty ? size - 1 : int.parse(e);
        }
        if (start > end || start >= size) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
          await res.close();
          return;
        }
        if (end >= size) end = size - 1;
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader,
            'bytes $start-$end/$size');
      }
    }

    res.headers.contentType = ContentType('application', 'octet-stream');
    res.headers.set(
        'Content-Disposition', 'attachment; filename="${f.downloadName}"');
    res.headers.set(HttpHeaders.contentLengthHeader, (end - start + 1).toString());
    await res.addStream(file.openRead(start, end + 1).map((c) {
      bytesServed.value += c.length;
      return c;
    }));
    await res.close();
  }

  // ---- Streaming ZIP64 (store method, data descriptors) ----
  // Byte layout verified against Python's zipfile before porting.

  Future<void> _serveZip(HttpResponse res) async {
    // Resolve readable files and their current sizes up front. Because we
    // store (no compression), the exact archive length is computable, so we
    // can send a sized download (browsers handle that far more reliably than a
    // chunked one) and skip anything unreadable instead of silently emptying.
    final items = <_ZipItem>[];
    for (final f in files) {
      final file = File(f.path);
      if (!await file.exists()) continue;
      int len;
      try {
        len = await file.length();
      } catch (_) {
        continue;
      }
      items.add(_ZipItem(file, utf8.encode(f.downloadName), len));
    }

    var contentLength = 0;
    var cdBytes = 0;
    for (final it in items) {
      contentLength += 30 + it.name.length + it.size + 24; // hdr+data+descriptor
      cdBytes += 46 + it.name.length + 28; // central dir entry (+zip64 extra)
    }
    contentLength += cdBytes + 56 + 20 + 22; // eocd64 + locator + eocd

    res.headers.contentType = ContentType('application', 'zip');
    res.headers.set('Content-Disposition', 'attachment; filename="files.zip"');
    res.headers.set(HttpHeaders.contentLengthHeader, contentLength.toString());

    var offset = 0;
    final entries = <_ZipEntry>[];

    for (final it in items) {
      final nameBytes = it.name;
      final localOffset = offset;

      final lh = BytesBuilder();
      _u32(lh, 0x04034b50);
      _u16(lh, 45); // version needed (zip64)
      _u16(lh, 0x0808); // flags: data descriptor + UTF-8
      _u16(lh, 0); // store
      _u16(lh, 0); // mod time
      _u16(lh, 0x21); // mod date (1980-01-01)
      _u32(lh, 0); // crc (in descriptor)
      _u32(lh, 0); // comp size (in descriptor)
      _u32(lh, 0); // uncomp size (in descriptor)
      _u16(lh, nameBytes.length);
      _u16(lh, 0); // extra len
      lh.add(nameBytes);
      final lhb = lh.toBytes();
      res.add(lhb);
      offset += lhb.length;

      final crc = _Crc32();
      var total = 0;
      try {
        // Cap the read at the declared size so a file that grew mid-read can't
        // overshoot Content-Length.
        await res.addStream(it.file.openRead(0, it.size).map((chunk) {
          crc.update(chunk);
          total += chunk.length;
          offset += chunk.length;
          bytesServed.value += chunk.length;
          return chunk;
        }));
      } catch (_) {
        // Connection dropped; nothing more we can do with this stream.
        return;
      }

      // If the file shrank mid-read, pad with zeros to keep Content-Length
      // exact (rare; keeps the download from hanging).
      while (total < it.size) {
        final n = (it.size - total) > 65536 ? 65536 : (it.size - total);
        final pad = Uint8List(n);
        res.add(pad);
        crc.update(pad);
        total += n;
        offset += n;
      }

      final dd = BytesBuilder();
      _u32(dd, 0x08074b50);
      _u32(dd, crc.value);
      _u64(dd, total);
      _u64(dd, total);
      final ddb = dd.toBytes();
      res.add(ddb);
      offset += ddb.length;

      entries.add(_ZipEntry(nameBytes, crc.value, total, localOffset));
    }

    final cdStart = offset;
    for (final e in entries) {
      final extra = BytesBuilder();
      _u16(extra, 0x0001);
      _u16(extra, 24);
      _u64(extra, e.size);
      _u64(extra, e.size);
      _u64(extra, e.offset);
      final extraB = extra.toBytes();

      final cd = BytesBuilder();
      _u32(cd, 0x02014b50);
      _u16(cd, 45); // version made by
      _u16(cd, 45); // version needed
      _u16(cd, 0x0808);
      _u16(cd, 0);
      _u16(cd, 0);
      _u16(cd, 0x21);
      _u32(cd, e.crc);
      _u32(cd, 0xFFFFFFFF); // comp size -> zip64
      _u32(cd, 0xFFFFFFFF); // uncomp size -> zip64
      _u16(cd, e.name.length);
      _u16(cd, extraB.length);
      _u16(cd, 0); // comment len
      _u16(cd, 0); // disk start
      _u16(cd, 0); // internal attrs
      _u32(cd, 0); // external attrs
      _u32(cd, 0xFFFFFFFF); // offset -> zip64
      cd.add(e.name);
      cd.add(extraB);
      final cdb = cd.toBytes();
      res.add(cdb);
      offset += cdb.length;
    }
    final cdSize = offset - cdStart;
    final n = entries.length;

    final z64 = offset;
    final e64 = BytesBuilder();
    _u32(e64, 0x06064b50);
    _u64(e64, 44);
    _u16(e64, 45);
    _u16(e64, 45);
    _u32(e64, 0);
    _u32(e64, 0);
    _u64(e64, n);
    _u64(e64, n);
    _u64(e64, cdSize);
    _u64(e64, cdStart);
    res.add(e64.toBytes());

    final loc = BytesBuilder();
    _u32(loc, 0x07064b50);
    _u32(loc, 0);
    _u64(loc, z64);
    _u32(loc, 1);
    res.add(loc.toBytes());

    final eocd = BytesBuilder();
    _u32(eocd, 0x06054b50);
    _u16(eocd, 0);
    _u16(eocd, 0);
    _u16(eocd, 0xFFFF);
    _u16(eocd, 0xFFFF);
    _u32(eocd, 0xFFFFFFFF);
    _u32(eocd, 0xFFFFFFFF);
    _u16(eocd, 0);
    res.add(eocd.toBytes());

    await res.close();
  }

  static void _u16(BytesBuilder b, int v) {
    b.addByte(v & 0xFF);
    b.addByte((v >> 8) & 0xFF);
  }

  static void _u32(BytesBuilder b, int v) {
    for (var i = 0; i < 4; i++) {
      b.addByte((v >> (8 * i)) & 0xFF);
    }
  }

  static void _u64(BytesBuilder b, int v) {
    for (var i = 0; i < 8; i++) {
      b.addByte((v >> (8 * i)) & 0xFF);
    }
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
    if (b < 1024 * 1024 * 1024) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }
}

class _ZipItem {
  _ZipItem(this.file, this.name, this.size);
  final File file;
  final List<int> name;
  final int size;
}

class _ZipEntry {
  _ZipEntry(this.name, this.crc, this.size, this.offset);
  final List<int> name;
  final int crc;
  final int size;
  final int offset;
}

/// Streaming CRC-32 (IEEE), table-based.
class _Crc32 {
  static final Uint32List _table = _makeTable();
  int _crc = 0xFFFFFFFF;

  static Uint32List _makeTable() {
    final t = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      t[n] = c;
    }
    return t;
  }

  void update(List<int> data) {
    var c = _crc;
    for (final b in data) {
      c = _table[(c ^ b) & 0xFF] ^ (c >>> 8);
    }
    _crc = c;
  }

  int get value => (_crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
