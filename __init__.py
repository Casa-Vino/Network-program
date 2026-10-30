"""netinv -- a LAN device discovery and fingerprinting core.

Layers (see README):
    discovery/  one module per signal (ssdp, mdns, arp, oui)
    model       Device + Inventory fusion layer
    scan        orchestrator
"""

from .model import Device, Inventory
from .scan import scan

__all__ = ["Device", "Inventory", "scan"]
__version__ = "0.1.0"
