"""Known-default credential candidates for the ownership audit.

This is deliberately a *tiny* set of the universal, textbook defaults that
every "secure your router" guide lists -- enough to answer "is this device
still wide open?" for your own gear. It is not a device-targeted credential
database. For a real audit, point --candidates at a larger list you are
authorized to use (e.g. the public SecLists default-credentials files), in
the same `user:password` per line format.

A blank field means an empty username or password.
"""

DEFAULTS = [
    ("admin", "admin"),
    ("admin", "password"),
    ("admin", ""),
    ("", ""),
    ("root", "root"),
    ("user", "user"),
    ("admin", "1234"),
]


def load_candidates(path: str) -> list:
    """Load `user:password` pairs, one per line. '#' lines are comments."""
    pairs = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.lstrip().startswith("#"):
                continue
            user, sep, pw = line.partition(":")
            if sep:
                pairs.append((user, pw))
    return pairs
