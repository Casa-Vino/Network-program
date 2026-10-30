"""CLI: python -m netinv [--timeout N] [--oui PATH] [--json] [--no-ping]"""

from __future__ import annotations

import argparse
import json
import sys

from .scan import scan


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="netinv",
        description="Discover and fingerprint devices on the local network.",
    )
    parser.add_argument("--timeout", type=float, default=4.0,
                        help="seconds to listen for SSDP/mDNS (default 4)")
    parser.add_argument("--oui", metavar="PATH",
                        help="IEEE oui.txt or Wireshark manuf file for full "
                             "vendor coverage")
    parser.add_argument("--json", action="store_true",
                        help="emit JSON instead of a table")
    parser.add_argument("--no-ping", action="store_true",
                        help="skip the ARP-priming pings of known hosts")
    parser.add_argument("--sweep", action="store_true",
                        help="actively ping-sweep the local subnet to find "
                             "hosts that stay silent on multicast")
    parser.add_argument("--max-hosts", type=int, default=4096,
                        help="cap on addresses swept (default 4096)")
    parser.add_argument("--probe", action="store_true",
                        help="probe each device's HTTP admin interface "
                             "(read-only: reachability + auth scheme)")
    parser.add_argument("--probe-defaults", action="store_true",
                        help="also audit whether devices still accept known "
                             "default credentials (requires --i-own-these)")
    parser.add_argument("--i-own-these", action="store_true",
                        help="assert you own / are authorized to manage every "
                             "device on this network")
    parser.add_argument("--candidates", metavar="PATH",
                        help="file of user:password candidates for the audit")
    args = parser.parse_args(argv)

    if args.probe_defaults and not args.i_own_these:
        parser.error("--probe-defaults requires --i-own-these: the default-"
                     "credential audit is only for devices you are authorized "
                     "to manage.")
    if args.probe_defaults:
        args.probe = True
        print("# Default-credential audit enabled for devices you asserted "
              "you own. Read-only: no configuration is changed.\n")

    candidates = None
    if args.candidates:
        from .drivers.candidates import load_candidates
        candidates = load_candidates(args.candidates)

    inv = scan(timeout=args.timeout, oui_path=args.oui,
               do_ping=not args.no_ping, do_sweep=args.sweep,
               max_hosts=args.max_hosts, probe=args.probe,
               probe_defaults=args.probe_defaults, candidates=candidates)
    rows = [d.to_row() for d in inv.devices()]

    if args.json:
        json.dump(rows, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        _print_table(rows)
        if args.probe:
            _print_findings(inv)
    return 0


def _print_findings(inv) -> None:
    _sev_mark = {"alert": "[!]", "warn": "[~]", "info": "[ ]"}
    lines = []
    for dev in inv.devices():
        for probe in dev.probes:
            if not probe.reachable:
                continue
            for severity, message in probe.findings:
                lines.append(f"  {_sev_mark.get(severity, '[ ]')} "
                             f"{dev.ip:15} {message}")
    print("\nProbe findings")
    print("-" * 14)
    if lines:
        print("\n".join(lines))
        alerts = sum(1 for d in inv.devices() for p in d.probes for m in p.alerts)
        if alerts:
            print(f"\n{alerts} device(s) with a security weakness to fix "
                  "([!] lines above).")
    else:
        print("  no reachable HTTP admin interfaces found.")


def _print_table(rows: list[dict]) -> None:
    if not rows:
        print("No devices discovered. On a container/VM, multicast may not "
              "reach the LAN -- run this on a host joined to the network.")
        return
    cols = [("ip", "IP"), ("mac", "MAC"), ("manufacturer", "MANUFACTURER"),
            ("name", "NAME"), ("model", "MODEL"), ("role", "ROLE"),
            ("conf", "CONF"), ("sources", "SRC")]
    widths = {k: len(h) for k, h in cols}
    for row in rows:
        for k, _ in cols:
            widths[k] = max(widths[k], len(str(row.get(k, ""))))
    line = "  ".join(h.ljust(widths[k]) for k, h in cols)
    print(line)
    print("  ".join("-" * widths[k] for k, _ in cols))
    for row in rows:
        print("  ".join(str(row.get(k, "")).ljust(widths[k]) for k, _ in cols))
    print(f"\n{len(rows)} device(s).")


if __name__ == "__main__":
    raise SystemExit(main())
