"""SSDP (UPnP) discovery.

Sends an M-SEARCH to the SSDP multicast group, collects the responders,
then fetches each one's device-description XML (the LOCATION header) to pull
out the friendly name, manufacturer, model, and device-type URNs. The URNs
are the single most reliable signal for "is this a gateway" on a LAN.

Standard library only.
"""

from __future__ import annotations

import select
import socket
import time
import xml.etree.ElementTree as ET
from urllib.request import urlopen

SSDP_ADDR = "239.255.255.250"
SSDP_PORT = 1900

_MSEARCH = (
    "M-SEARCH * HTTP/1.1\r\n"
    f"HOST: {SSDP_ADDR}:{SSDP_PORT}\r\n"
    'MAN: "ssdp:discover"\r\n'
    "MX: 2\r\n"
    "ST: ssdp:all\r\n"
    "\r\n"
).encode()


def discover(timeout: float = 4.0) -> list[dict]:
    """Return a list of findings, one per responding IP."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)

    # Locations to fetch, grouped so each description is retrieved once.
    locations: dict[str, set[str]] = {}
    try:
        for _ in range(2):  # a couple of probes -- UDP is lossy
            sock.sendto(_MSEARCH, (SSDP_ADDR, SSDP_PORT))

        deadline = time.time() + timeout
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                break
            ready, _, _ = select.select([sock], [], [], remaining)
            if not ready:
                break
            try:
                data, addr = sock.recvfrom(65535)
            except OSError:
                break
            headers = _parse_headers(data)
            loc = headers.get("location")
            if loc:
                locations.setdefault(addr[0], set()).add(loc)
    finally:
        sock.close()

    findings = []
    for ip, locs in locations.items():
        finding = {"ip": ip, "sources": {"ssdp"}, "device_types": set()}
        for loc in locs:
            _merge_description(loc, finding)
        findings.append(finding)
    return findings


def _parse_headers(data: bytes) -> dict:
    headers = {}
    for line in data.decode("utf-8", "replace").split("\r\n")[1:]:
        if ":" in line:
            key, _, value = line.partition(":")
            headers[key.strip().lower()] = value.strip()
    return headers


def _localname(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]  # drop the {namespace} prefix


def _merge_description(location: str, finding: dict) -> None:
    try:
        with urlopen(location, timeout=3) as resp:
            raw = resp.read()
    except Exception:
        return
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        return

    fields = {}
    for el in root.iter():
        name = _localname(el.tag)
        if name in ("friendlyName", "manufacturer", "modelName",
                    "modelNumber", "deviceType") and el.text:
            fields.setdefault(name, el.text.strip())
        if name == "deviceType" and el.text:
            finding["device_types"].add(el.text.strip())

    finding.setdefault("friendly_name", fields.get("friendlyName"))
    finding.setdefault("ssdp_manufacturer", fields.get("manufacturer"))
    model = " ".join(p for p in (fields.get("modelName"),
                                 fields.get("modelNumber")) if p)
    if model:
        finding.setdefault("model", model)
