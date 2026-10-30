import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/file_server.dart';
import '../services/media_enum.dart';
import '../services/net_util.dart';
import 'folder_picker.dart';

/// Pick files on the phone and serve them over the local Wi-Fi so any computer
/// can download them from a browser — no USB, nothing to install on the PC.
class SendFilesScreen extends StatefulWidget {
  const SendFilesScreen({super.key});

  @override
  State<SendFilesScreen> createState() => _SendFilesScreenState();
}

class _SendFilesScreenState extends State<SendFilesScreen> {
  final _server = FileServer();
  List<SharedFile> _files = [];
  String? _url;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    final files = <SharedFile>[];
    for (final f in result.files) {
      if (f.path != null) {
        files.add(SharedFile(name: f.name, path: f.path!, size: f.size));
      }
    }
    setState(() => _files = files);
  }

  Future<void> _pickFolder() async {
    String? picked;
    if (Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }
      if (!status.isGranted) {
        setState(() => _error =
            'To share a whole folder, enable "All files access" for this app '
            '(Settings → Apps → Device Scanner → Permissions).');
        return;
      }
      if (!mounted) return;
      final root = await storageRoot();
      if (!mounted) return;
      picked = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => FolderPickerScreen(start: root)),
      );
    } else {
      // Desktop: the OS folder dialog works directly, no special permission.
      picked = await FilePicker.platform.getDirectoryPath();
    }
    if (picked == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final files = await enumerateFolder(picked);
    if (mounted) {
      setState(() {
        _files = files;
        _busy = false;
      });
    }
  }

  Future<void> _start() async {
    if (_files.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ip = await localIPv4();
      if (ip == null || !ip.contains('.')) {
        throw 'No network detected — connect to the same network as the '
            'receiving device.';
      }
      await _server.start(_files);
      setState(() => _url = 'http://$ip:${_server.port}/${_server.token}/');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    await _server.stop();
    setState(() => _url = null);
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Send files to a computer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Pick files, start sharing, then open the shown link in a browser '
            'on any computer on this Wi-Fi to download them. Nothing to install '
            'on the computer.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: (_url != null || _busy) ? null : _pick,
                icon: const Icon(Icons.attach_file),
                label: const Text('Pick files'),
              ),
              OutlinedButton.icon(
                onPressed: (_url != null || _busy) ? null : _pickFolder,
                icon: const Icon(Icons.folder_open),
                label: const Text('Share a folder'),
              ),
            ],
          ),
          if (_files.isNotEmpty && _url == null) ...[
            const SizedBox(height: 10),
            Text(
              '${_files.length} file(s) • ${_fmtBytes(totalBytes(_files))}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            ..._files.take(15).map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text('• ${f.rel}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
                )),
            if (_files.length > 15)
              Text('…and ${_files.length - 15} more',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),
          if (_url == null)
            FilledButton.icon(
              onPressed: (_files.isEmpty || _busy) ? null : _start,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Start sharing'),
            )
          else
            _sharingCard(theme),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }

  Widget _sharingCard(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Open this on the computer:',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                      data: _url!,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  _url!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontFeatures: const []),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Keep this screen open during the transfer. '
          'Sharing ${_files.length} file(s).',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _stop,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop sharing'),
        ),
      ],
    );
  }
}
