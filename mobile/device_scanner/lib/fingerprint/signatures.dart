/// Device signature database (mobile edition).
///
/// Mirrors the Python `netinv` fingerprint approach, but the signals are the
/// ones a phone can actually gather: open TCP ports, advertised mDNS service
/// types, the gateway flag, and an mDNS hostname. No OUI/vendor here — Android
/// does not expose other devices' MAC addresses.
///
/// Add coverage by appending to [kSignatures]; the engine needs no changes.
class Signature {
  const Signature({
    required this.label,
    required this.category,
    this.portsAny = const [],
    this.servicesAny = const [],
    this.hostnameContains = const [],
    this.gateway = false,
    this.notes,
  });

  final String label;
  final String category;
  final List<int> portsAny; // any of these TCP ports open
  final List<String> servicesAny; // any of these mDNS service types present
  final List<String> hostnameContains; // substring of the mDNS hostname
  final bool gateway; // matches the network's gateway host
  final String? notes; // informational hint shown in the UI
}

const List<Signature> kSignatures = [
  Signature(
    label: 'Router / gateway',
    category: 'gateway / router',
    gateway: true,
    notes: 'This is your network gateway. Open its web admin in a browser at '
        'this IP; if it still uses a factory password, change it.',
  ),
  Signature(
    label: 'Network printer',
    category: 'printer',
    portsAny: [9100, 631, 515],
    servicesAny: ['_ipp._tcp', '_ipps._tcp', '_pdl-datastream._tcp', '_printer._tcp'],
  ),
  Signature(
    label: 'NAS / file server',
    category: 'file server / nas',
    portsAny: [445, 548, 5000, 5001],
    servicesAny: ['_smb._tcp', '_afpovertcp._tcp'],
    notes: 'File sharing. A web admin often lives on :5000/:5001.',
  ),
  Signature(
    label: 'Apple TV / AirPlay',
    category: 'media / airplay',
    portsAny: [7000],
    servicesAny: ['_airplay._tcp', '_raop._tcp', '_mediaremotetv._tcp'],
  ),
  Signature(
    label: 'Google Cast',
    category: 'media renderer',
    portsAny: [8008, 8009],
    servicesAny: ['_googlecast._tcp'],
  ),
  Signature(
    label: 'Sonos speaker',
    category: 'speaker',
    servicesAny: ['_sonos._tcp', '_spotify-connect._tcp'],
  ),
  Signature(
    label: 'HomeKit accessory',
    category: 'homekit accessory',
    servicesAny: ['_hap._tcp'],
  ),
  Signature(
    label: 'Philips Hue bridge',
    category: 'iot hub',
    servicesAny: ['_hue._tcp', '_hap._tcp'],
    hostnameContains: ['hue'],
  ),
  Signature(
    label: 'SSH host',
    category: 'host',
    portsAny: [22],
    servicesAny: ['_ssh._tcp', '_sftp-ssh._tcp'],
  ),
  Signature(
    label: 'Windows PC',
    category: 'host (windows)',
    portsAny: [3389, 139],
  ),
  Signature(
    label: 'Apple mobile device',
    category: 'mobile (apple)',
    portsAny: [62078],
  ),
  Signature(
    label: 'IP camera',
    category: 'camera',
    portsAny: [554],
    notes: 'RTSP stream port is open — likely a camera or NVR.',
  ),
  Signature(
    label: 'Web interface',
    category: 'web device',
    portsAny: [80, 443, 8080, 8443],
    notes: 'Has a web interface — open it in a browser to identify it.',
  ),
];
