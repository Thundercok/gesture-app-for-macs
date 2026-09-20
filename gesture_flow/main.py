"""
GestureFlow - Main Application Controller
Run with or without HUD window, managing camera loop, adaptive FPS, and gesture dispatching.
"""

import os
import sys
import time
import argparse
import yaml
import signal
from pathlib import Path

# Add project root to sys.path
PROJECT_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(PROJECT_ROOT.parent))

from gesture_flow.core import (
    ActionDispatcher,
    HandTracker,
    GestureEngine,
    CameraStream,
)
from gesture_flow.ui import GestureHUD


def load_config(config_path: str) -> dict:
    if not os.path.exists(config_path):
        print(f"[Warning] Config file not found at {config_path}, using defaults.")
        return {}
    with open(config_path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def main():
    parser = argparse.ArgumentParser(description="GestureFlow - macOS System-Wide Hand Gesture Controller")
    parser.add_argument("--config", type=str, default=str(PROJECT_ROOT / "config" / "config.yaml"), help="Path to config.yaml")
    parser.add_argument("--headless", action="store_true", help="Run in headless background mode (no HUD window)")
    parser.add_argument("--fps", type=int, default=None, help="Override target active FPS")
    args = parser.parse_args()

    config = load_config(args.config)

    # CLI overrides
    if args.fps:
        config.setdefault("camera", {})["fps"] = args.fps

    print("=" * 65)
    print("🚀 GestureFlow macOS - Hand Gesture Shortcut Controller")
    print("=" * 65)
    print("📌 Available Gestures:")
    print("  • ✌️ 2-Finger Swipe Right  -> Next Tab (Cmd + Option + →)")
    print("  • ✌️ 2-Finger Swipe Left   -> Previous Tab (Cmd + Option + ←)")
    print("  • ✌️ 2-Finger Swipe Down   -> Minimize Window (Cmd + M)")
    print("  • ✌️ 2-Finger Swipe Up     -> Fullscreen (Cmd + Ctrl + F)")
    print("  • 🖐 4-Finger Swipe Left/Right -> Switch Desktop (Ctrl + ← / →)")
    print("  • 🖐 4-Finger Swipe Up    -> Mission Control (Ctrl + ↑)")
    print("  • 🖐 Hold Open Palm (0.5s)-> Play / Pause Media")
    print("  • ✊ Hold Fist (0.5s)     -> Show Desktop (Cmd + F3)")
    print("  • ☝️ 1 Finger Pointing     -> Virtual Mouse Movement")
    print("  • 👌 Pinch                 -> Left Mouse Click")
    print("=" * 65)

    cam_cfg = config.get("camera", {})
    engine_cfg = config.get("engine", {})
    power_cfg = config.get("power_saver", {})

    dispatcher = ActionDispatcher()
    tracker = HandTracker(
        min_detection_confidence=engine_cfg.get("min_detection_confidence", 0.6),
        min_tracking_confidence=engine_cfg.get("min_tracking_confidence", 0.6),
        model_complexity=engine_cfg.get("model_complexity", 0)
    )
    engine = GestureEngine(config, dispatcher)

    cam = CameraStream(
        device_index=cam_cfg.get("device_index", 0),
        width=cam_cfg.get("width", 640),
        height=cam_cfg.get("height", 480),
        mirror=cam_cfg.get("mirror", True)
    )

    if not cam.start():
        print("[Error] Failed to initialize camera. Please check camera permissions.")
        sys.exit(1)

    hud = None if args.headless else GestureHUD()
    show_hud = not args.headless

    running = True

    def _sigint_handler(sig, frame):
        nonlocal running
        print("\n[GestureFlow] Stopping gracefully...")
        running = False

    signal.signal(signal.SIGINT, _sigint_handler)

    print("✨ Camera stream started. Bring your hand into view to begin!")
    if show_hud:
        print("💡 Press 'q' on the preview window to exit, or 'h' to hide HUD.")

    last_hand_time = time.time()
    frame_count = 0
    fps_start_time = time.time()
    current_fps = 30.0

    idle_timeout = power_cfg.get("idle_timeout_sec", 2.0)
    adaptive_fps = power_cfg.get("adaptive_fps", True)

    try:
        while running:
            ret, frame = cam.read(timeout=0.05)
            if not ret or frame is None:
                time.sleep(0.01)
                continue

            frame_count += 1
            if frame_count >= 20:
                now_t = time.time()
                current_fps = frame_count / max(1e-4, (now_t - fps_start_time))
                frame_count = 0
                fps_start_time = now_t

            # Process hand landmarks
            pose = tracker.process(frame)

            now = time.time()
            if pose is not None:
                last_hand_time = now
                event = engine.process(pose)
                if event:
                    print(f"⚡ [Triggered] {event.label} ({event.name})")
                    if hud is not None:
                        hud.update_event(event)
            else:
                engine.process(None)

            # Adaptive FPS Power Saver
            is_idle = (now - last_hand_time) > idle_timeout
            if adaptive_fps and is_idle and args.headless:
                time.sleep(0.15)  # Drop to ~6 FPS during prolonged idle in headless mode

            # Render HUD
            if show_hud and hud is not None:
                if pose is not None:
                    tracker.draw_landmarks(frame, pose.pixel_landmarks)

                hud_frame = hud.render(frame, pose, current_fps)
                key = hud.show(hud_frame)

                if key == ord("q") or key == 27:  # 'q' or Esc
                    break
                elif key == ord("h"):  # 'h' toggles HUD visibility
                    print("[GestureFlow] Hiding HUD window. Run in background mode.")
                    hud.close()
                    show_hud = False

    finally:
        cam.stop()
        if hud is not None:
            hud.close()
        print("[GestureFlow] Shutdown complete.")


if __name__ == "__main__":
    main()
