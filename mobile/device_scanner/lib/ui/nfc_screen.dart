import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

/// Reads NFC tags that are held to the phone: UID, the technologies the tag
/// supports, and any NDEF records it carries. Read-only — it does not write
/// to, lock, or clone tags.
class NfcScreen extends StatefulWidget {
  const NfcScreen({super.key});

  @override
  State<NfcScreen> createState() => _NfcScreenState();
}

class _NfcScreenState extends State<NfcScreen> {
  bool _available = false;
  bool _checked = false;
  bool _scanning = false;
  String? _error;

  String? _uid;
  List<String> _techs = const [];
  List<_Record> _records = const [];

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    if (_scanning) {
      NfcManager.instance.stopSession().catchError((_) {});
    }
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final a = Platform.isAndroid && await NfcManager.instance.isAvailable();
      setState(() {
        _available = a;
        _checked = true;
      });
    } catch (e) {
      setState(() {
        _checked = true;
        _error = '$e';
      });
    }
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _uid = null;
      _techs = const [];
      _records = const [];
      _scanning = true;
    });
    try {
      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          _read(tag);
          await NfcManager.instance.stopSession();
          if (mounted) setState(() => _scanning = false);
        },
      );
    } catch (e) {
      setState(() {
        _error = '$e';
        _scanning = false;
      });
    }
  }

  Future<void> _stop() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    if (mounted) setState(() => _scanning = false);
  }

  void _read(NfcTag tag) {
    final data = tag.data;
    final techs = <String>[];
    String? uid;
    if (data is Map) {
      for (final entry in data.entries) {
        techs.add(entry.key.toString());
        final v = entry.value;
        if (uid == null && v is Map && v['identifier'] != null) {
          uid = _hex(v['identifier']);
        }
      }
    }

    final records = <_Record>[];
    try {
      final ndef = Ndef.from(tag);
      final msg = ndef?.cachedMessage;
      if (msg != null) {
        for (final r in msg.records) {
          records.add(_parseRecord(r));
        }
      }
    } catch (_) {}

    setState(() {
      _uid = uid;
      _techs = techs;
      _records = records;
    });
  }

  _Record _parseRecord(NdefRecord r) {
    final payload = r.payload;
    final type = _ascii(r.type);
    // Well-known Text record ("T"): [status][lang][utf-8 text].
    if (type == 'T' && payload.isNotEmpty) {
      final langLen = payload[0] & 0x3f;
      final text = utf8.decode(
        payload.sublist(1 + langLen),
        allowMalformed: true,
      );
      return _Record('Text', text);
    }
    // Well-known URI record ("U"): [prefix byte][rest].
    if (type == 'U' && payload.isNotEmpty) {
      final rest = utf8.decode(payload.sublist(1), allowMalformed: true);
      return _Record('URI', '${_uriPrefix(payload[0])}$rest');
    }
    final label = type.isEmpty ? 'Record' : type;
    return _Record(label, _hex(payload));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_checked && !_available) {
      return Scaffold(
        appBar: AppBar(title: const Text('NFC tags')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              _error ??
                  (Platform.isAndroid
                      ? 'NFC is off or not supported on this phone. Turn NFC '
                          'on in Settings, then reopen this screen.'
                      : 'NFC tag reading is available on Android phones only.'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC tags'),
        bottom: _scanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator())
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: !_checked ? null : (_scanning ? _stop : _start),
        icon: Icon(_scanning ? Icons.stop : Icons.nfc),
        label: Text(_scanning ? 'Stop' : 'Scan a tag'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _scanning
                  ? 'Hold an NFC tag to the back of the phone…'
                  : (_uid == null && _records.isEmpty
                      ? 'Tap “Scan a tag”, then hold a tag to the phone.'
                      : 'Last tag read:'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (_uid != null)
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('UID'),
              subtitle: Text(_uid!),
            ),
          if (_techs.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('Technologies'),
              subtitle: Text(_techs.join(', ')),
            ),
          if (_records.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('NDEF records (${_records.length})',
                  style: theme.textTheme.labelLarge),
            ),
            ..._records.map((r) => ListTile(
                  leading: const Icon(Icons.description),
                  title: Text(r.kind),
                  subtitle: Text(r.value),
                )),
          ],
        ],
      ),
    );
  }

  static String _hex(Object? bytes) {
    final list = _toBytes(bytes);
    return list.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }

  static String _ascii(Object? bytes) {
    final list = _toBytes(bytes);
    return String.fromCharCodes(list.where((b) => b >= 0x20 && b < 0x7f));
  }

  static List<int> _toBytes(Object? bytes) {
    if (bytes is Uint8List) return bytes;
    if (bytes is List) return bytes.cast<int>();
    return const [];
  }

  static String _uriPrefix(int code) {
    const prefixes = [
      '', 'http://www.', 'https://www.', 'http://', 'https://', 'tel:',
      'mailto:', 'ftp://anonymous:anonymous@', 'ftp://ftp.', 'ftps://',
      'sftp://', 'smb://', 'nfs://', 'ftp://', 'dav://', 'news:',
      'telnet://', 'imap:', 'rtsp://', 'urn:', 'pop:', 'sip:', 'sips:',
      'tftp:', 'btspp://', 'btl2cap://', 'btgoep://', 'tcpobex://',
      'irdaobex://', 'file://', 'urn:epc:id:', 'urn:epc:tag:',
      'urn:epc:pat:', 'urn:epc:raw:', 'urn:epc:', 'urn:nfc:',
    ];
    return (code >= 0 && code < prefixes.length) ? prefixes[code] : '';
  }
}

class _Record {
  final String kind;
  final String value;
  const _Record(this.kind, this.value);
}
