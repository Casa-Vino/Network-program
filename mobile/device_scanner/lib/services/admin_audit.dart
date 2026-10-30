import 'dart:convert';
import 'dart:io';

import '../models/device.dart';

/// Read-only audit of a device's HTTP admin interface, ported from the desktop
/// netinv tool. It checks how the admin page gates access and — for HTTP Basic
/// — whether it still accepts a well-known default login.
///
/// Deliberately limited, by design:
///   * every request is a GET; nothing is ever configured or changed;
///   * login *forms* are detected but never auto-submitted (device-specific,
///     and POSTing risks side effects / lockouts);
///   * HTTP Digest is detected but not auto-tested.
///
/// The caller must gate this behind an explicit "I'm authorized" confirmation.
class Cred {
  const Cred(this.user, this.pass);
  final String user;
  final String pass;
  String get label =>
      '${user.isEmpty ? "<blank>" : user} / ${pass.isEmpty ? "<blank>" : pass}';
}

const List<Cred> kDefaultCreds = [
  Cred('admin', 'admin'),
  Cred('admin', 'password'),
  Cred('admin', ''),
  Cred('', ''),
  Cred('admin', '1234'),
  Cred('root', 'root'),
  Cred('user', 'user'),
  Cred('ubnt', 'ubnt'),
];

enum AuthScheme { none, basic, digest, form, unknown }

class AuditResult {
  AuditResult({
    required this.reachable,
    required this.scheme,
    required this.message,
    this.accepted,
    this.alert = false,
  });

  final bool reachable;
  final AuthScheme scheme;
  final String message;
  final Cred? accepted;
  final bool alert; // true when a default login was accepted (a real finding)
}

class AdminAudit {
  static final RegExp _passwordField =
      RegExp(r'''type=["']?password''', caseSensitive: false);

  static Future<AuditResult> run(Device device,
      {List<Cred> creds = kDefaultCreds}) async {
    final url = device.webUrl;
    if (url == null) {
      return AuditResult(
          reachable: false,
          scheme: AuthScheme.none,
          message: 'No web admin port is open on this device.');
    }
    final uri = Uri.parse(url);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      // Routers routinely serve self-signed HTTPS on the LAN; accept it for
      // this local audit only (we are not disabling TLS app-wide).
      ..badCertificateCallback = (_, __, ___) => true;

    try {
      final resp = await _get(client, uri);
      final www =
          (resp.headers.value(HttpHeaders.wwwAuthenticateHeader) ?? '')
              .toLowerCase();
      final body = await _readBody(resp);

      if (www.startsWith('basic')) {
        return _tryBasic(client, uri, creds);
      }
      if (www.startsWith('digest')) {
        return AuditResult(
            reachable: true,
            scheme: AuthScheme.digest,
            message: 'Uses HTTP Digest auth — not auto-tested. '
                'Open it and try the suggested defaults.');
      }
      if (resp.statusCode == 200 && _passwordField.hasMatch(body)) {
        return AuditResult(
            reachable: true,
            scheme: AuthScheme.form,
            message: 'Uses a login form — not auto-submitted. '
                'Open it and try the suggested defaults.');
      }
      if (resp.statusCode == 200) {
        return AuditResult(
            reachable: true,
            scheme: AuthScheme.none,
            alert: true,
            message: 'Admin page served WITHOUT a login prompt — anyone on the '
                'network can reach it. Set a password.');
      }
      return AuditResult(
          reachable: true,
          scheme: AuthScheme.unknown,
          message: 'Reachable (HTTP ${resp.statusCode}) but no recognizable '
              'login. Open it in the browser.');
    } on SocketException {
      return AuditResult(
          reachable: false,
          scheme: AuthScheme.none,
          message: 'Could not connect to $url.');
    } on HandshakeException {
      return AuditResult(
          reachable: false,
          scheme: AuthScheme.none,
          message: 'TLS handshake failed for $url.');
    } catch (e) {
      return AuditResult(
          reachable: false, scheme: AuthScheme.none, message: 'Audit error: $e');
    } finally {
      client.close(force: true);
    }
  }

  static Future<HttpClientResponse> _get(HttpClient c, Uri uri,
      {String? auth}) async {
    final req = await c.getUrl(uri);
    req.followRedirects = false;
    req.headers.set('User-Agent', 'device-scanner');
    if (auth != null) req.headers.set(HttpHeaders.authorizationHeader, auth);
    return req.close();
  }

  static Future<String> _readBody(HttpClientResponse r) async {
    try {
      return await r
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return '';
    }
  }

  static Future<AuditResult> _tryBasic(
      HttpClient c, Uri uri, List<Cred> creds) async {
    for (final cr in creds) {
      final token = base64.encode(utf8.encode('${cr.user}:${cr.pass}'));
      try {
        final resp = await _get(c, uri, auth: 'Basic $token');
        await _readBody(resp); // drain the connection
        if (resp.statusCode == 200) {
          return AuditResult(
              reachable: true,
              scheme: AuthScheme.basic,
              accepted: cr,
              alert: true,
              message: 'Accepts a default login: ${cr.label}. '
                  'Change the password right after you log in.');
        }
      } catch (_) {
        // try the next candidate
      }
    }
    return AuditResult(
        reachable: true,
        scheme: AuthScheme.basic,
        message: 'HTTP Basic auth is present; none of the tested default logins '
            'worked. Check the label for a unique password.');
  }
}
