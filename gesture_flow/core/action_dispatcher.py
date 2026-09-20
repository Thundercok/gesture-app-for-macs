"""
macOS Action Dispatcher - Low latency Quartz C-API & AppleScript Event Injection
"""

import time
import subprocess
import threading
from typing import List, Optional
import Quartz

# Mac Virtual Key Codes (Carbon / HIToolbox)
KEY_CODES = {
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
    "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
    "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
    "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
    "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
    "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "tab": 0x30,
    "space": 0x31, "`": 0x32, "delete": 0x33, "enter": 0x24, "return": 0x24, "esc": 0x35,
    "escape": 0x35, "cmd": 0x37, "command": 0x37, "shift": 0x38, "capslock": 0x39,
    "option": 0x3A, "alt": 0x3A, "control": 0x3B, "ctrl": 0x3B, "rightshift": 0x3C,
    "rightoption": 0x3D, "rightcontrol": 0x3E, "f1": 0x7A, "f2": 0x78, "f3": 0x63,
    "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D,
    "f11": 0x67, "f12": 0x6F, "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
}

MODIFIERS = {
    "cmd": Quartz.kCGEventFlagMaskCommand,
    "command": Quartz.kCGEventFlagMaskCommand,
    "shift": Quartz.kCGEventFlagMaskShift,
    "alt": Quartz.kCGEventFlagMaskAlternate,
    "option": Quartz.kCGEventFlagMaskAlternate,
    "ctrl": Quartz.kCGEventFlagMaskControl,
    "control": Quartz.kCGEventFlagMaskControl,
    "fn": Quartz.kCGEventFlagMaskSecondaryFn,
}


class ActionDispatcher:
    """Dispatches native keyboard shortcuts, mouse events, and system commands on macOS."""

    def __init__(self):
        self._lock = threading.Lock()
        self._last_event_time = 0.0

    def send_hotkey(self, keys: List[str]):
        """
        Sends a hotkey combo (e.g. ['cmd', 'alt', 'right'], ['ctrl', 'tab'], ['cmd', 'm']).
        """
        if not keys:
            return

        flags = 0
        main_key = None

        for k in keys:
            k_lower = k.lower().strip()
            if k_lower in MODIFIERS:
                flags |= MODIFIERS[k_lower]
            elif k_lower in KEY_CODES:
                main_key = KEY_CODES[k_lower]

        if main_key is None:
            return

        def _dispatch():
            with self._lock:
                # Key Down
                event_down = Quartz.CGEventCreateKeyboardEvent(None, main_key, True)
                if flags:
                    Quartz.CGEventSetFlags(event_down, flags)
                Quartz.CGEventPost(Quartz.kCGAnnotatedSessionEventTap, event_down)

                time.sleep(0.02)  # 20ms hold

                # Key Up
                event_up = Quartz.CGEventCreateKeyboardEvent(None, main_key, False)
                if flags:
                    Quartz.CGEventSetFlags(event_up, flags)
                Quartz.CGEventPost(Quartz.kCGAnnotatedSessionEventTap, event_up)

        threading.Thread(target=_dispatch, daemon=True).start()

    def next_tab(self):
        """Switch to next tab (Chrome/Safari/VSCode)."""
        self.send_hotkey(["cmd", "alt", "right"])

    def prev_tab(self):
        """Switch to previous tab."""
        self.send_hotkey(["cmd", "alt", "left"])

    def minimize_window(self):
        """Minimize active window."""
        self.send_hotkey(["cmd", "m"])

    def fullscreen_toggle(self):
        """Toggle macOS fullscreen."""
        self.send_hotkey(["cmd", "ctrl", "f"])

    def close_tab(self):
        """Close current tab."""
        self.send_hotkey(["cmd", "w"])

    def switch_desktop_right(self):
        """Switch to space/desktop on right."""
        self.send_hotkey(["ctrl", "right"])

    def switch_desktop_left(self):
        """Switch to space/desktop on left."""
        self.send_hotkey(["ctrl", "left"])

    def mission_control(self):
        """Open Mission Control."""
        self.send_hotkey(["ctrl", "up"])

    def app_expose(self):
        """Open App Exposé."""
        self.send_hotkey(["ctrl", "down"])

    def show_desktop(self):
        """Show Desktop."""
        self.send_hotkey(["cmd", "f3"])

    def switch_app(self):
        """Switch application (Cmd + Tab)."""
        self.send_hotkey(["cmd", "tab"])

    def play_pause_media(self):
        """Universal Play / Pause via AppleScript (Spotify, Apple Music, System)."""
        def _exec():
            script = """
            if application "Spotify" is running then
                tell application "Spotify" to playpause
            else if application "Music" is running then
                tell application "Music" to playpause
            else
                tell application "System Events" to key code 49 using {command down, option down}
            end if
            """
            subprocess.run(["osascript", "-e", script], capture_output=True)

        threading.Thread(target=_exec, daemon=True).start()

    def set_volume_delta(self, delta_percent: int):
        """Increase or decrease system volume by delta percent."""
        def _exec():
            script = f"""
            set curVol to output volume of (get volume settings)
            set newVol to curVol + ({delta_percent})
            if newVol > 100 then set newVol to 100
            if newVol < 0 then set newVol to 0
            set volume output volume newVol
            """
            subprocess.run(["osascript", "-e", script], capture_output=True)

        threading.Thread(target=_exec, daemon=True).start()

    def set_volume_absolute(self, volume_percent: int):
        """Set absolute volume (0 - 100)."""
        volume_percent = max(0, min(100, int(volume_percent)))
        def _exec():
            script = f"set volume output volume {volume_percent}"
            subprocess.run(["osascript", "-e", script], capture_output=True)

        threading.Thread(target=_exec, daemon=True).start()

    def move_mouse(self, screen_x: float, screen_y: float):
        """Move the mouse cursor smoothly to absolute screen coordinates."""
        point = Quartz.CGPoint(x=screen_x, y=screen_y)
        Quartz.CGWarpMousePosition(point)

    def mouse_click(self, button: str = "left"):
        """Perform a mouse click at current cursor position."""
        def _exec():
            pos = Quartz.CGEventGetLocation(Quartz.CGEventCreate(None))
            down_type = Quartz.kCGEventLeftMouseDown if button == "left" else Quartz.kCGEventRightMouseDown
            up_type = Quartz.kCGEventLeftMouseUp if button == "left" else Quartz.kCGEventRightMouseUp
            btn = Quartz.kCGMouseButtonLeft if button == "left" else Quartz.kCGMouseButtonRight

            event_down = Quartz.CGEventCreateMouseEvent(None, down_type, pos, btn)
            event_up = Quartz.CGEventCreateMouseEvent(None, up_type, pos, btn)

            Quartz.CGEventPost(Quartz.kCGAnnotatedSessionEventTap, event_down)
            time.sleep(0.015)
            Quartz.CGEventPost(Quartz.kCGAnnotatedSessionEventTap, event_up)

        threading.Thread(target=_exec, daemon=True).start()

    def mouse_scroll(self, scroll_y: int):
        """Scroll vertically."""
        event = Quartz.CGEventCreateScrollWheelEvent2(
            None,
            Quartz.kCGScrollEventUnitPixel,
            1,
            int(scroll_y),
            0,
            0
        )
        Quartz.CGEventPost(Quartz.kCGAnnotatedSessionEventTap, event)
