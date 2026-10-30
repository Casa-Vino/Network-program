"""ARP-based MAC resolution (Linux).

SSDP and mDNS give us IPs; to look up a manufacturer we need the MAC. The
kernel already learns MACs for hosts we talk to, so we optionally nudge the
cache with a ping sweep, then read it from /proc/net/arp and `ip neigh`.
"""

from __future__ import annotations

import subprocess
from concurrent.futures import ThreadPoolExecutor

_INVALID = {"00:00:00:00:00:00"}


def populate(ips, workers: int = 32) -> None:
    """Ping each IP once so the kernel ARP cache learns its MAC."""
    def ping(ip: str) -> None:
        try:
            subprocess.run(
                ["ping", "-c", "1", "-W", "1", ip],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=3,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass

    ips = list(ips)
    if not ips:
        return
    with ThreadPoolExecutor(max_workers=min(workers, len(ips))) as pool:
        list(pool.map(ping, ips))


def table() -> dict[str, str]:
    """Return {ip: mac} merged from /proc/net/arp and `ip neigh`."""
    result: dict[str, str] = {}
    result.update(_from_proc())
    for ip, mac in _from_ip_neigh().items():
        result.setdefault(ip, mac)
    return result


def _from_proc() -> dict[str, str]:
    out: dict[str, str] = {}
    try:
        with open("/proc/net/arp") as fh:
            next(fh, None)  # header
            for line in fh:
                parts = line.split()
                if len(parts) >= 4:
                    ip, mac = parts[0], parts[3].lower()
                    if mac not in _INVALID:
                        out[ip] = mac
    except OSError:
        pass
    return out


def _from_ip_neigh() -> dict[str, str]:
    out: dict[str, str] = {}
    try:
        proc = subprocess.run(["ip", "neigh", "show"],
                              capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return out
    for line in proc.stdout.splitlines():
        parts = line.split()
        if "lladdr" in parts:
            ip = parts[0]
            mac = parts[parts.index("lladdr") + 1].lower()
            if mac not in _INVALID:
                out[ip] = mac
    return out
