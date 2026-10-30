import '../models/device.dart';

/// Factory-login hints by vendor, matched against a device's hostname and
/// classification.
///
/// IMPORTANT: these are *starting points*, not guarantees. Since ~2016 (and now
/// by law in several regions) new routers ship with a UNIQUE password printed
/// on a label rather than a universal default, so for new gear the label is the
/// real credential. Each hint says so.
class DefaultLogin {
  const DefaultLogin({
    required this.vendor,
    required this.match,
    this.user,
    this.pass,
    required this.note,
  });

  final String vendor;
  final List<String> match; // lowercase substrings to look for
  final String? user; // null when there is no universal default
  final String? pass;
  final String note;

  String get credLabel {
    if (user == null) return 'No universal default';
    final u = user!.isEmpty ? '<blank>' : user!;
    final p = (pass ?? '').isEmpty ? '<blank>' : pass!;
    return '$u / $p';
  }
}

const List<DefaultLogin> kDefaultLogins = [
  DefaultLogin(
    vendor: 'Wavlink',
    match: ['wavlink'],
    user: 'admin',
    pass: 'admin',
    note: 'Older units: admin/admin. Newer: the password on the label, or set '
        'on first login.',
  ),
  DefaultLogin(
    vendor: 'TP-Link',
    match: ['tp-link', 'tplink', 'tplinkwifi', 'archer'],
    user: 'admin',
    pass: 'admin',
    note: 'Older: admin/admin. Newer units make you set a password on first '
        'login (tplinkwifi.net).',
  ),
  DefaultLogin(
    vendor: 'NETGEAR',
    match: ['netgear', 'routerlogin'],
    user: 'admin',
    pass: 'password',
    note: 'Default admin/password; many prompt you to change it (routerlogin.net).',
  ),
  DefaultLogin(
    vendor: 'ASUS',
    match: ['asus'],
    user: 'admin',
    pass: 'admin',
    note: 'admin/admin on older units; newer ones set credentials during setup '
        '(router.asus.com).',
  ),
  DefaultLogin(
    vendor: 'Linksys',
    match: ['linksys'],
    user: 'admin',
    pass: 'admin',
    note: 'admin/admin (older), or blank username + admin. Newer: Linksys app / label.',
  ),
  DefaultLogin(
    vendor: 'D-Link',
    match: ['dlink', 'd-link'],
    user: 'admin',
    pass: '',
    note: 'admin with a blank password on many units; newer: the label.',
  ),
  DefaultLogin(
    vendor: 'Tenda',
    match: ['tenda'],
    user: 'admin',
    pass: 'admin',
    note: 'Often admin/admin (tendawifi.com).',
  ),
  DefaultLogin(
    vendor: 'Huawei',
    match: ['huawei'],
    user: 'admin',
    pass: 'admin',
    note: 'admin/admin on older units; newer: the label password.',
  ),
  DefaultLogin(
    vendor: 'Zyxel',
    match: ['zyxel'],
    user: 'admin',
    pass: '1234',
    note: 'Often admin/1234 or admin/admin; newer: the label.',
  ),
  DefaultLogin(
    vendor: 'Ubiquiti',
    match: ['ubiquiti', 'unifi', 'edgeos', 'ubnt'],
    user: 'ubnt',
    pass: 'ubnt',
    note: 'Older: ubnt/ubnt. UniFi is set up via its controller/app.',
  ),
  DefaultLogin(
    vendor: 'MikroTik',
    match: ['mikrotik', 'routeros'],
    user: 'admin',
    pass: '',
    note: 'admin with a blank password on older RouterOS; newer: blank or label.',
  ),
  DefaultLogin(
    vendor: 'Xiaomi',
    match: ['xiaomi', 'miwifi'],
    user: null,
    pass: null,
    note: 'Set during first-time setup (miwifi.com); no universal default.',
  ),
  DefaultLogin(
    vendor: 'Google Nest Wifi',
    match: ['google', 'nest'],
    user: null,
    pass: null,
    note: 'No web admin — configured entirely in the Google Home app.',
  ),
  DefaultLogin(
    vendor: 'eero',
    match: ['eero'],
    user: null,
    pass: null,
    note: 'No web admin — configured in the eero app.',
  ),
];

/// A generic hint used for routers/web devices we can't pin to a vendor.
const DefaultLogin kGenericRouterHint = DefaultLogin(
  vendor: 'Unknown router',
  match: [],
  user: 'admin',
  pass: 'admin',
  note: 'Check the label for a unique password first. Common fallbacks: '
      'admin/admin, admin/password, or admin with a blank password.',
);

/// Returns a vendor-specific hint, or a generic one for routers/web devices.
DefaultLogin? lookupDefaultLogin(Device d) {
  final hay = [
    d.hostname ?? '',
    d.classification ?? '',
    d.category ?? '',
  ].join(' ').toLowerCase();

  for (final e in kDefaultLogins) {
    if (e.match.any(hay.contains)) return e;
  }

  final isRouterish = d.isGateway ||
      (d.category?.contains('router') ?? false) ||
      (d.category == 'web device');
  return isRouterish ? kGenericRouterHint : null;
}
