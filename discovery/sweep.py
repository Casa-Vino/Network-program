"""Active subnet sweep.

SSDP/mDNS only find devices that choose to answer multicast. Plenty of hosts
(a NAS with mDNS off, an IoT plug, a laptop with the firewall up) stay quiet.
A ping sweep across the local subnet surfaces them, and the pings also prime
the kernel ARP cache so arp.table() can then supply their MACs.

Linux-oriented (reads `ip -4 -o addr show`). Address parsing is factored out
so it can be unit-tested without a live interface.
"""

from __future__ import annotations

import ipaddress
import subprocess
from concurrent.futures import ThreadPoolExecutor


def local_subnets() -> list[ipaddress.IPv4Network]:
    try:
        proc = subprocess.run(["ip", "-4", "-o", "addr", "show"],
                              capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return []
    return _parse_addrs(proc.stdout)


def _parse_addrs(text: str) -> list[ipaddress.IPv4Network]:
    nets: list[ipaddress.IPv4Network] = []
    seen: set[str] = set()
    for line in text.splitlines():
        tokens = line.split()
        if "inet" not in tokens:
            continue
        cidr = tokens[tokens.index("inet") + 1]
        try:
            net = ipaddress.ip_network(cidr, strict=False)
        except ValueError:
            continue
        if net.is_loopback or net.is_link_local:
            continue
        key = str(net)
        if key not in seen:
            seen.add(key)
            nets.append(net)
    return nets


def hosts_in(networks, max_hosts: int = 4096) -> tuple[list[str], bool]:
    """Expand networks to host addresses, capped. Returns (hosts, truncated)."""
    hosts: list[str] = []
    truncated = False
    for net in networks:
        for host in net.hosts():
            if len(hosts) >= max_hosts:
                return hosts, True
            hosts.append(str(host))
    return hosts, truncated


def ping_sweep(networks, max_hosts: int = 4096, workers: int = 128):
    """Ping every host in the networks; return (responders, truncated)."""
    hosts, truncated = hosts_in(networks, max_hosts)
    if not hosts:
        return [], truncated

    def ping(ip: str) -> str | None:
        try:
            proc = subprocess.run(
                ["ping", "-c", "1", "-W", "1", ip],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=3,
            )
            return ip if proc.returncode == 0 else None
        except (OSError, subprocess.TimeoutExpired):
            return None

    with ThreadPoolExecutor(max_workers=min(workers, len(hosts))) as pool:
        responders = [ip for ip in pool.map(ping, hosts) if ip]
    return responders, truncated


def discover(max_hosts: int = 4096) -> list[dict]:
    """Return findings for every responding host (IP only; MAC comes later)."""
    responders, _ = ping_sweep(local_subnets(), max_hosts=max_hosts)
    return [{"ip": ip, "sources": {"sweep"}} for ip in responders]
