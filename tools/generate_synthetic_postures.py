#!/usr/bin/env python3
"""
tools/generate_synthetic_postures.py - Parametric synthetic multi-subject posture dataset generator.

Generates >= 6 realistic synthetic recording sessions across 5 canonical posture classes:
- open_palm
- pinch
- two_fingers
- fist
- none (relaxed rest, chin scratch, semi-curled ambient)

Each session simulates distinct subjects, hand anthropometry (scale 0.85 - 1.15),
rotation attitudes (-25° to +25°), bone aspect ratios, mirror conditions (left vs right),
and sensor jitter noise.
"""

import os
import math
import json
import random
from typing import List, Tuple, Dict, Any

import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from tools.make_synthetic_fixtures import (
    make_open_palm_landmarks,
    make_pinch_landmarks,
    make_two_finger_landmarks,
    make_fist_landmarks,
    pts_to_records,
)


def rotate_and_mirror(
    pts: List[Tuple[float, float]],
    cx: float,
    cy: float,
    angle_rad: float,
    mirror: bool = False,
) -> List[Tuple[float, float]]:
    cos_a = math.cos(angle_rad)
    sin_a = math.sin(angle_rad)
    out = []
    for x, y in pts:
        dx = x - cx
        dy = y - cy
        if mirror:
            dx = -dx
        rx = dx * cos_a - dy * sin_a
        ry = dx * sin_a + dy * cos_a
        out.append((cx + rx, cy + ry))
    return out


def add_joint_noise(
    pts: List[Tuple[float, float]],
    noise_sigma: float,
    rng: random.Random,
) -> List[Tuple[float, float]]:
    if noise_sigma <= 0:
        return pts
    return [
        (round(x + rng.gauss(0, noise_sigma), 5), round(y + rng.gauss(0, noise_sigma), 5))
        for x, y in pts
    ]


def make_none_landmarks(cx: float, cy: float, scale: float = 1.0, variant: int = 0) -> List[Tuple[float, float]]:
    """
    Synthesizes non-communicative ambient postures (relaxed rest, limp fingers, chin/scratch).
    """
    pts = make_open_palm_landmarks(cx, cy, scale)
    if variant == 0:
        # Relaxed limp hand: fingers partially curled in staggered positions
        pts[7] = (cx - 0.04 * scale, cy - 0.03 * scale)
        pts[8] = (cx - 0.04 * scale, cy + 0.01 * scale)  # index tip limp
        pts[11] = (cx, cy - 0.02 * scale)
        pts[12] = (cx, cy + 0.02 * scale)                 # middle tip limp
        pts[15] = (cx + 0.04 * scale, cy - 0.01 * scale)
        pts[16] = (cx + 0.04 * scale, cy + 0.03 * scale)  # ring limp
        pts[19] = (cx + 0.07 * scale, cy)
        pts[20] = (cx + 0.07 * scale, cy + 0.03 * scale)  # pinky limp
        pts[4] = (cx - 0.06 * scale, cy + 0.02 * scale)   # thumb resting
    elif variant == 1:
        # Single finger curl (scratch / point variant, not 2 fingers, not open)
        pts[6] = (cx - 0.04 * scale, cy - 0.02 * scale)
        pts[7] = (cx - 0.04 * scale, cy - 0.01 * scale)
        pts[8] = (cx - 0.04 * scale, cy + 0.01 * scale)
        pts[15] = (cx + 0.04 * scale, cy - 0.01 * scale)
        pts[16] = (cx + 0.04 * scale, cy + 0.03 * scale)
        pts[19] = (cx + 0.07 * scale, cy)
        pts[20] = (cx + 0.07 * scale, cy + 0.03 * scale)
    else:
        # Loose natural curl (ambient hand on lap / table)
        pts[8] = (cx - 0.03 * scale, cy - 0.04 * scale)
        pts[12] = (cx, cy - 0.05 * scale)
        pts[16] = (cx + 0.03 * scale, cy - 0.03 * scale)
        pts[20] = (cx + 0.06 * scale, cy - 0.01 * scale)
        pts[4] = (cx - 0.07 * scale, cy)
    return pts


def generate_session_frames(
    session_id: str,
    subject_scale: float,
    tilt_range: Tuple[float, float],
    noise_sigma: float,
    mirror: bool,
    samples_per_class: int = 50,
    seed: int = 100,
) -> List[Dict[str, Any]]:
    rng = random.Random(seed)
    records: List[Dict[str, Any]] = []
    t = 1.0
    dt = 0.016
    frame_idx = 0

    classes = ["open_palm", "pinch", "two_fingers", "fist", "none"]

    for posture_cls in classes:
        # Subtle drift in center position for realism
        base_cx = rng.uniform(0.42, 0.58)
        base_cy = rng.uniform(0.45, 0.55)

        # 2 frames of hand absence to cleanly reset filter channel state between distinct gesture blocks
        for _ in range(2):
            records.append({
                "timestamp": round(t, 4),
                "frameIndex": frame_idx,
                "groundTruth": "none",
                "predictedIntent": "none",
                "firedIntent": "",
                "firedAction": "",
                "handDetected": False,
                "fingerCount": 0,
                "isPinching": False,
                "isTwoFingers": False,
                "isRaisedHand": False,
                "estimatedDepth": 0.0,
                "facingCamera": 0.0,
                "primaryPoints": [],
                "confidence": [0.0] * 21,
            })
            t += dt
            frame_idx += 1

        for s in range(samples_per_class):
            # Dynamic perturbations per frame
            f_scale = subject_scale * rng.uniform(0.97, 1.03)
            f_angle = math.radians(rng.uniform(tilt_range[0], tilt_range[1]))
            cur_cx = base_cx + rng.uniform(-0.015, 0.015)
            cur_cy = base_cy + rng.uniform(-0.015, 0.015)

            if posture_cls == "open_palm":
                pts = make_open_palm_landmarks(cur_cx, cur_cy, f_scale)
                ground_truth = "open_palm"
                is_pinching = False
                is_two_fingers = False
                finger_count = 4
            elif posture_cls == "pinch":
                pts = make_pinch_landmarks(cur_cx, cur_cy, f_scale)
                ground_truth = "pinch"
                is_pinching = True
                is_two_fingers = False
                finger_count = 3
            elif posture_cls == "two_fingers":
                pts = make_two_finger_landmarks(cur_cx, cur_cy, f_scale)
                # Tucked thumb against palm (ergonomic two-finger scroll posture)
                pts[2] = (cur_cx - 0.05 * f_scale, cur_cy + 0.03 * f_scale)
                pts[3] = (cur_cx - 0.04 * f_scale, cur_cy + 0.01 * f_scale)
                pts[4] = (cur_cx - 0.02 * f_scale, cur_cy + 0.02 * f_scale)
                ground_truth = "two_fingers"
                is_pinching = False
                is_two_fingers = True
                finger_count = 2
            elif posture_cls == "fist":
                pts = make_fist_landmarks(cur_cx, cur_cy, f_scale)
                ground_truth = "fist"
                is_pinching = False
                is_two_fingers = False
                finger_count = 0
            else:  # none
                v = s % 3
                pts = make_none_landmarks(cur_cx, cur_cy, f_scale, variant=v)
                ground_truth = "idle"
                is_pinching = False
                is_two_fingers = False
                finger_count = 1

            pts = rotate_and_mirror(pts, cur_cx, cur_cy, f_angle, mirror=mirror)
            pts = add_joint_noise(pts, noise_sigma, rng)

            rec = {
                "timestamp": round(t, 4),
                "frameIndex": frame_idx,
                "groundTruth": ground_truth,
                "predictedIntent": ground_truth if ground_truth != "idle" else "none",
                "firedIntent": "",
                "firedAction": "",
                "handDetected": True,
                "fingerCount": finger_count,
                "isPinching": is_pinching,
                "isTwoFingers": is_two_fingers,
                "isRaisedHand": True,
                "estimatedDepth": 0.40,
                "facingCamera": 0.90,
                "primaryPoints": pts_to_records(pts),
                "confidence": [1.0] * 21,
            }
            records.append(rec)
            t += dt
            frame_idx += 1

    return records


def generate_all_synthetic_sessions(
    output_dir: str = "tools/data/synthetic_sessions",
    samples_per_class: int = 50,
) -> List[str]:
    os.makedirs(output_dir, exist_ok=True)

    session_configs = [
        # (filename, subject_scale, tilt_range_deg, noise_sigma, mirror, seed)
        ("session_01_subject1_norm.jsonl", 1.00, (-10.0, 10.0), 0.002, False, 101),
        ("session_02_subject2_small.jsonl", 0.85, (-15.0, 15.0), 0.003, False, 202),
        ("session_03_subject3_large.jsonl", 1.15, (-12.0, 12.0), 0.002, False, 303),
        ("session_04_subject4_tilt.jsonl", 0.95, (-25.0, 25.0), 0.004, False, 404),
        ("session_05_subject5_left_mirror.jsonl", 1.05, (-15.0, 15.0), 0.003, True, 505),
        ("session_06_subject6_jitter.jsonl", 0.92, (-20.0, 20.0), 0.006, False, 606),
    ]

    generated_files = []
    for fname, scale, tilt, noise, mirror, seed in session_configs:
        fpath = os.path.join(output_dir, fname)
        frames = generate_session_frames(
            session_id=fname,
            subject_scale=scale,
            tilt_range=tilt,
            noise_sigma=noise,
            mirror=mirror,
            samples_per_class=samples_per_class,
            seed=seed,
        )
        with open(fpath, "w", encoding="utf-8") as f:
            for fr in frames:
                f.write(json.dumps(fr) + "\n")
        generated_files.append(fpath)
        print(f"[Synthetic] Generated {len(frames)} frames -> {fpath}")

    return generated_files


if __name__ == "__main__":
    generate_all_synthetic_sessions()
