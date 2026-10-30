"""mDNS / DNS-SD discovery, dependency-free.

Sends a PTR query for the service-enumeration name and parses whatever
responders send back, chaining the records to attach service types to IPs:

    PTR  (service type)  -> service instance
    SRV  (instance)      -> target host + port
    A    (host)          -> IPv4 address

The result is per-IP: a hostname and the set of advertised service types.
This is a focused parser (enough to identify devices), not a full resolver.

Caveat: on Linux with avahi/systemd-resolved already bound to UDP 5353 we
rely on SO_REUSEPORT to share the socket; if the bind still fails we fall
back to an ephemeral port and only catch unicast (QU) replies.
"""

from __future__ import annotations

import select
import socket
import struct
import time

MDNS_ADDR = "224.0.0.251"
MDNS_PORT = 5353

_ENUM = "_services._dns-sd._udp.local"


def discover(timeout: float = 4.0) -> list[dict]:
    sock = _open_socket()
    if sock is None:
        return []

    a_records: dict[str, set[str]] = {}       # host -> ips
    srv: dict[str, str] = {}                    # instance -> host
    services: dict[str, set[str]] = {}          # host -> service types

    try:
        query = _build_query(_ENUM)
        sock.sendto(query, (MDNS_ADDR, MDNS_PORT))

        deadline = time.time() + timeout
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                break
            ready, _, _ = select.select([sock], [], [], remaining)
            if not ready:
                break
            try:
                data, _ = sock.recvfrom(65535)
            except OSError:
                break
            _parse_packet(data, a_records, srv, services)
    finally:
        sock.close()

    # Fold host-keyed data down onto IPs.
    findings: dict[str, dict] = {}
    for host, ips in a_records.items():
        host_svcs = services.get(host, set())
        for ip in ips:
            f = findings.setdefault(ip, {
                "ip": ip, "sources": {"mdns"},
                "services": set(), "hostname": _trim(host),
            })
            f["services"].update(host_svcs)

    # Services whose SRV target we resolved to a known host.
    for instance, host in srv.items():
        for ip in a_records.get(host, ()):
            findings.setdefault(ip, {
                "ip": ip, "sources": {"mdns"},
                "services": set(), "hostname": _trim(host),
            })

    return list(findings.values())


def _open_socket():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except OSError:
            pass
    bound = False
    try:
        sock.bind(("", MDNS_PORT))
        bound = True
    except OSError:
        try:
            sock.bind(("", 0))  # ephemeral: QU replies only
        except OSError:
            sock.close()
            return None
    if bound:
        try:
            mreq = struct.pack("4sl", socket.inet_aton(MDNS_ADDR),
                               socket.INADDR_ANY)
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
        except OSError:
            pass
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
    return sock


def _build_query(name: str) -> bytes:
    header = struct.pack(">HHHHHH", 0, 0, 1, 0, 0, 0)  # id=0, 1 question
    question = _encode_name(name) + struct.pack(">HH", 12, 0x8001)  # PTR, QU|IN
    return header + question


def _encode_name(name: str) -> bytes:
    out = bytearray()
    for label in name.split("."):
        out.append(len(label))
        out += label.encode("utf-8")
    out.append(0)
    return bytes(out)


def _read_name(data: bytes, offset: int) -> tuple[str, int]:
    labels = []
    jumped = False
    end = offset
    while True:
        length = data[offset]
        if length & 0xC0 == 0xC0:  # compression pointer
            pointer = ((length & 0x3F) << 8) | data[offset + 1]
            if not jumped:
                end = offset + 2
            offset = pointer
            jumped = True
            continue
        offset += 1
        if length == 0:
            if not jumped:
                end = offset
            break
        labels.append(data[offset:offset + length].decode("utf-8", "replace"))
        offset += length
    return ".".join(labels), end


def _parse_packet(data, a_records, srv, services) -> None:
    try:
        (_id, _flags, qd, an, ns, ar) = struct.unpack(">HHHHHH", data[:12])
    except struct.error:
        return
    offset = 12
    try:
        for _ in range(qd):  # skip questions
            _, offset = _read_name(data, offset)
            offset += 4
        for _ in range(an + ns + ar):
            name, offset = _read_name(data, offset)
            rtype, _rclass, _ttl, rdlen = struct.unpack(">HHIH",
                                                        data[offset:offset + 10])
            offset += 10
            rdata = data[offset:offset + rdlen]
            _handle_record(data, offset, name, rtype, rdata,
                           a_records, srv, services)
            offset += rdlen
    except (struct.error, IndexError):
        return


def _handle_record(data, offset, name, rtype, rdata,
                   a_records, srv, services) -> None:
    if rtype == 1 and len(rdata) == 4:                 # A
        ip = socket.inet_ntoa(rdata)
        a_records.setdefault(name, set()).add(ip)
    elif rtype == 12:                                   # PTR
        target, _ = _read_name(data, offset)
        if _is_service_type(name) and name != _ENUM:
            services.setdefault(target, set())  # placeholder; linked via SRV
            # Record the service type against the instance's eventual host.
            _remember_service(name, target, srv, services)
    elif rtype == 33:                                   # SRV
        # rdata: priority(2) weight(2) port(2) target(name)
        target, _ = _read_name(data, offset + 6)
        srv[name] = target
        # Attach any service type already seen for this instance.
        stype = _service_type_of(name)
        if stype:
            services.setdefault(target, set()).add(stype)


def _remember_service(stype, instance, srv, services) -> None:
    host = srv.get(instance)
    if host:
        services.setdefault(host, set()).add(stype)


def _service_type_of(instance: str) -> str | None:
    # instance "Living Room._airplay._tcp.local" -> "_airplay._tcp.local"
    idx = instance.find("._")
    if idx != -1:
        return instance[idx + 1:]
    return None


def _is_service_type(name: str) -> bool:
    return name.endswith("._tcp.local") or name.endswith("._udp.local")


def _trim(host: str) -> str:
    return host[:-6] if host.endswith(".local") else host
