import 'dart:io';

/// A Wi-Fi network seen in range (a site survey), not necessarily one you're on.
class WifiNet {
  WifiNet(this.ssid);
  final String ssid;
  String? security;
  String? channel;
  int signal = -1; // percent, -1 unknown
}

class WifiSurveyResult {
  WifiSurveyResult({required this.supported, this.nets = const [], this.note});
  final bool supported;
  final List<WifiNet> nets;
  final String? note;
}

/// Lists Wi-Fi networks in range. Windows via `netsh`, Linux via `nmcli`;
/// other platforms report unsupported (use the OS Wi-Fi list there).
Future<WifiSurveyResult> surveyWifi() async {
  try {
    if (Platform.isWindows) return _windows();
    if (Platform.isLinux) return _linux();
  } catch (e) {
    return WifiSurveyResult(supported: true, note: 'Survey failed: $e');
  }
  return WifiSurveyResult(
    supported: false,
    note: 'The in-app Wi-Fi survey runs on Windows and Linux. On this device, '
        'use the system Wi-Fi list to see networks in range.',
  );
}

Future<WifiSurveyResult> _windows() async {
  final r = await Process.run(
      'netsh', ['wlan', 'show', 'networks', 'mode=bssid']);
  final out = (r.stdout ?? '').toString();
  if (out.toLowerCase().contains('no wireless interface') ||
      out.toLowerCase().contains('not running')) {
    return WifiSurveyResult(
        supported: true,
        note: 'No wireless interface / WLAN service. On Ethernet-only there is '
            'nothing to survey.');
  }
  final nets = <WifiNet>[];
  WifiNet? cur;
  for (final raw in out.split('\n')) {
    final line = raw.trim();
    final ssid = RegExp(r'^SSID\s+\d+\s*:\s*(.*)$').firstMatch(line);
    if (ssid != null) {
      if (cur != null) nets.add(cur);
      final name = ssid.group(1)!.trim();
      cur = WifiNet(name.isEmpty ? '(hidden)' : name);
      continue;
    }
    if (cur == null) continue;
    final auth = RegExp(r'^Authentication\s*:\s*(.*)$').firstMatch(line);
    if (auth != null) {
      cur.security ??= auth.group(1)!.trim();
      continue;
    }
    final sig = RegExp(r'^Signal\s*:\s*(\d+)%').firstMatch(line);
    if (sig != null && cur.signal < 0) {
      cur.signal = int.parse(sig.group(1)!);
      continue;
    }
    final chan = RegExp(r'^Channel\s*:\s*(\d+)').firstMatch(line);
    if (chan != null) cur.channel ??= chan.group(1)!;
  }
  if (cur != null) nets.add(cur);
  nets.sort((a, b) => b.signal.compareTo(a.signal));
  return WifiSurveyResult(supported: true, nets: nets);
}

Future<WifiSurveyResult> _linux() async {
  final r = await Process.run(
      'nmcli', ['-t', '-f', 'SSID,SIGNAL,SECURITY,CHAN', 'dev', 'wifi']);
  final out = (r.stdout ?? '').toString();
  final nets = <WifiNet>[];
  for (final raw in out.split('\n')) {
    if (raw.trim().isEmpty) continue;
    // nmcli -t escapes ':' inside fields as '\:'
    final fields = raw.split(RegExp(r'(?<!\\):')).map((f) => f.replaceAll(r'\:', ':')).toList();
    if (fields.isEmpty) continue;
    final ssid = fields[0].trim();
    final net = WifiNet(ssid.isEmpty ? '(hidden)' : ssid);
    if (fields.length > 1) net.signal = int.tryParse(fields[1].trim()) ?? -1;
    if (fields.length > 2 && fields[2].trim().isNotEmpty) {
      net.security = fields[2].trim();
    }
    if (fields.length > 3) net.channel = fields[3].trim();
    nets.add(net);
  }
  nets.sort((a, b) => b.signal.compareTo(a.signal));
  return WifiSurveyResult(supported: true, nets: nets);
}
