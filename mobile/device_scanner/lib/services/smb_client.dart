import 'dart:io';

import 'package:smb_connect/smb_connect.dart';

/// Thin wrapper over the pure-Dart `smb_connect` client: connect, browse,
/// download, and upload. Used by the SMB browser screen.
///
/// smb_connect speaks SMB 1.0/CIFS/2.0/2.1 — enough for Windows and Samba
/// shares on a home network. Leave username/password blank to attempt a guest
/// connection (many servers disable this).
class SmbClient {
  SmbConnect? _conn;

  bool get connected => _conn != null;

  Future<void> connect({
    required String host,
    String domain = '',
    String username = '',
    String password = '',
  }) async {
    _conn = await SmbConnect.connectAuth(
      host: host,
      domain: domain,
      username: username,
      password: password,
    );
  }

  Future<List<SmbFile>> listShares() => _conn!.listShares();

  /// List the contents of a folder by its SMB path (e.g. "/Public/Docs").
  Future<List<SmbFile>> listPath(String path) async {
    final normalized = path.endsWith('/') ? path : '$path/';
    final folder = await _conn!.file(normalized);
    return _conn!.listFiles(folder);
  }

  /// Stream a remote file down to [localPath]. Returns the byte count.
  Future<int> download(SmbFile file, String localPath,
      {void Function(int received)? onProgress}) async {
    final out = File(localPath).openWrite();
    var total = 0;
    try {
      final stream = await _conn!.openRead(file);
      await for (final chunk in stream) {
        out.add(chunk);
        total += chunk.length;
        onProgress?.call(total);
      }
      await out.flush();
    } finally {
      await out.close();
    }
    return total;
  }

  /// Upload a local file into [remoteDirPath] under [name]. Returns byte count.
  Future<int> upload(String remoteDirPath, String name, File local,
      {void Function(int sent)? onProgress}) async {
    final remotePath = remoteDirPath.endsWith('/')
        ? '$remoteDirPath$name'
        : '$remoteDirPath/$name';
    final remote = await _conn!.createFile(remotePath);
    final sink = await _conn!.openWrite(remote);
    var total = 0;
    try {
      await for (final chunk in local.openRead()) {
        sink.add(chunk);
        total += chunk.length;
        onProgress?.call(total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return total;
  }

  Future<void> close() async {
    try {
      await _conn?.close();
    } catch (_) {
      // ignore close errors
    }
    _conn = null;
  }
}
