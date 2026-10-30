"""Drivers layer: opt-in, device-class-specific access modules.

Importing this package registers the built-in drivers. The one shipped driver
(http_admin) is read-only. Add new drivers by subclassing base.Driver and
calling registry.register().
"""

from . import registry
from .base import Driver, ProbeResult
from .http_admin import HttpAdminDriver

registry.register(HttpAdminDriver())

__all__ = ["Driver", "ProbeResult", "registry", "HttpAdminDriver"]
