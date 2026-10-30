import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:smb_connect/smb_connect.dart';

import '../services/net_util.dart';
import '../services/smb_client.dart';

/// Browse a host's SMB shares: navigate folders, download files to the phone,
/// and upload files into a folder.
///
/// Use only on shares you own or are authorized to access.
class SmbBrowserScreen extends StatefulWidget {
  const SmbBrowserScreen({super.key, required this.host, this.label});
  final String host;
  final String? label;

  @override
  State<SmbBrowserScreen> createState() => _SmbBrowserScreenState();
}

class _SmbBrowserScreenState extends State<SmbBrowserScreen> {
  final _client = SmbClient();
  final _domain = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  bool _busy = false;
  String? _error;

  // Navigation: a stack of folder paths. Empty = the shares list.
  final List<String> _stack = [];
  List<SmbFile> _entries = [];

  @override
  void dispose() {
    _client.close();
    _domain.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _client.connect(
        host: widget.host,
        domain: _domain.text.trim(),
        username: _user.text,
        password: _pass.text,
      );
      await _reload();
    } catch (e) {
      setState(() => _error = 'Connection failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entries = _stack.isEmpty
          ? await _client.listShares()
          : await _client.listPath(_stack.last);
      entries.sort((a, b) {
        final ad = a.isDirectory(), bd = b.isDirectory();
        if (ad != bd) return ad ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() => _entries = entries);
    } catch (e) {
      setState(() => _error = 'Could not list: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openEntry(SmbFile entry) {
    if (_stack.isEmpty) {
      _stack.add('/${entry.name}'); // a share
    } else if (entry.isDirectory()) {
      _stack.add(entry.path);
    } else {
      _download(entry);
      return;
    }
    _reload();
  }

  bool _goUp() {
    if (_stack.isEmpty) return false;
    setState(() => _stack.removeLast());
    _reload();
    return true;
  }

  Future<void> _download(SmbFile file) async {
    _snack('Downloading ${file.name}…');
    try {
      final base = await downloadsDir();
      final dir = Directory('${base.path}/DeviceScanner');
      await dir.create(recursive: true);
      final localPath = '${dir.path}/${file.name}';
      final bytes = await _client.download(file, localPath);
      _snack('Saved ${_fmt(bytes)} to ${dir.path}/${file.name}');
    } catch (e) {
      _snack('Download failed: $e');
    }
  }

  Future<void> _upload() async {
    if (_stack.isEmpty) return; // can't upload at the shares root
    final picked = await FilePicker.platform.pickFiles();
    final path = picked?.files.single.path;
    final name = picked?.files.single.name;
    if (path == null || name == null) return;
    _snack('Uploading $name…');
    try {
      final bytes = await _client.upload(_stack.last, name, File(path));
      _snack('Uploaded ${_fmt(bytes)} as $name');
      await _reload();
    } catch (e) {
      _snack('Upload failed: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final location =
        _stack.isEmpty ? 'Shares' : _stack.last.replaceFirst('/', '');
    return PopScope(
      canPop: _stack.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.label ?? widget.host),
          bottom: _busy
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(4),
                  child: LinearProgressIndicator())
              : null,
        ),
        floatingActionButton: _client.connected && _stack.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload'),
              )
            : null,
        body: !_client.connected ? _connectForm() : _browser(location),
      ),
    );
  }

  Widget _connectForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Connect to \\\\${widget.host}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Enter the file server\'s Windows/Samba login. Leave blank to try a '
          'guest connection. Use only on shares you are authorized to access.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _user,
          decoration: const InputDecoration(
              labelText: 'Username', border: OutlineInputBorder()),
          autocorrect: false,
          enableSuggestions: false,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass,
          obscureText: true,
          decoration: const InputDecoration(
              labelText: 'Password', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _domain,
          decoration: const InputDecoration(
              labelText: 'Domain / workgroup (optional)',
              border: OutlineInputBorder()),
          autocorrect: false,
          enableSuggestions: false,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _connect,
          icon: const Icon(Icons.login),
          label: const Text('Connect'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  Widget _browser(String location) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              if (_stack.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Up',
                  onPressed: _busy ? null : _goUp,
                  visualDensity: VisualDensity.compact,
                ),
              Expanded(
                child: Text(location,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: _entries.isEmpty && !_busy
              ? const Center(child: Text('Empty'))
              : ListView.separated(
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = _entries[i];
                    final isDir = _stack.isEmpty || e.isDirectory();
                    return ListTile(
                      leading: Icon(isDir
                          ? (_stack.isEmpty ? Icons.folder_shared : Icons.folder)
                          : Icons.insert_drive_file),
                      title: Text(e.name),
                      subtitle: isDir
                          ? null
                          : Text(_fmt(e.size)),
                      trailing: isDir
                          ? const Icon(Icons.chevron_right)
                          : const Icon(Icons.download),
                      onTap: _busy ? null : () => _openEntry(e),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
