"""
One-Euro ($1€$) Filter for Adaptive Real-Time Anti-Jitter Smoothing
Casiez et al., CHI 2012: "1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input in Human-Computer Interaction"
"""

import math
import time


class LowPassFilter:
    def __init__(self, alpha: float = 0.5):
        self._alpha = alpha
        self._last_val = None

    def filter(self, val: float, alpha: float = None) -> float:
        if alpha is not None:
            self._alpha = alpha
        if self._last_val is None:
            self._last_val = val
            return val
        res = self._alpha * val + (1.0 - self._alpha) * self._last_val
        self._last_val = res
        return res

    def reset(self):
        self._last_val = None


class OneEuroFilter:
    """
    Adaptive filter:
    - High smoothing (low jitter) when moving slowly or holding still.
    - Low smoothing (zero lag) when moving quickly.
    """

    def __init__(self, min_cutoff: float = 1.0, beta: float = 0.007, d_cutoff: float = 1.0):
        self.min_cutoff = min_cutoff
        self.beta = beta
        self.d_cutoff = d_cutoff
        self._x_filt = LowPassFilter()
        self._dx_filt = LowPassFilter()
        self._last_time = None

    def _alpha(self, cutoff: float, dt: float) -> float:
        tau = 1.0 / (2.0 * math.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)

    def filter(self, x: float, timestamp: float = None) -> float:
        if timestamp is None:
            timestamp = time.time()

        if self._last_time is None:
            self._last_time = timestamp
            return self._x_filt.filter(x, 1.0)

        dt = max(1e-4, timestamp - self._last_time)
        self._last_time = timestamp

        # Estimate derivative
        dx = (x - (self._x_filt._last_val or x)) / dt
        edx = self._dx_filt.filter(dx, self._alpha(self.d_cutoff, dt))

        # Dynamic cutoff
        cutoff = self.min_cutoff + self.beta * abs(edx)
        return self._x_filt.filter(x, self._alpha(cutoff, dt))

    def reset(self):
        self._x_filt.reset()
        self._dx_filt.reset()
        self._last_time = None


class PointFilter2D:
    """Convenience wrapper for 2D (x, y) filtering."""

    def __init__(self, min_cutoff: float = 1.2, beta: float = 0.008):
        self.fx = OneEuroFilter(min_cutoff, beta)
        self.fy = OneEuroFilter(min_cutoff, beta)

    def filter(self, x: float, y: float, timestamp: float = None) -> tuple[float, float]:
        return (
            self.fx.filter(x, timestamp),
            self.fy.filter(y, timestamp)
        )

    def reset(self):
        self.fx.reset()
        self.fy.reset()
