"""Read-only HTTP admin-interface probe.

For a device it can reach, this reports:
  * whether a web admin interface answers, and on which port/scheme;
  * how it gates access -- HTTP Basic/Digest, a login form, or nothing;
  * (opt-in, ownership-gated) whether it still accepts a well-known default
    credential over HTTP Basic/Digest.

What it never does:
  * change any device configuration -- every request is a GET;
  * auto-submit login *forms* -- those are device-specific and POSTing to
    them risks side effects and lockouts, so a form is reported, not tested;
  * route through the agent proxy -- LAN targets are reached directly
    (ProxyHandler({})).

The default-credential check exists to audit your own devices. The caller
must pass attempt_defaults=True AND assert ownership (the CLI requires an
explicit flag); without that, the probe only observes and never sends a
credential.
"""

from __future__ import annotations

import re
import socket
import urllib.error
import urllib.request

from .base import Driver, ProbeResult
from .candidates import DEFAULTS

_DEFAULT_PORTS = [(80, "http"), (443, "https"), (8080, "http"), (8443, "https")]
_ADMIN_HINTS = ("router", "gateway", "admin", "login", "setup", "configuration",
                "management", "modem", "access point")
_PASSWORD_FIELD = re.compile(r'type=["\']?password', re.I)
_TITLE = re.compile(r"<title[^>]*>(.*?)</title>", re.I | re.S)


class HttpAdminDriver(Driver):
    name = "http-admin"

    def applies_to(self, device) -> bool:  # noqa: ARG002
        # Generic: many devices expose a web UI. Probing is opt-in at the
        # scan level, so there is no need to narrow by category here.
        return True

    def probe(self, device, attempt_defaults: bool = False, candidates=None,
              timeout: float = 3.0, ports=None, **_) -> ProbeResult | None:
        result = ProbeResult(driver=self.name, ip=device.ip)
        for port, scheme in (ports or _DEFAULT_PORTS):
            url = f"{scheme}://{device.ip}:{port}/"
            observed = _get(url, timeout)
            if observed is None:
                continue  # port closed / no HTTP here

            result.reachable = True
            status, headers, body = observed
            auth = _auth_scheme(headers)
            result.details = {
                "url": url,
                "status": status,
                "server": headers.get("Server", ""),
                "auth": auth or "none",
                "title": _title(body),
            }
            self._assess(result, url, status, auth, body,
                         attempt_defaults, candidates, timeout)
            return result  # first responding admin endpoint wins

        return result  # reachable stays False

    def _assess(self, result, url, status, auth, body,
                attempt_defaults, candidates, timeout) -> None:
        looks_admin = _looks_admin(body, result.details["title"])

        if auth in ("basic", "digest"):
            result.add("info", f"HTTP {auth} auth required at {url}")
            if attempt_defaults:
                self._check_defaults(result, url, auth, candidates, timeout)
            else:
                result.add("info", "re-run with the default-credential audit "
                                    "enabled to test this (your devices only)")
            return

        if status == 200 and _PASSWORD_FIELD.search(body):
            result.add("info", f"login form present at {url} "
                               "(not auto-tested)")
            return

        if status == 200 and looks_admin:
            result.add("alert", f"admin interface served WITHOUT "
                               f"authentication at {url} -- anyone on the "
                               "network can reach it")
            return

        if status == 200:
            result.add("warn", f"web server responds at {url} "
                              f"(title: {result.details['title'] or 'n/a'})")

    def _check_defaults(self, result, url, auth, candidates, timeout) -> None:
        pairs = candidates if candidates is not None else DEFAULTS
        accepted = None
        for user, pw in pairs:
            if _try_auth(url, auth, user, pw, timeout):
                accepted = (user, pw)
                break
        if accepted:
            shown = f"{accepted[0] or '<blank>'}/{accepted[1] or '<blank>'}"
            result.add("alert", f"ACCEPTS DEFAULT CREDENTIALS ({shown}) -- "
                               "change this device's password now")
        else:
            result.add("info", "none of the tested default credentials were "
                              "accepted")


def _opener(*handlers):
    # ProxyHandler({}) disables any configured proxy -- LAN hosts are direct.
    return urllib.request.build_opener(urllib.request.ProxyHandler({}),
                                       *handlers)


def _get(url, timeout):
    req = urllib.request.Request(url, method="GET",
                                 headers={"User-Agent": "netinv-probe"})
    try:
        with _opener().open(req, timeout=timeout) as resp:
            return resp.status, resp.headers, _read(resp)
    except urllib.error.HTTPError as err:  # 4xx/5xx still carry useful headers
        return err.code, err.headers, _read(err)
    except (urllib.error.URLError, OSError, socket.timeout, ValueError):
        return None


def _read(resp) -> str:
    try:
        return resp.read(65536).decode("utf-8", "replace")
    except OSError:
        return ""


def _try_auth(url, auth, user, pw, timeout) -> bool:
    mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
    mgr.add_password(None, url, user, pw)
    handler = (urllib.request.HTTPBasicAuthHandler(mgr) if auth == "basic"
               else urllib.request.HTTPDigestAuthHandler(mgr))
    try:
        with _opener(handler).open(url, timeout=timeout) as resp:
            return resp.status == 200
    except urllib.error.HTTPError:
        return False  # 401 -> rejected
    except (urllib.error.URLError, OSError, socket.timeout, ValueError):
        return False


def _auth_scheme(headers) -> str | None:
    value = headers.get("WWW-Authenticate", "")
    low = value.lower()
    if low.startswith("basic"):
        return "basic"
    if low.startswith("digest"):
        return "digest"
    return None


def _title(body) -> str:
    m = _TITLE.search(body)
    return m.group(1).strip() if m else ""


def _looks_admin(body, title) -> bool:
    hay = (title + " " + body[:4096]).lower()
    return any(hint in hay for hint in _ADMIN_HINTS)
