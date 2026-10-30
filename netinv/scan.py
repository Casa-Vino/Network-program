"""Orchestrator: run the discovery modules and fuse them into an Inventory.

SSDP and mDNS each block for their timeout, so we run them in parallel and
pay the wait once. An optional active sweep surfaces hosts that stay silent
on multicast. Then we resolve MACs (ARP) and manufacturers (OUI), and finally
fingerprint each fused record.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

from . import fingerprint
from .discovery import arp, mdns, oui, ssdp, sweep
from .drivers import registry
from .model import Inventory


def scan(timeout: float = 4.0, oui_path: str | None = None,
         do_ping: bool = True, do_sweep: bool = False,
         max_hosts: int = 4096, probe: bool = False,
         probe_defaults: bool = False, candidates=None) -> Inventory:
    inv = Inventory()

    with ThreadPoolExecutor(max_workers=2) as pool:
        ssdp_future = pool.submit(ssdp.discover, timeout)
        mdns_future = pool.submit(mdns.discover, timeout)
        ssdp_findings = ssdp_future.result()
        mdns_findings = mdns_future.result()

    for finding in ssdp_findings + mdns_findings:
        inv.add(finding)

    if do_sweep:
        for finding in sweep.discover(max_hosts=max_hosts):
            inv.add(finding)

    if oui_path:
        oui.load_file(oui_path)

    if do_ping:
        arp.populate(inv.ips())
    for ip, mac in arp.table().items():
        if ip in inv._by_ip:
            inv.set_mac(ip, mac)

    for dev in inv.devices():
        if dev.mac and not dev.manufacturer:
            dev.manufacturer = oui.lookup(dev.mac)
        fingerprint.annotate(dev)
        if probe:
            dev.probes = registry.probe_device(
                dev, attempt_defaults=probe_defaults, candidates=candidates)

    return inv
