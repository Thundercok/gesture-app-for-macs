#!/usr/bin/env python3
"""
tools/generate_intent_sequences.py - Parametric synthetic multi-subject intent sequence generator.

Generates temporal sequences (6 sessions, multi-subject) for Causal Intent Classification:
Classes:
  0: idle       - Ambient hand, resting, scratching, non-pointing drift (v < 0.04)
  1: hover      - Active pointing travel with open hand across space (v in [0.15, 0.50], open aperture)
  2: pre_click  - Rapid aperture contraction (0.75 -> 0.22 in 3-5 frames) as fingers clamp prior to click
  3: drag       - Sustained pointer translation while pinched (aperture < 0.20, v in [0.18, 0.45])
  4: scroll     - Two-finger posture with active vertical translation (v_y in [0.15, 0.45])

Produces:
  - tools/data/intent_sessions/session_*.jsonl
  - tools/data/intent_features.csv (sliding window K=10 frames x 56D features = 560D input)
  - tools/data/intent_split.json (strict session-level train/test manifest)
"""

import os
import sys
import math
import json
import csv
import random
from typing import List, Tuple, Dict, Any

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from tools.make_synthetic_fixtures import (
    make_open_palm_landmarks,
    make_pinch_landmarks,
    make_two_finger_landmarks,
    pts_to_records,
)
from tools.generate_synthetic_postures import (
    rotate_and_mirror,
    add_joint_noise,
    make_none_landmarks,
)
from tools.export_features import normalize_landmarks

INTENT_CLASSES = ["idle", "hover", "pre_click", "drag", "scroll"]
INTENT_TO_IDX = {cls: idx for idx, cls in enumerate(INTENT_CLASSES)}
WINDOW_SIZE = 10  # 10 frames = 167 ms at 60 FPS


def interpolate_pts(
    p1: List[Tuple[float, float]],
    p2: List[Tuple[float, float]],
    alpha: float
) -> List[Tuple[float, float]]:
    return [
        (round(a[0] * (1.0 - alpha) + b[0] * alpha, 5), round(a[1] * (1.0 - alpha) + b[1] * alpha, 5))
        for a, b in zip(p1, p2)
    ]


def generate_intent_stream(
    subject_id: str,
    scale: float = 1.0,
    tilt_rad: float = 0.0,
    mirror: bool = False,
    noise_sigma: float = 0.001,
    seed: int = 42,
    segments_per_class: int = 4,
    frames_per_segment: int = 15
) -> List[Dict[str, Any]]:
    rng = random.Random(seed)
    frames = []
    t = 0.0
    dt = 0.016667

    # Center trajectory tracking
    cx, cy = 0.50, 0.50

    for seg_idx in range(segments_per_class):
        # Sequence of intents in natural interactive flow:
        # idle -> hover -> pre_click -> hover -> drag -> hover -> scroll -> idle
        intent_plan = ["idle", "hover", "pre_click", "hover", "drag", "scroll"]

        for intent in intent_plan:
            vx = rng.uniform(-0.25, 0.25)
            vy = rng.uniform(-0.25, 0.25)

            for f in range(frames_per_segment):
                t += dt

                if intent == "idle":
                    # Slow, aimless drift with none posture
                    cx += rng.gauss(0, 0.0008)
                    cy += rng.gauss(0, 0.0008)
                    base_pts = make_none_landmarks(cx, cy, scale, variant=seg_idx % 3)
                    is_two_fingers = False
                    is_pinching = False

                elif intent == "hover":
                    # Deliberate pointer flight with open palm
                    cx += vx * dt
                    cy += vy * dt
                    base_pts = make_open_palm_landmarks(cx, cy, scale)
                    is_two_fingers = False
                    is_pinching = False

                elif intent == "pre_click":
                    # Deceleration clamp from open palm to pinch
                    # First 5 frames: open palm hovering
                    # Next 10 frames: aperture closes from 100% to 10%
                    progress = min(1.0, max(0.0, (f - 3) / 8.0)) if f >= 3 else 0.0
                    open_pts = make_open_palm_landmarks(cx, cy, scale)
                    pinch_pts = make_pinch_landmarks(cx, cy, scale)
                    base_pts = interpolate_pts(open_pts, pinch_pts, progress)
                    # Slow down during click clamp
                    cx += (vx * 0.2) * dt
                    cy += (vy * 0.2) * dt
                    is_two_fingers = False
                    is_pinching = (progress >= 0.85)

                elif intent == "drag":
                    # Sustained travel with clamped pinch
                    cx += vx * 1.2 * dt
                    cy += vy * 1.2 * dt
                    base_pts = make_pinch_landmarks(cx, cy, scale)
                    is_two_fingers = False
                    is_pinching = True

                elif intent == "scroll":
                    # Vertical displacement with two fingers
                    cx += (vx * 0.2) * dt
                    cy += math.copysign(0.28, vy) * dt
                    base_pts = make_two_finger_landmarks(cx, cy, scale)
                    is_two_fingers = True
                    is_pinching = False

                # Keep center in bounds
                cx = max(0.20, min(0.80, cx))
                cy = max(0.20, min(0.80, cy))

                # Apply tilt and mirroring
                xf_pts = rotate_and_mirror(base_pts, cx, cy, tilt_rad, mirror=mirror)
                final_pts = add_joint_noise(xf_pts, noise_sigma, rng)

                rec = {
                    "timestamp": round(t, 4),
                    "frameIndex": len(frames),
                    "handDetected": True,
                    "isRaisedHand": True,
                    "facingCamera": 0.85,
                    "isTwoFingers": is_two_fingers,
                    "isPinching": is_pinching,
                    "intent": intent,
                    "subject": subject_id,
                    "primaryPoints": pts_to_records(final_pts),
                }
                frames.append(rec)

    return frames


def export_intent_dataset(output_dir: str = "tools/data"):
    sessions_dir = os.path.join(output_dir, "intent_sessions")
    os.makedirs(sessions_dir, exist_ok=True)

    configs = [
        {"id": "session_01_subject1_norm", "scale": 1.00, "tilt": 0.0, "mirror": False, "noise": 0.001, "seed": 101},
        {"id": "session_02_subject2_small", "scale": 0.88, "tilt": 0.15, "mirror": False, "noise": 0.001, "seed": 102},
        {"id": "session_03_subject3_large", "scale": 1.15, "tilt": -0.15, "mirror": False, "noise": 0.001, "seed": 103},
        {"id": "session_04_subject4_tilt", "scale": 1.05, "tilt": 0.35, "mirror": False, "noise": 0.0012, "seed": 104},
        {"id": "session_05_subject5_left", "scale": 0.95, "tilt": -0.10, "mirror": True, "noise": 0.001, "seed": 105},
        {"id": "session_06_subject6_jitter", "scale": 1.02, "tilt": 0.08, "mirror": False, "noise": 0.0025, "seed": 106},
    ]

    all_session_files = []
    print(f"[Dataset] Generating {len(configs)} multi-subject intent sessions...")

    for cfg in configs:
        frames = generate_intent_stream(
            subject_id=cfg["id"],
            scale=cfg["scale"],
            tilt_rad=cfg["tilt"],
            mirror=cfg["mirror"],
            noise_sigma=cfg["noise"],
            seed=cfg["seed"],
            segments_per_class=5,
            frames_per_segment=16
        )
        filepath = os.path.join(sessions_dir, f"{cfg['id']}.jsonl")
        with open(filepath, "w") as f:
            for fr in frames:
                f.write(json.dumps(fr) + "\n")
        all_session_files.append(filepath)
        print(f"  -> Generated {len(frames)} frames: {os.path.basename(filepath)}")

    # Strict Session-Level Train/Test Split
    train_sessions = [configs[0]["id"] + ".jsonl", configs[1]["id"] + ".jsonl", configs[2]["id"] + ".jsonl", configs[4]["id"] + ".jsonl", configs[5]["id"] + ".jsonl"]
    test_sessions = [configs[3]["id"] + ".jsonl"]  # Held-out tilted subject 4

    split_manifest = {
        "train": train_sessions,
        "test": test_sessions,
        "classes": INTENT_CLASSES,
        "window_size": WINDOW_SIZE
    }
    split_path = os.path.join(output_dir, "intent_split.json")
    with open(split_path, "w") as f:
        json.dump(split_manifest, f, indent=2)
    print(f"[Dataset] Saved split manifest to {split_path}")

    # Build sliding-window features CSV (10 frames x 56D = 560D features)
    features_csv = os.path.join(output_dir, "intent_features.csv")
    print(f"[Dataset] Extracting sliding-window 560D features into {features_csv}...")

    total_windows = 0
    with open(features_csv, "w", newline="") as csv_f:
        writer = csv.writer(csv_f)
        header = ["source_file", "split", "frame_index", "timestamp", "intent"] + [f"feat_{i}" for i in range(WINDOW_SIZE * 56)]
        writer.writerow(header)

        for session_file in all_session_files:
            filename = os.path.basename(session_file)
            split_tag = "test" if filename in test_sessions else "train"

            with open(session_file, "r") as sf:
                session_frames = [json.loads(line) for line in sf if line.strip()]

            # Extract 56D vector for every frame
            frame_features = []
            for fr in session_frames:
                pts = [(p["x"], p["y"]) for p in fr["primaryPoints"]]
                feats, _ = normalize_landmarks(pts)
                frame_features.append(feats)

            # Slide window of size K=10
            for i in range(WINDOW_SIZE - 1, len(session_frames)):
                window_feats = []
                for step in range(i - WINDOW_SIZE + 1, i + 1):
                    window_feats.extend(frame_features[step])

                target_frame = session_frames[i]
                target_intent = target_frame.get("intent", "idle")
                row = [filename, split_tag, i, round(target_frame.get("time", 0.0), 3), target_intent] + [round(x, 6) for x in window_feats]
                writer.writerow(row)
                total_windows += 1

    print(f"[Dataset] Export complete! Total sliding windows: {total_windows} (560 features each).")
    return features_csv, split_path


def main():
    export_intent_dataset()


if __name__ == "__main__":
    main()
