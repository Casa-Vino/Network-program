"""MAC OUI -> manufacturer lookup.

The 24-bit prefix of a MAC identifies the manufacturer via the IEEE OUI
registry. A tiny built-in table covers a few common vendors so the tool is
useful out of the box; pass --oui to load the full registry for real
coverage. Both the IEEE `oui.txt` and the Wireshark `manuf` formats parse.

Note: IEEE also issues 28-/36-bit prefixes (MA-M/MA-S) that share a 24-bit
OUI; this sketch keys on 24 bits only, which is correct for the vast
majority of consumer gear.
"""

from __future__ import annotations

import re

# Minimal seed set -- replaced/augmented by load_file().
_BUILTIN = {
    "FC:FB:FB": "Cisco Systems",
    "00:1A:2B": "Cisco Systems",
    "B8:27:EB": "Raspberry Pi Foundation",
    "DC:A6:32": "Raspberry Pi Trading",
    "00:17:88": "Philips Hue",
    "EC:FA:BC": "Espressif (ESP)",
    "A4:CF:12": "Espressif (ESP)",
    "F0:9F:C2": "Ubiquiti",
    "74:AC:B9": "Ubiquiti",
    "00:11:32": "Synology",
    "00:1D:0F": "TP-Link",
    "50:C7:BF": "TP-Link",
    "00:18:4D": "Netgear",
    "A0:40:A0": "Netgear",
    "00:25:9C": "Cisco-Linksys",
    "AC:DE:48": "Apple",
    "F0:18:98": "Apple",
}

_loaded: dict[str, str] = {}


def load_file(path: str) -> int:
    """Load an IEEE oui.txt or Wireshark manuf file. Returns entry count."""
    count = 0
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            entry = _parse_line(line)
            if entry:
                prefix, vendor = entry
                _loaded[prefix] = vendor
                count += 1
    return count


def lookup(mac: str) -> str | None:
    prefix = _prefix(mac)
    if not prefix:
        return None
    return _loaded.get(prefix) or _BUILTIN.get(prefix)


def _prefix(mac: str) -> str | None:
    hexpairs = re.findall(r"[0-9A-Fa-f]{2}", mac)
    if len(hexpairs) < 3:
        return None
    return ":".join(p.upper() for p in hexpairs[:3])


# Wireshark:  FC:FB:FB    Cisco    # comment      (also /36 masked prefixes)
# IEEE oui:   FC-FB-FB   (hex)\t\tCisco Systems, Inc.
_MANUF_RE = re.compile(r"^([0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2})"
                       r"(?:/\d+)?\s+(.+)$")
_IEEE_RE = re.compile(r"^([0-9A-Fa-f]{6})\s+\(base 16\)\s+(.+)$")


def _parse_line(line: str):
    line = line.rstrip("\n")
    if not line or line.lstrip().startswith("#"):
        return None

    m = _MANUF_RE.match(line.strip())
    if m:
        prefix = m.group(1).upper().replace("-", ":")
        vendor = m.group(2).split("#")[0].strip().split("\t")[0].strip()
        if vendor:
            return prefix, vendor

    m = _IEEE_RE.match(line.strip())
    if m:
        raw = m.group(1).upper()
        prefix = ":".join(raw[i:i + 2] for i in range(0, 6, 2))
        return prefix, m.group(2).strip()

    return None
