"""Driver registry: select and run the drivers that apply to a device."""

from __future__ import annotations

from .base import Driver, ProbeResult

_DRIVERS: list[Driver] = []


def register(driver: Driver) -> None:
    _DRIVERS.append(driver)


def drivers_for(device) -> list[Driver]:
    return [d for d in _DRIVERS if d.applies_to(device)]


def probe_device(device, **opts) -> list[ProbeResult]:
    results = []
    for driver in drivers_for(device):
        result = driver.probe(device, **opts)
        if result is not None:
            results.append(result)
    return results
