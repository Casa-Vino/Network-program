import 'package:flutter/material.dart';

import '../services/wifi_survey.dart';

/// Site survey: Wi-Fi networks in range with signal, security and channel.
class WifiSurveyScreen extends StatefulWidget {
  const WifiSurveyScreen({super.key});

  @override
  State<WifiSurveyScreen> createState() => _WifiSurveyScreenState();
}

class _WifiSurveyScreenState extends State<WifiSurveyScreen> {
  WifiSurveyResult? _res;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await surveyWifi();
    if (mounted) {
      setState(() {
        _res = res;
        _loading = false;
      });
    }
  }

  IconData _signalIcon(int pct) {
    if (pct < 0) return Icons.signal_wifi_statusbar_null;
    if (pct >= 70) return Icons.network_wifi;
    if (pct >= 40) return Icons.network_wifi_3_bar;
    return Icons.network_wifi_1_bar;
  }

  bool _open(String? sec) {
    final s = (sec ?? '').toLowerCase();
    return s.isEmpty || s == 'open' || s.contains('none');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi networks in range'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Rescan',
              onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_res!.nets.isEmpty)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _res!.note ?? 'No Wi-Fi networks found.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _res!.nets.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text('${_res!.nets.length} network(s) in range',
                            style: theme.textTheme.labelLarge),
                      );
                    }
                    final n = _res!.nets[i - 1];
                    final open = _open(n.security);
                    return ListTile(
                      leading: Icon(_signalIcon(n.signal)),
                      title: Text(n.ssid),
                      subtitle: Text([
                        if (n.security != null && n.security!.isNotEmpty)
                          n.security
                        else
                          'Open',
                        if (n.channel != null) 'ch ${n.channel}',
                      ].join('  •  ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (open)
                            Icon(Icons.lock_open,
                                size: 18, color: theme.colorScheme.error),
                          const SizedBox(width: 8),
                          Text(n.signal < 0 ? '—' : '${n.signal}%',
                              style: theme.textTheme.titleSmall),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
