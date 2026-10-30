"""Scoring engine: match a Device against the signature database.

Each satisfied condition contributes points weighted by how discriminating
that signal is -- a model string or a service set is strong, a shared OUI
vendor is weak. The signature with the highest score (above a floor) wins;
confidence tracks the *absolute* evidence, saturating once several strong
signals agree, so a vendor-only match reads honestly low while a device that
matches vendor + model + service set reads high.

No single signal decides it -- that is the whole point of fusing them.
"""

from __future__ import annotations

from dataclasses import dataclass

from .signatures import SIGNATURES

DEFAULT_POINTS = {
    "oui_vendor": 2,
    "model_contains": 4,
    "friendly_name_contains": 2,
    "device_type_contains": 3,
    "services_any": 3,
    "services_all": 4,
}

_MIN_SCORE = 2        # a recognizable vendor is enough to label (low confidence)
_SATURATION = 6       # points at which confidence reaches 1.0


@dataclass
class Match:
    label: str
    category: str
    score: int
    confidence: float
    reasons: list
    notes: str | None = None


def identify(device) -> Match | None:
    """Return the best matching signature for a device, or None."""
    ctx = _context(device)
    best: Match | None = None
    for sig in SIGNATURES:
        match = _score(sig, ctx)
        if match and (best is None or match.score > best.score
                      or (match.score == best.score
                          and match.confidence > best.confidence)):
            best = match
    return best


def annotate(device) -> None:
    """Write the fingerprint result onto the device in place."""
    match = identify(device)
    if match and match.score >= _MIN_SCORE:
        device.classification = match.label
        device.category = match.category
        device.confidence = match.confidence
        device.match_reasons = match.reasons
        device.notes = match.notes
    else:
        # Fall back to the coarse heuristic so every device still gets a label.
        device.category = device.role_guess()


def _context(device) -> dict:
    vendor = " ".join(filter(None, [device.manufacturer,
                                    device.ssdp_manufacturer])).lower()
    model = " ".join(filter(None, [device.model,
                                   device.friendly_name])).lower()
    return {
        "vendor": vendor,
        "model": model,
        "friendly": (device.friendly_name or "").lower(),
        "types": " ".join(device.device_types).lower(),
        "services": {s.lower() for s in device.services},
    }


def _score(sig: dict, ctx: dict) -> Match | None:
    score = 0
    reasons: list = []

    for key, points in DEFAULT_POINTS.items():
        if key not in sig:
            continue
        hit = _condition(key, sig[key], ctx)
        if hit:
            score += points
            reasons.append(hit)

    if score == 0:
        return None
    confidence = min(1.0, score / _SATURATION)
    return Match(
        label=sig["label"],
        category=sig.get("category", "unknown"),
        score=score,
        confidence=round(confidence, 2),
        reasons=reasons,
        notes=sig.get("notes"),
    )


def _condition(key: str, needles, ctx: dict) -> str | None:
    if key == "oui_vendor":
        for n in needles:
            if n.lower() in ctx["vendor"]:
                return f"vendor~{n}"
    elif key == "model_contains":
        for n in needles:
            if n.lower() in ctx["model"]:
                return f"model~{n}"
    elif key == "friendly_name_contains":
        for n in needles:
            if n.lower() in ctx["friendly"]:
                return f"name~{n}"
    elif key == "device_type_contains":
        for n in needles:
            if n.lower() in ctx["types"]:
                return f"upnp~{n}"
    elif key == "services_any":
        for n in needles:
            if n.lower() in ctx["services"]:
                return f"svc={n}"
    elif key == "services_all":
        if all(n.lower() in ctx["services"] for n in needles):
            return "svc=all(" + ",".join(needles) + ")"
    return None
