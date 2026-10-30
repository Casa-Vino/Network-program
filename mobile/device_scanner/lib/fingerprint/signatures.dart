/// Device signature database (mobile edition).
///
/// Mirrors the Python `netinv` fingerprint approach, but the signals are the
/// ones a phone can actually gather: open TCP ports, advertised mDNS service
/// types, the gateway flag, and an mDNS/reverse-DNS hostname. No OUI/vendor
/// here — Android does not expose other devices' MAC addresses.
///
/// Ordering matters only as a tie-breaker (earlier wins at equal score), so
/// more specific/confident signatures come first. Add coverage by appending;
/// the engine needs no changes.
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
  final List<String> hostnameContains; // substring of the hostname
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
  // NAS proper — needs a NAS-specific signal, not just SMB.
  Signature(
    label: 'NAS / file server',
    category: 'file server / nas',
    portsAny: [548, 5000, 5001],
    servicesAny: ['_afpovertcp._tcp'],
    hostnameContains: ['synology', 'qnap', 'truenas', 'nas', 'diskstation'],
    notes: 'Dedicated storage. Its web admin is usually on :5000/:5001.',
  ),
  Signature(
    label: 'Network printer',
    category: 'printer',
    portsAny: [9100, 631, 515],
    servicesAny: ['_ipp._tcp', '_ipps._tcp', '_pdl-datastream._tcp', '_printer._tcp'],
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
    label: 'Roku',
    category: 'media / streaming',
    portsAny: [8060],
    servicesAny: ['_roku-rcp._tcp'],
  ),
  Signature(
    label: 'Plex media server',
    category: 'media server',
    portsAny: [32400],
    notes: 'Plex web UI is on :32400/web.',
  ),
  Signature(
    label: 'Samsung Smart TV',
    category: 'smart tv',
    portsAny: [8001, 8002],
  ),
  Signature(
    label: 'LG webOS TV',
    category: 'smart tv',
    portsAny: [3000, 3001],
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
    label: 'Home Assistant',
    category: 'home automation hub',
    portsAny: [8123],
    notes: 'Open its dashboard at http://<ip>:8123.',
  ),
  Signature(
    label: 'MQTT broker',
    category: 'iot broker',
    portsAny: [1883, 8883],
  ),
  Signature(
    label: 'DNS server (e.g. Pi-hole)',
    category: 'dns server',
    portsAny: [53],
    notes: 'Answers DNS — could be a Pi-hole/AdGuard. Check its web UI.',
  ),
  Signature(
    label: 'IP camera',
    category: 'camera',
    portsAny: [554],
    notes: 'RTSP stream port is open — likely a camera or NVR.',
  ),
  Signature(
    label: 'SSH host',
    category: 'host',
    portsAny: [22],
    servicesAny: ['_ssh._tcp', '_sftp-ssh._tcp'],
  ),
  Signature(
    label: 'Remote desktop (RDP)',
    category: 'host (windows)',
    portsAny: [3389],
  ),
  Signature(
    label: 'Computer',
    category: 'computer',
    servicesAny: ['_workstation._tcp', '_device-info._tcp'],
  ),
  // Bare SMB with no NAS/computer signal: honestly ambiguous.
  Signature(
    label: 'SMB file sharing',
    category: 'file sharing (smb)',
    portsAny: [445, 139],
    notes: 'Windows PC, a NAS, or a Samba server. Open \\\\<ip> on a PC, or '
        'check for a web admin.',
  ),
  Signature(
    label: 'Apple mobile device',
    category: 'mobile (apple)',
    portsAny: [62078],
  ),
  Signature(
    label: 'Web interface',
    category: 'web device',
    portsAny: [80, 443, 8080, 8443],
    notes: 'Has a web interface — open it in a browser to identify it.',
  ),
];
