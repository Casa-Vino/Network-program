"""Device fingerprinting: score fused signals against a signature database."""

from .engine import Match, annotate, identify

__all__ = ["Match", "annotate", "identify"]
