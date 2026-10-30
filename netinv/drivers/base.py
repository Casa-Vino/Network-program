"""Driver interface and the shared probe result.

A driver knows how to *talk to* a class of device. Drivers are selected per
device (by classification/category) and are strictly layered above discovery
and fingerprinting -- they run only when the caller opts in.

This scaffold's one shipped driver (http_admin) is read-only: it reports what
it sees and never changes device state. The interface leaves room for write
drivers later, but anything that mutates a device belongs behind its own,
clearly separate opt-in.

Findings are (severity, message) pairs:
    info   a neutral fact ("HTTP auth present")
    warn   worth a look ("admin page reachable")
    alert  a real weakness to fix ("accepts default credentials")
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class ProbeResult:
    driver: str
    ip: str
    reachable: bool = False
    details: dict = field(default_factory=dict)
    findings: list = field(default_factory=list)  # list[(severity, message)]
    error: str | None = None

    def add(self, severity: str, message: str) -> None:
        self.findings.append((severity, message))

    @property
    def alerts(self) -> list:
        return [m for sev, m in self.findings if sev == "alert"]

    def to_dict(self) -> dict:
        return {
            "driver": self.driver,
            "ip": self.ip,
            "reachable": self.reachable,
            "details": self.details,
            "findings": [{"severity": s, "message": m} for s, m in self.findings],
            "error": self.error,
        }


class Driver:
    """Base class. Subclasses set `name`, and implement applies_to/probe."""

    name = "base"

    def applies_to(self, device) -> bool:  # noqa: ARG002
        raise NotImplementedError

    def probe(self, device, **opts) -> ProbeResult | None:  # noqa: ARG002
        raise NotImplementedError
