import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'file_server.dart';

/// Shared-storage root, e.g. /storage/emulated/0, derived from the app's own
/// external dir (…/Android/data/<pkg>/files). Reading files under it needs the
/// "All files access" (MANAGE_EXTERNAL_STORAGE) permission.
Future<String> storageRoot() async {
  try {
    final d = await getExternalStorageDirectory();
    if (d != null) {
      final idx = d.path.indexOf('/Android/');
      if (idx > 0) return d.path.substring(0, idx);
    }
  } catch (_) {}
  return '/storage/emulated/0';
}

/// Immediate subdirectories of [path] (non-hidden), for the folder picker.
Future<List<Directory>> listSubdirs(String path) async {
  final dirs = <Directory>[];
  try {
    await for (final e in Directory(path).list(followLinks: false)) {
      if (e is Directory && !e.path.split('/').last.startsWith('.')) {
        dirs.add(e);
      }
    }
  } catch (_) {}
  dirs.sort((a, b) =>
      a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  return dirs;
}

/// Recursively collect files under [root] as SharedFiles, streamed-on-demand
/// (nothing is copied). Hidden files/dirs are skipped.
Future<List<SharedFile>> enumerateFolder(String root) async {
  final files = <SharedFile>[];
  final sep = RegExp(r'[/\\]');
  try {
    await for (final ent
        in Directory(root).list(recursive: true, followLinks: false)) {
      if (ent is! File) continue;
      final base = ent.path.split(sep).last;
      if (base.startsWith('.')) continue;
      if (ent.path.contains(RegExp(r'[/\\]\.'))) continue; // in a hidden dir
      try {
        final size = await ent.length();
        final rel = ent.path
            .substring(root.length)
            .replaceAll(RegExp(r'^[/\\]+'), '')
            .replaceAll('\\', '/'); // normalize for display/download
        files.add(SharedFile(name: base, path: ent.path, size: size, rel: rel));
      } catch (_) {}
    }
  } catch (_) {}
  files.sort((a, b) => a.rel.toLowerCase().compareTo(b.rel.toLowerCase()));
  return files;
}

int totalBytes(List<SharedFile> files) =>
    files.fold(0, (sum, f) => sum + f.size);
