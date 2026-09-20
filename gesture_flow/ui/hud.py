"""
HUD Visualizer - Real-time camera overlay, gesture feedback, and system status
"""

import time
from typing import Optional, List, Tuple
import cv2
import numpy as np

from ..core.hand_tracker import HandPose
from ..core.gesture_engine import GestureEvent


class GestureHUD:
    """Renders a sleek on-screen HUD overlay with gesture feedback, icons, and status."""

    def __init__(self, window_name: str = "GestureFlow HUD"):
        self.window_name = window_name
        self._last_event: Optional[GestureEvent] = None
        self._event_display_until: float = 0.0
        self._fps_history = []
        self._last_frame_time = time.time()

    def update_event(self, event: GestureEvent, duration: float = 1.2):
        self._last_event = event
        self._event_display_until = time.time() + duration

    def render(self, frame: np.ndarray, pose: Optional[HandPose], fps: float = 0.0) -> np.ndarray:
        """Draws HUD elements onto the frame."""
        h, w, _ = frame.shape
        overlay = frame.copy()
        now = time.time()

        # 1. Draw Header Bar (Semi-transparent dark strip)
        cv2.rectangle(overlay, (0, 0), (w, 50), (20, 20, 25), -1)
        cv2.addWeighted(overlay, 0.75, frame, 0.25, 0, frame)

        # Title & Status
        cv2.putText(frame, "GestureFlow", (15, 32), cv2.FONT_HERSHEY_DUPLEX, 0.8, (0, 255, 180), 2, cv2.LINE_AA)

        # FPS indicator
        fps_text = f"{int(fps)} FPS"
        cv2.putText(frame, fps_text, (w - 100, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (180, 180, 180), 1, cv2.LINE_AA)

        # 2. Hand State Badge
        if pose is not None:
            # Active tracking dot
            cv2.circle(frame, (185, 27), 6, (0, 255, 0), -1, cv2.LINE_AA)
            state_text = f"Hand Active ({pose.finger_count}f)"
            cv2.putText(frame, state_text, (200, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (220, 220, 220), 1, cv2.LINE_AA)
        else:
            cv2.circle(frame, (185, 27), 6, (100, 100, 100), -1, cv2.LINE_AA)
            cv2.putText(frame, "No Hand (Idle)", (200, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (120, 120, 120), 1, cv2.LINE_AA)

        # 3. Action / Gesture Trigger Banner (Animated Bottom Pop-up)
        if self._last_event is not None and now < self._event_display_until:
            progress = max(0.0, min(1.0, (self._event_display_until - now) / 1.2))
            alpha = min(1.0, progress * 2.0)

            banner_y = h - 65
            sub_overlay = frame.copy()
            # Gradient colored banner
            cv2.rectangle(sub_overlay, (20, banner_y), (w - 20, banner_y + 48), (35, 30, 20), -1)
            cv2.rectangle(sub_overlay, (20, banner_y), (w - 20, banner_y + 48), (0, 220, 255), 2)
            cv2.addWeighted(sub_overlay, alpha * 0.85, frame, 1.0 - alpha * 0.85, 0, frame)

            # Event label
            text = f"ACTION: {self._last_event.label}"
            cv2.putText(frame, text, (35, banner_y + 32), cv2.FONT_HERSHEY_DUPLEX, 0.7, (255, 255, 255), 2, cv2.LINE_AA)

        # 4. Footer Guide
        guide_text = "[q] Quit  |  [h] Toggle HUD  |  [2-Fingers] Swipe Tab / Minimize"
        cv2.putText(frame, guide_text, (15, h - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (150, 150, 150), 1, cv2.LINE_AA)

        return frame

    def show(self, frame: np.ndarray) -> int:
        """Displays the frame and returns key press code."""
        cv2.imshow(self.window_name, frame)
        return cv2.waitKey(1) & 0xFF

    def close(self):
        cv2.destroyAllWindows()
