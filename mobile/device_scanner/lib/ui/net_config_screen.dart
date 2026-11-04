import 'package:flutter/material.dart';

import '../services/net_config.dart';

/// Shows this machine's own network configuration: interfaces + IPs (with CIDR
/// where known), gateways, and DNS servers. The orientation step before
/// scanning an unfamiliar network.
class NetConfigScreen extends StatefulWidget {
  const NetConfigScreen({super.key});

  @override
  State<NetConfigScreen> createState() => _NetConfigScreenState();
}

class _NetConfigScreenState extends State<NetConfigScreen> {
  NetConfig? _cfg;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cfg = await readNetConfig();
    if (mounted) {
      setState(() {
        _cfg = cfg;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('This device’s network'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(theme, 'Interfaces'),
                if (_cfg!.interfaces.isEmpty)
                  const Text('No active IPv4 interfaces.'),
                ..._cfg!.interfaces.map((i) => _ifaceTile(theme, i)),
                const SizedBox(height: 20),
                _section(theme, 'Gateway(s)'),
                Text(_cfg!.gateways.isEmpty ? '—' : _cfg!.gateways.join(', '),
                    style: theme.textTheme.bodyLarge),
                const SizedBox(height: 20),
                _section(theme, 'DNS server(s)'),
                Text(_cfg!.dns.isEmpty ? '—' : _cfg!.dns.join(', '),
                    style: theme.textTheme.bodyLarge),
                const SizedBox(height: 24),
                Text(
                  'Subnet mask (CIDR) is shown where the OS exposes it. Items '
                  'shown as “—” couldn’t be read on this platform.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.primary)),
      );

  Widget _ifaceTile(ThemeData theme, IfaceInfo i) {
    final addrs = i.ipv4.map((a) {
      return i.prefix != null && i.ipv4.first == a ? '$a/${i.prefix}' : a;
    }).join(', ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.lan),
        title: Text(i.name),
        subtitle: Text(addrs),
      ),
    );
  }
}
