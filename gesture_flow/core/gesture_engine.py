"""
Gesture Engine - Advanced multi-gesture classification, kinematic swipe detection, and state machine
"""

import time
import math
from typing import Optional, Dict, Any, List, Tuple
from collections import deque
import AppKit

from .hand_tracker import HandPose
from .action_dispatcher import ActionDispatcher
from .filter import PointFilter2D


class GestureEvent:
    def __init__(self, name: str, label: str, action_type: str, payload: Any = None):
        self.name = name
        self.label = label
        self.action_type = action_type
        self.payload = payload
        self.timestamp = time.time()


class GestureEngine:
    """Classifies static poses and dynamic swipes, managing state transitions and debouncing."""

    def __init__(self, config: Dict[str, Any], dispatcher: ActionDispatcher):
        self.config = config
        self.dispatcher = dispatcher

        engine_cfg = config.get("engine", {})
        self.min_displacement = engine_cfg.get("swipe_min_displacement", 0.07)
        self.max_swipe_duration = engine_cfg.get("swipe_max_duration", 0.35)
        self.direction_ratio = engine_cfg.get("swipe_direction_ratio", 1.4)
        self.swipe_cooldown_sec = engine_cfg.get("swipe_cooldown_sec", 0.35)
        self.hold_duration_sec = engine_cfg.get("gesture_hold_sec", 0.45)

        # Motion buffer: deque of (x, y, timestamp, pose_type)
        self._motion_buffer = deque(maxlen=30)
        self._last_action_time = 0.0
        self._last_triggered_event: Optional[GestureEvent] = None

        # Hold trackers
        self._current_hold_pose: Optional[str] = None
        self._hold_start_time: float = 0.0
        self._hold_triggered = False

        # Mouse & Smoothing
        self._mouse_cfg = config.get("mouse", {})
        self._mouse_filter = PointFilter2D(min_cutoff=1.5, beta=0.015)
        screen = AppKit.NSScreen.mainScreen()
        self._screen_w = screen.frame().size.width if screen else 1920
        self._screen_h = screen.frame().size.height if screen else 1080
        self._last_pinch_click_time = 0.0

    def process(self, pose: Optional[HandPose]) -> Optional[GestureEvent]:
        """Processes current hand pose and returns any triggered GestureEvent."""
        now = time.time()

        if pose is None:
            self._motion_buffer.clear()
            self._current_hold_pose = None
            self._hold_triggered = False
            self._mouse_filter.reset()
            return None

        # Identify Static Pose Type
        ext = pose.extended_fingers
        is_two_finger = ext["index"] and ext["middle"] and not ext["ring"] and not ext["pinky"]
        is_one_finger = ext["index"] and not ext["middle"] and not ext["ring"] and not ext["pinky"]
        is_open_hand = pose.finger_count >= 4
        is_fist = pose.finger_count == 0
        is_thumbs_up = ext["thumb"] and not ext["index"] and not ext["middle"] and not ext["ring"] and not ext["pinky"] and (pose.landmarks[4][1] < pose.landmarks[2][1])
        is_thumbs_down = ext["thumb"] and not ext["index"] and not ext["middle"] and not ext["ring"] and not ext["pinky"] and (pose.landmarks[4][1] > pose.landmarks[2][1])

        # 1. Check Dynamic Swipes (Only if cooldown elapsed)
        if now - self._last_action_time >= self.swipe_cooldown_sec:
            # Track index tip position
            idx_tip = pose.landmarks[8]
            self._motion_buffer.append((idx_tip[0], idx_tip[1], now, is_two_finger, is_open_hand))

            # Prune old samples
            while self._motion_buffer and now - self._motion_buffer[0][2] > self.max_swipe_duration:
                self._motion_buffer.popleft()

            if len(self._motion_buffer) >= 3:
                start_x, start_y, start_t, start_two, start_open = self._motion_buffer[0]
                end_x, end_y, end_t, _, _ = self._motion_buffer[-1]

                dx = end_x - start_x
                dy = end_y - start_y
                dt = end_t - start_t

                if 0.04 <= dt <= self.max_swipe_duration:
                    abs_dx = abs(dx)
                    abs_dy = abs(dy)
                    total_disp = max(abs_dx, abs_dy)

                    if total_disp >= self.min_displacement:
                        event = None
                        # Horizontal swipe
                        if abs_dx > abs_dy * self.direction_ratio:
                            if is_two_finger or start_two:
                                if dx > 0:
                                    event = self._create_event("two_finger_swipe_right", "✌️ Next Tab (⌥⌘→)")
                                else:
                                    event = self._create_event("two_finger_swipe_left", "✌️ Prev Tab (⌥⌘←)")
                            elif is_open_hand or start_open:
                                if dx > 0:
                                    event = self._create_event("open_hand_swipe_right", "🖐 Desktop Right (⌃→)")
                                else:
                                    event = self._create_event("open_hand_swipe_left", "🖐 Desktop Left (⌃←)")

                        # Vertical swipe
                        elif abs_dy > abs_dx * self.direction_ratio:
                            if is_two_finger or start_two:
                                if dy > 0:  # Moving down in image
                                    event = self._create_event("two_finger_swipe_down", "✌️ Minimize (⌘M)")
                                else:       # Moving up in image
                                    event = self._create_event("two_finger_swipe_up", "✌️ Fullscreen (⌃⌘F)")
                            elif is_open_hand or start_open:
                                if dy < 0:  # Moving up
                                    event = self._create_event("open_hand_swipe_up", "🖐 Mission Control (⌃↑)")
                                else:       # Moving down
                                    event = self._create_event("open_hand_swipe_down", "🖐 App Exposé (⌃↓)")

                        if event:
                            self._execute_event(event)
                            self._motion_buffer.clear()
                            self._last_action_time = now
                            return event

        # 2. Check Static Hold Gestures (Hold for >0.45s)
        current_pose = None
        if is_open_hand and (now - self._last_action_time > 0.6):
            current_pose = "open_palm_hold"
        elif is_fist:
            current_pose = "fist_hold"
        elif is_thumbs_up:
            current_pose = "thumbs_up"
        elif is_thumbs_down:
            current_pose = "thumbs_down"

        if current_pose is not None:
            if self._current_hold_pose == current_pose:
                hold_time = now - self._hold_start_time
                if hold_time >= self.hold_duration_sec and not self._hold_triggered:
                    self._hold_triggered = True
                    self._last_action_time = now

                    labels = {
                        "open_palm_hold": "🖐 Play/Pause Media",
                        "fist_hold": "✊ Show Desktop (⌘F3)",
                        "thumbs_up": "👍 Volume Up (+10%)",
                        "thumbs_down": "👎 Volume Down (-10%)",
                    }
                    event = self._create_event(current_pose, labels.get(current_pose, current_pose))
                    self._execute_event(event)
                    return event
            else:
                self._current_hold_pose = current_pose
                self._hold_start_time = now
                self._hold_triggered = False
        else:
            self._current_hold_pose = None
            self._hold_triggered = False

        # 3. Virtual Mouse (When 1 finger pointing)
        if self._mouse_cfg.get("enabled", True) and is_one_finger:
            idx_tip = pose.landmarks[8]
            # Map normalized (0.2-0.8) to full screen coordinates
            norm_x = (idx_tip[0] - 0.15) / 0.7
            norm_y = (idx_tip[1] - 0.15) / 0.7
            norm_x = max(0.0, min(1.0, norm_x))
            norm_y = max(0.0, min(1.0, norm_y))

            target_x = norm_x * self._screen_w
            target_y = norm_y * self._screen_h

            smooth_x, smooth_y = self._mouse_filter.filter(target_x, target_y, now)
            self.dispatcher.move_mouse(smooth_x, smooth_y)

            # Check Pinch Click
            pinch_thresh = self._mouse_cfg.get("pinch_click_threshold", 0.04)
            if pose.pinch_distance < 0.22 and (now - self._last_pinch_click_time > 0.35):
                self._last_pinch_click_time = now
                self.dispatcher.mouse_click("left")
                event = GestureEvent("mouse_click", "👌 Left Click", "mouse")
                return event

        return None

    def _create_event(self, name: str, label: str) -> GestureEvent:
        mapping = self.config.get("gestures", {}).get(name, {})
        action = mapping.get("action", name)
        event = GestureEvent(name=name, label=label, action_type=action, payload=mapping)
        self._last_triggered_event = event
        return event

    def _execute_event(self, event: GestureEvent):
        """Executes the mapped system action for the event."""
        action = event.action_type
        payload = event.payload or {}

        if action == "next_tab":
            self.dispatcher.next_tab()
        elif action == "prev_tab":
            self.dispatcher.prev_tab()
        elif action == "minimize_window":
            self.dispatcher.minimize_window()
        elif action == "fullscreen_toggle":
            self.dispatcher.fullscreen_toggle()
        elif action == "close_tab":
            self.dispatcher.close_tab()
        elif action == "switch_desktop_right":
            self.dispatcher.switch_desktop_right()
        elif action == "switch_desktop_left":
            self.dispatcher.switch_desktop_left()
        elif action == "mission_control":
            self.dispatcher.mission_control()
        elif action == "app_expose":
            self.dispatcher.app_expose()
        elif action == "show_desktop":
            self.dispatcher.show_desktop()
        elif action == "switch_app":
            self.dispatcher.switch_app()
        elif action == "play_pause":
            self.dispatcher.play_pause_media()
        elif action == "volume_up":
            self.dispatcher.set_volume_delta(payload.get("step", 10))
        elif action == "volume_down":
            self.dispatcher.set_volume_delta(payload.get("step", -10))
        elif "keys" in payload:
            self.dispatcher.send_hotkey(payload["keys"])
