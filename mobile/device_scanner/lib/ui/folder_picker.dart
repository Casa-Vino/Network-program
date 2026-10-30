import 'dart:io';

import 'package:flutter/material.dart';

import '../services/media_enum.dart';

/// Minimal in-app folder browser (needs All-files access). Pops the chosen
/// folder's absolute path.
class FolderPickerScreen extends StatefulWidget {
  const FolderPickerScreen({super.key, required this.start});
  final String start;

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  late String _current = widget.start;
  List<Directory> _subdirs = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final subs = await listSubdirs(_current);
    if (mounted) {
      setState(() {
        _subdirs = subs;
        _busy = false;
      });
    }
  }

  void _enter(String path) {
    setState(() => _current = path);
    _load();
  }

  bool _up() {
    if (_current == widget.start || !_current.startsWith(widget.start)) {
      return false;
    }
    final parent = _current.substring(0, _current.lastIndexOf('/'));
    _enter(parent.isEmpty ? widget.start : parent);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final shown = _current.replaceFirst(widget.start, '') ;
    return PopScope(
      canPop: _current == widget.start,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pick a folder to share'),
          bottom: _busy
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(4),
                  child: LinearProgressIndicator())
              : null,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.pop(context, _current),
          icon: const Icon(Icons.check),
          label: const Text('Share this folder'),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  if (_current != widget.start)
                    IconButton(
                      icon: const Icon(Icons.arrow_upward),
                      visualDensity: VisualDensity.compact,
                      onPressed: _up,
                    ),
                  Expanded(
                    child: Text(shown.isEmpty ? '/ (internal storage)' : shown,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _subdirs.isEmpty && !_busy
                  ? const Center(child: Text('No subfolders here'))
                  : ListView.separated(
                      itemCount: _subdirs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final name = _subdirs[i].path.split('/').last;
                        return ListTile(
                          leading: const Icon(Icons.folder),
                          title: Text(name),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _enter(_subdirs[i].path),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
