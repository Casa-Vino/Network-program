/// A single discovered host on the local network.
///
/// On a phone we can see far less than a laptop can: no ARP table and no MAC
/// address for other hosts (Android blocks that), so there is no OUI/vendor
/// signal. What we *can* observe is which TCP ports answer and which mDNS
/// services a device advertises — those are the signals the fingerprint
/// engine scores.
class Device {
  Device(this.ip);

  final String ip;
  String? hostname; // from mDNS, when available
  final Set<int> openPorts = {};
  final Set<String> services = {}; // mDNS service types, e.g. "_airplay._tcp"
  bool isGateway = false;

  // Filled by the fingerprint engine.
  String? classification;
  String? category;
  double confidence = 0;
  List<String> reasons = const [];
  String? notes;

  /// Best available label.
  String get role => classification ?? category ?? 'unknown';

  /// Numeric last octet, for sorting within a /24.
  int get lastOctet => int.tryParse(ip.split('.').last) ?? 0;

  /// A browser URL for the device's web admin, if a web port is open.
  String? get webUrl {
    if (openPorts.contains(443)) return 'https://$ip';
    if (openPorts.contains(80)) return 'http://$ip';
    if (openPorts.contains(8443)) return 'https://$ip:8443';
    if (openPorts.contains(8080)) return 'http://$ip:8080';
    if (openPorts.contains(5000)) return 'http://$ip:5000';
    if (openPorts.contains(8123)) return 'http://$ip:8123';
    return null;
  }
}
