import '../models/device.dart';
import 'signatures.dart';

/// Scores a device against every signature and keeps the best match, using the
/// same saturating-confidence idea as the Python `netinv` engine: confidence
/// reflects absolute evidence, so a single weak signal reads low while several
/// agreeing signals read high.

const int _gatewayPts = 5;
const int _portsAnyPts = 3;
const int _servicesAnyPts = 3;
const int _hostnamePts = 2;
const int _minScore = 2;
const double _saturation = 6;

class Match {
  Match(this.label, this.category, this.score, this.confidence, this.reasons,
      this.notes);

  final String label;
  final String category;
  final int score;
  final double confidence;
  final List<String> reasons;
  final String? notes;
}

Match? _scoreSignature(Signature s, Device d) {
  var score = 0;
  final reasons = <String>[];

  if (s.gateway && d.isGateway) {
    score += _gatewayPts;
    reasons.add('is the gateway');
  }
  if (s.portsAny.isNotEmpty) {
    final hit = s.portsAny.where(d.openPorts.contains).toList();
    if (hit.isNotEmpty) {
      score += _portsAnyPts;
      reasons.add('port ${hit.first} open');
    }
  }
  if (s.servicesAny.isNotEmpty) {
    final hit = s.servicesAny
        .where((svc) => d.services.any((x) => x.contains(svc)))
        .toList();
    if (hit.isNotEmpty) {
      score += _servicesAnyPts;
      reasons.add('mDNS ${hit.first}');
    }
  }
  if (s.hostnameContains.isNotEmpty && d.hostname != null) {
    final h = d.hostname!.toLowerCase();
    final hit = s.hostnameContains.where((n) => h.contains(n.toLowerCase()));
    if (hit.isNotEmpty) {
      score += _hostnamePts;
      reasons.add('hostname~${hit.first}');
    }
  }

  if (score == 0) return null;
  final confidence = (score / _saturation).clamp(0.0, 1.0);
  return Match(s.label, s.category, score,
      double.parse(confidence.toStringAsFixed(2)), reasons, s.notes);
}

Match? identify(Device d) {
  Match? best;
  for (final s in kSignatures) {
    final m = _scoreSignature(s, d);
    if (m == null) continue;
    if (best == null ||
        m.score > best.score ||
        (m.score == best.score && m.confidence > best.confidence)) {
      best = m;
    }
  }
  return best;
}

/// Writes the best match onto the device, or a coarse fallback category.
void annotate(Device d) {
  final m = identify(d);
  if (m != null && m.score >= _minScore) {
    d.classification = m.label;
    d.category = m.category;
    d.confidence = m.confidence;
    d.reasons = m.reasons;
    d.notes = m.notes;
  } else {
    d.category = (d.openPorts.isNotEmpty || d.services.isNotEmpty)
        ? 'unidentified device'
        : 'host';
  }
}
