"""Device model and the fusion layer.

Each discovery module emits partial "findings" (plain dicts) keyed by IP.
The Inventory merges them into one Device record per host, so that an SSDP
description, an mDNS hostname, and an ARP/OUI manufacturer for the same IP
end up on a single object. This is the "scoring function over several
signals" layer -- right now the fusion is a simple merge plus role_guess(),
and that is the natural place to grow smarter identification later.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Device:
    ip: str
    mac: Optional[str] = None
    manufacturer: Optional[str] = None     # resolved from the MAC OUI
    hostname: Optional[str] = None          # from an mDNS A record
    friendly_name: Optional[str] = None     # SSDP <friendlyName>
    model: Optional[str] = None             # SSDP <modelName>/<modelNumber>
    ssdp_manufacturer: Optional[str] = None # SSDP <manufacturer>
    device_types: set = field(default_factory=set)  # SSDP deviceType URNs
    services: set = field(default_factory=set)       # mDNS service types
    sources: set = field(default_factory=set)        # {"ssdp","mdns","arp","sweep"}

    # Filled by the fingerprint engine (fingerprint/engine.annotate).
    classification: Optional[str] = None             # best signature label
    category: Optional[str] = None                   # coarse device category
    confidence: float = 0.0                          # 0..1 for the match
    notes: Optional[str] = None                      # e.g. where admin UI lives
    match_reasons: list = field(default_factory=list)

    # Filled by the drivers layer (optional, opt-in probing only).
    probes: list = field(default_factory=list)       # list[ProbeResult]

    def role_guess(self) -> str:
        """A cheap first-pass role from the strongest available signal.

        This is deliberately a flat set of rules, not ML -- it is the seed
        of the scoring function and easy to extend one line at a time.
        """
        types = " ".join(self.device_types).lower()
        svcs = " ".join(self.services).lower()

        if "internetgatewaydevice" in types:
            return "gateway / router"
        if "wandevice" in types or "wanconnectiondevice" in types:
            return "gateway / router"
        if "_hap._tcp" in svcs:
            return "homekit accessory"
        if "_ipp._tcp" in svcs or "_printer._tcp" in svcs or "_pdl-datastream" in svcs:
            return "printer"
        if "_airplay._tcp" in svcs or "_raop._tcp" in svcs:
            return "media / airplay"
        if "mediarenderer" in types or "_googlecast._tcp" in svcs:
            return "media renderer"
        if "_spotify-connect._tcp" in svcs:
            return "speaker"
        if "_ssh._tcp" in svcs or "_sftp-ssh._tcp" in svcs:
            return "host (ssh)"
        if "_smb._tcp" in svcs or "_afpovertcp._tcp" in svcs:
            return "file server / nas"
        if self.device_types or self.services:
            return "upnp/mdns device"
        return "unknown"

    def role(self) -> str:
        """Best available label: a fingerprint match beats the heuristic."""
        return self.classification or self.category or self.role_guess()

    def to_row(self) -> dict:
        row = {
            "ip": self.ip,
            "mac": self.mac or "",
            "manufacturer": self.manufacturer or self.ssdp_manufacturer or "",
            "name": self.friendly_name or self.hostname or "",
            "model": self.model or "",
            "role": self.role(),
            "conf": f"{self.confidence:.2f}" if self.confidence else "",
            "sources": ",".join(sorted(self.sources)),
        }
        if self.notes:
            row["notes"] = self.notes
        if self.match_reasons:
            row["reasons"] = self.match_reasons
        if self.probes:
            row["probes"] = [p.to_dict() for p in self.probes]
        return row


class Inventory:
    """Holds one Device per IP and merges findings into it."""

    def __init__(self) -> None:
        self._by_ip: dict[str, Device] = {}

    def add(self, finding: dict) -> None:
        ip = finding.get("ip")
        if not ip:
            return
        dev = self._by_ip.setdefault(ip, Device(ip=ip))

        for scalar in ("friendly_name", "model", "ssdp_manufacturer", "hostname"):
            value = finding.get(scalar)
            if value and not getattr(dev, scalar):
                setattr(dev, scalar, value)

        for multi in ("device_types", "services", "sources"):
            value = finding.get(multi)
            if value:
                getattr(dev, multi).update(value)

    def set_mac(self, ip: str, mac: str) -> None:
        dev = self._by_ip.get(ip)
        if dev:
            dev.mac = mac
            dev.sources.add("arp")

    def ips(self) -> list[str]:
        return list(self._by_ip)

    def devices(self) -> list[Device]:
        return sorted(self._by_ip.values(), key=lambda d: _ip_key(d.ip))


def _ip_key(ip: str) -> tuple:
    try:
        return tuple(int(p) for p in ip.split("."))
    except ValueError:
        return (999, ip)
