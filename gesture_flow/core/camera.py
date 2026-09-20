"""
Threaded Webcam Capture - Rock-solid macOS AVFoundation frame acquisition
"""

import cv2
import threading
import time
from typing import Optional, Tuple
import numpy as np


class CameraStream:
    """Captures webcam frames continuously on a dedicated background thread."""

    def __init__(self, device_index: int = 0, width: int = 640, height: int = 480, mirror: bool = True):
        self.device_index = device_index
        self.target_w = width
        self.target_h = height
        self.mirror = mirror

        self._cap: Optional[cv2.VideoCapture] = None
        self._thread: Optional[threading.Thread] = None
        self._lock = threading.Lock()
        self._running = False
        self._frame: Optional[np.ndarray] = None
        self._frame_time = 0.0
        self._new_frame_event = threading.Event()

    def start(self) -> bool:
        if self._running:
            return True

        # Open camera with native backend
        self._cap = cv2.VideoCapture(self.device_index)
        if not self._cap.isOpened():
            self._cap = cv2.VideoCapture(self.device_index, cv2.CAP_AVFOUNDATION)

        if not self._cap.isOpened():
            print(f"[CameraStream] Error: Cannot open camera index {self.device_index}")
            return False

        # Warm up camera sensor for 5-10 frames so exposure/AGC stabilizes
        for _ in range(10):
            ret, test_frame = self._cap.read()
            if ret and test_frame is not None and test_frame.mean() > 1.0:
                break
            time.sleep(0.04)

        self._running = True
        self._thread = threading.Thread(target=self._capture_loop, daemon=True)
        self._thread.start()
        return True

    def _capture_loop(self):
        while self._running:
            if self._cap is None:
                break
            ret, frame = self._cap.read()
            if not ret or frame is None:
                time.sleep(0.01)
                continue

            # Resize if needed to target dimensions
            h, w = frame.shape[:2]
            if w != self.target_w or h != self.target_h:
                frame = cv2.resize(frame, (self.target_w, self.target_h), interpolation=cv2.INTER_LINEAR)

            if self.mirror:
                frame = cv2.flip(frame, 1)

            with self._lock:
                self._frame = frame
                self._frame_time = time.time()
                self._new_frame_event.set()

    def read(self, timeout: float = 0.1) -> Tuple[bool, Optional[np.ndarray]]:
        """Returns the latest captured frame."""
        self._new_frame_event.wait(timeout)
        self._new_frame_event.clear()
        with self._lock:
            if self._frame is not None:
                return True, self._frame.copy()
            return False, None

    def stop(self):
        self._running = False
        if self._thread is not None:
            self._thread.join(timeout=1.0)
            self._thread = None
        if self._cap is not None:
            self._cap.release()
            self._cap = None
