#!/usr/bin/env python3
"""
tools/make_synthetic_fixtures.py - Generates deterministic synthetic landmark fixtures for replay testing.
"""

import json
import os
import random

def make_two_finger_landmarks(cx, cy, scale=1.0):
    pts = make_open_palm_landmarks(cx, cy, scale)
    pts[14] = (cx + 0.04 * scale, cy - 0.02 * scale)
    pts[15] = (cx + 0.04 * scale, cy - 0.01 * scale)
    pts[16] = (cx + 0.04 * scale, cy + 0.01 * scale)
    pts[18] = (cx + 0.07 * scale, cy - 0.01 * scale)
    pts[19] = (cx + 0.07 * scale, cy + 0.01 * scale)
    pts[20] = (cx + 0.07 * scale, cy + 0.02 * scale)
    return pts

def make_fist_landmarks(cx, cy, scale=1.0):
    pts = make_open_palm_landmarks(cx, cy, scale)
    pts[6] = (cx - 0.04 * scale, cy - 0.02 * scale)
    pts[7] = (cx - 0.04 * scale, cy - 0.01 * scale)
    pts[8] = (cx - 0.04 * scale, cy + 0.01 * scale)
    pts[10] = (cx, cy - 0.02 * scale)
    pts[11] = (cx, cy - 0.01 * scale)
    pts[12] = (cx, cy + 0.01 * scale)
    pts[14] = (cx + 0.04 * scale, cy - 0.02 * scale)
    pts[15] = (cx + 0.04 * scale, cy - 0.01 * scale)
    pts[16] = (cx + 0.04 * scale, cy + 0.01 * scale)
    pts[18] = (cx + 0.07 * scale, cy - 0.01 * scale)
    pts[19] = (cx + 0.07 * scale, cy + 0.01 * scale)
    pts[20] = (cx + 0.07 * scale, cy + 0.02 * scale)
    return pts

def make_downward_landmarks(cx, cy, scale=1.0):
    wrist = (cx, cy - 0.10 * scale)
    thumb_cmc = (cx - 0.04 * scale, cy - 0.05 * scale)
    thumb_mp  = (cx - 0.07 * scale, cy - 0.02 * scale)
    thumb_ip  = (cx - 0.09 * scale, cy + 0.01 * scale)
    thumb_tip = (cx - 0.11 * scale, cy + 0.03 * scale)

    index_mcp = (cx - 0.04 * scale, cy)
    index_pip = (cx - 0.04 * scale, cy + 0.05 * scale)
    index_dip = (cx - 0.04 * scale, cy + 0.09 * scale)
    index_tip = (cx - 0.04 * scale, cy + 0.13 * scale)

    middle_mcp = (cx, cy)
    middle_pip = (cx, cy + 0.06 * scale)
    middle_dip = (cx, cy + 0.10 * scale)
    middle_tip = (cx, cy + 0.15 * scale)

    ring_mcp = (cx + 0.04 * scale, cy)
    ring_pip = (cx + 0.04 * scale, cy + 0.05 * scale)
    ring_dip = (cx + 0.04 * scale, cy + 0.09 * scale)
    ring_tip = (cx + 0.04 * scale, cy + 0.13 * scale)

    pinky_mcp = (cx + 0.07 * scale, cy - 0.02 * scale)
    pinky_pip = (cx + 0.07 * scale, cy + 0.03 * scale)
    pinky_dip = (cx + 0.07 * scale, cy + 0.06 * scale)
    pinky_tip = (cx + 0.07 * scale, cy + 0.09 * scale)

    return [
        wrist,
        thumb_cmc, thumb_mp, thumb_ip, thumb_tip,
        index_mcp, index_pip, index_dip, index_tip,
        middle_mcp, middle_pip, middle_dip, middle_tip,
        ring_mcp, ring_pip, ring_dip, ring_tip,
        pinky_mcp, pinky_pip, pinky_dip, pinky_tip
    ]

def make_open_palm_landmarks(cx, cy, scale=1.0):
    wrist = (cx, cy + 0.10 * scale)
    thumb_cmc = (cx - 0.04 * scale, cy + 0.05 * scale)
    thumb_mp  = (cx - 0.07 * scale, cy + 0.02 * scale)
    thumb_ip  = (cx - 0.09 * scale, cy - 0.01 * scale)
    thumb_tip = (cx - 0.11 * scale, cy - 0.03 * scale)

    index_mcp = (cx - 0.04 * scale, cy)
    index_pip = (cx - 0.04 * scale, cy - 0.05 * scale)
    index_dip = (cx - 0.04 * scale, cy - 0.09 * scale)
    index_tip = (cx - 0.04 * scale, cy - 0.13 * scale)

    middle_mcp = (cx, cy)
    middle_pip = (cx, cy - 0.06 * scale)
    middle_dip = (cx, cy - 0.10 * scale)
    middle_tip = (cx, cy - 0.15 * scale)

    ring_mcp = (cx + 0.04 * scale, cy)
    ring_pip = (cx + 0.04 * scale, cy - 0.05 * scale)
    ring_dip = (cx + 0.04 * scale, cy - 0.09 * scale)
    ring_tip = (cx + 0.04 * scale, cy - 0.13 * scale)

    pinky_mcp = (cx + 0.07 * scale, cy + 0.02 * scale)
    pinky_pip = (cx + 0.07 * scale, cy - 0.03 * scale)
    pinky_dip = (cx + 0.07 * scale, cy - 0.06 * scale)
    pinky_tip = (cx + 0.07 * scale, cy - 0.09 * scale)

    return [
        wrist,
        thumb_cmc, thumb_mp, thumb_ip, thumb_tip,
        index_mcp, index_pip, index_dip, index_tip,
        middle_mcp, middle_pip, middle_dip, middle_tip,
        ring_mcp, ring_pip, ring_dip, ring_tip,
        pinky_mcp, pinky_pip, pinky_dip, pinky_tip
    ]

def make_pinch_landmarks(cx, cy, scale=1.0):
    pts = make_open_palm_landmarks(cx, cy, scale)
    touch_pt = (cx - 0.03 * scale, cy - 0.04 * scale)
    pts[4] = touch_pt  # thumb tip
    pts[8] = touch_pt  # index tip
    pts[7] = (cx - 0.03 * scale, cy - 0.01 * scale) # index dip
    return pts

def pts_to_records(pts):
    return [{"x": round(p[0], 5), "y": round(p[1], 5)} for p in pts]

def generate_swipe_left_fixture(out_path):
    records = []
    t = 1.0
    dt = 0.016
    frame_idx = 0

    # Phase 1: 8 frames open palm stationary at cx=0.40, cy=0.50 (dwell established)
    for _ in range(8):
        pts = make_open_palm_landmarks(0.40, 0.50)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "swipe_left",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    # Phase 2: 6 frames moving rapidly to camera right (cx from 0.40 to 0.62)
    # Moving to camera right means rawTrackingPoint.x (1.0 - indexTip.x) moves from 0.64 to 0.42 (dx = -0.22, physical swipe left)
    xs = [0.40, 0.44, 0.48, 0.53, 0.58, 0.62]
    for x in xs:
        pts = make_open_palm_landmarks(x, 0.50)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "swipe_left",
            "predictedIntent": "swipe",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    # Phase 3: 10 frames resting at end
    for _ in range(10):
        pts = make_open_palm_landmarks(0.62, 0.50)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

def generate_pinch_fixture(out_path):
    records = []
    t = 1.0
    dt = 0.016
    frame_idx = 0

    # Phase 1: 5 frames open palm stationary at (0.50, 0.50)
    for _ in range(5):
        pts = make_open_palm_landmarks(0.50, 0.50)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    # Phase 2: 12 frames pinched stationary (arms and engages dock)
    for _ in range(12):
        pts = make_pinch_landmarks(0.50, 0.50)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "pinch_dock",
            "predictedIntent": "pinch_dock",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 2,
            "isPinching": True,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    # Phase 3: 6 frames release pinch (opens fingers again, commits dock switch)
    for _ in range(6):
        pts = make_open_palm_landmarks(0.50, 0.50)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "pinch_dock",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

def generate_swipe_right_fixture(out_path):
    records = []
    t = 1.0
    dt = 0.016
    frame_idx = 0

    # Phase 1: 8 frames open palm stationary at cx=0.62, cy=0.50 (dwell established)
    for _ in range(8):
        pts = make_open_palm_landmarks(0.62, 0.50)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "swipe_right",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    # Phase 2: 6 frames moving rapidly to camera left (cx from 0.62 to 0.40)
    # Moving to camera left means rawTrackingPoint.x (1.0 - indexTip.x) moves from 0.42 to 0.64 (dx = +0.22, physical swipe right)
    xs = [0.62, 0.58, 0.53, 0.48, 0.44, 0.40]
    for x in xs:
        pts = make_open_palm_landmarks(x, 0.50)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "swipe_right",
            "predictedIntent": "swipe",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    # Phase 3: 10 frames resting at end
    for _ in range(10):
        pts = make_open_palm_landmarks(0.40, 0.50)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

def generate_swipe_up_fixture(out_path):
    records = []
    t = 1.0
    dt = 0.016
    frame_idx = 0

    # Phase 1: 8 frames open palm stationary at cx=0.50, cy=0.40
    for _ in range(8):
        pts = make_open_palm_landmarks(0.50, 0.40)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "swipe_up",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    # Phase 2: 6 frames moving rapidly vertically (cy from 0.40 to 0.65 -> dy > 0 -> swipe_up)
    ys = [0.40, 0.45, 0.50, 0.55, 0.60, 0.65]
    for y in ys:
        pts = make_open_palm_landmarks(0.50, y)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "swipe_up",
            "predictedIntent": "swipe",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    # Phase 3: 10 frames resting at end
    for _ in range(10):
        pts = make_open_palm_landmarks(0.50, 0.65)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

def generate_swipe_down_fixture(out_path):
    records = []
    t = 1.0
    dt = 0.016
    frame_idx = 0

    # Phase 1: 8 frames open palm stationary at cx=0.50, cy=0.65
    for _ in range(8):
        pts = make_open_palm_landmarks(0.50, 0.65)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "swipe_down",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    # Phase 2: 6 frames moving rapidly vertically (cy from 0.65 to 0.40 -> dy < 0 -> swipe_down)
    ys = [0.65, 0.60, 0.55, 0.50, 0.45, 0.40]
    for y in ys:
        pts = make_open_palm_landmarks(0.50, y)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "swipe_down",
            "predictedIntent": "swipe",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    # Phase 3: 10 frames resting at end
    for _ in range(10):
        pts = make_open_palm_landmarks(0.50, 0.40)
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt
        frame_idx += 1

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

def generate_idle_jitter_fixture(out_path):
    rng = random.Random(42)
    records = []
    t = 1.0
    dt = 0.016
    for i in range(600):
        pts = make_open_palm_landmarks(0.50, 0.50)
        jittered = [(p[0] + rng.gauss(0, 0.003), p[1] + rng.gauss(0, 0.003)) for p in pts]
        rec = {
            "timestamp": round(t, 4),
            "frameIndex": i,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(jittered),
            "confidence": [1.0] * 21
        }
        records.append(rec)
        t += dt

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

def generate_slow_swipe_fixture(out_path):
    records = []
    t = 1.0
    dt = 0.016
    frame_idx = 0

    # Phase 1: 8 frames open palm stationary at cx=0.40, cy=0.50
    for _ in range(8):
        pts = make_open_palm_landmarks(0.40, 0.50)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 2: Slow movement over 60 frames (1 second, velocity ~0.20 units/s)
    for step in range(60):
        x = 0.40 + (0.20 * (step / 60.0))
        pts = make_open_palm_landmarks(x, 0.50)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 3: 10 frames resting
    for _ in range(10):
        pts = make_open_palm_landmarks(0.60, 0.50)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

def generate_diagonal_fixture(out_path):
    records = []
    t = 1.0
    dt = 0.016
    frame_idx = 0

    # Phase 1: 8 frames open palm stationary at cx=0.60, cy=0.40
    for _ in range(8):
        pts = make_open_palm_landmarks(0.60, 0.40)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 2: 6 frames fast diagonal: |dx| == |dy| (+0.20 in raw x and +0.20 in y)
    for step in range(6):
        frac = (step + 1) / 6.0
        x = 0.60 - 0.20 * frac
        y = 0.40 + 0.20 * frac
        pts = make_open_palm_landmarks(x, y)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "swipe",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 3: 10 frames resting at (0.40, 0.60)
    for _ in range(10):
        pts = make_open_palm_landmarks(0.40, 0.60)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

def generate_pinch_then_swipe_fixture(out_path):
    records = []
    t = 1.0
    dt = 0.016
    frame_idx = 0

    # Phase 1: 5 frames moving hand (inst speed ~ 1.25 units/s) so handSpeed > 0.30
    xs_move = [0.30, 0.32, 0.34, 0.36, 0.38]
    for x in xs_move:
        pts = make_open_palm_landmarks(x, 0.50)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 2: 3 frames brief pinch while in transit (handSpeed > 0.30 suppresses dock, lastPinchTime recorded)
    for x in [0.40, 0.42, 0.44]:
        pts = make_pinch_landmarks(x, 0.50)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 2,
            "isPinching": True,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 3: immediately 6 frames rapid swipe to camera right (cx from 0.44 to 0.65) within 0.10s
    xs_swipe = [0.44, 0.48, 0.53, 0.58, 0.62, 0.65]
    for x in xs_swipe:
        pts = make_open_palm_landmarks(x, 0.50)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "swipe",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 4: 10 frames resting
    for _ in range(10):
        pts = make_open_palm_landmarks(0.65, 0.50)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

def generate_hand_lost_mid_swipe_fixture(out_path):
    records = []
    t = 1.0
    dt = 0.016
    frame_idx = 0

    # Phase 1: 8 frames stationary dwell at cx=0.40, cy=0.50
    for _ in range(8):
        pts = make_open_palm_landmarks(0.40, 0.50)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 2: 2 frames moving fast towards swipe: x moves 0.40 -> 0.42 -> 0.44 (displacement 0.04 < 0.065)
    for x in [0.42, 0.44]:
        pts = make_open_palm_landmarks(x, 0.50)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "swipe",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 3: 5 frames hand lost
    for _ in range(5):
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
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
            "confidence": []
        })
        t += dt
        frame_idx += 1

    # Phase 4: 10 frames hand reappears and stays resting at 0.44
    for _ in range(10):
        pts = make_open_palm_landmarks(0.44, 0.50)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

def generate_face_proximity_fixture(out_path):
    records = []
    t = 1.0
    dt = 0.016
    frame_idx = 0
    face_box = {"x": 0.20, "y": 0.20, "width": 0.60, "height": 0.60}

    # Phase 1: 8 frames downward chin-touch hand stationary at cx=0.40, cy=0.40
    for _ in range(8):
        pts = make_downward_landmarks(0.40, 0.40)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21,
            "faceBBox": face_box
        })
        t += dt
        frame_idx += 1

    # Phase 2: 6 frames fast motion
    for x in [0.40, 0.44, 0.48, 0.53, 0.58, 0.62]:
        pts = make_downward_landmarks(x, 0.40)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "swipe",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21,
            "faceBBox": face_box
        })
        t += dt
        frame_idx += 1

    # Phase 3: 10 frames resting at cx=0.62
    for _ in range(10):
        pts = make_downward_landmarks(0.62, 0.40)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 4,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21,
            "faceBBox": face_box
        })
        t += dt
        frame_idx += 1

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

def generate_scroll_down_fixture(out_path):
    records = []
    t = 1.0
    dt = 0.016
    frame_idx = 0

    # Phase 1: 8 frames neutral fist stationary dwell at (0.50, 0.40)
    for _ in range(8):
        pts = make_fist_landmarks(0.50, 0.40)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "scroll_down",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 0,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 2: two fingers flick downwards in camera: cy from 0.40 to 0.62 (dy > 0 -> strokeDirection = .up -> scroll_down)
    ys = [0.40, 0.45, 0.52, 0.60, 0.62, 0.62]
    for y in ys:
        pts = make_two_finger_landmarks(0.50, y)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "scroll_down",
            "predictedIntent": "scroll",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 2,
            "isPinching": False,
            "isTwoFingers": True,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 3: 10 frames resting at 0.62
    for _ in range(10):
        pts = make_two_finger_landmarks(0.50, 0.62)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 2,
            "isPinching": False,
            "isTwoFingers": True,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

def generate_scroll_up_fixture(out_path):
    records = []
    t = 1.0
    dt = 0.016
    frame_idx = 0

    # Phase 1: 8 frames neutral fist stationary dwell at (0.50, 0.62)
    for _ in range(8):
        pts = make_fist_landmarks(0.50, 0.62)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "scroll_up",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 0,
            "isPinching": False,
            "isTwoFingers": False,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 2: two fingers flick upwards in camera: cy from 0.62 to 0.40 (dy < 0 -> strokeDirection = .down -> scroll_up)
    ys = [0.62, 0.57, 0.50, 0.42, 0.40, 0.40]
    for y in ys:
        pts = make_two_finger_landmarks(0.50, y)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "scroll_up",
            "predictedIntent": "scroll",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 2,
            "isPinching": False,
            "isTwoFingers": True,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    # Phase 3: 10 frames resting at 0.40
    for _ in range(10):
        pts = make_two_finger_landmarks(0.50, 0.40)
        records.append({
            "timestamp": round(t, 4),
            "frameIndex": frame_idx,
            "groundTruth": "idle",
            "predictedIntent": "idle",
            "firedIntent": "",
            "firedAction": "",
            "handDetected": True,
            "fingerCount": 2,
            "isPinching": False,
            "isTwoFingers": True,
            "isRaisedHand": True,
            "estimatedDepth": 0.45,
            "facingCamera": 0.95,
            "primaryPoints": pts_to_records(pts),
            "confidence": [1.0] * 21
        })
        t += dt
        frame_idx += 1

    with open(out_path, "w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    print(f"Generated {len(records)} frames to {out_path}")

if __name__ == "__main__":
    os.makedirs("tools/fixtures", exist_ok=True)
    generate_swipe_left_fixture("tools/fixtures/synthetic_swipe_left.jsonl")
    generate_pinch_fixture("tools/fixtures/synthetic_pinch.jsonl")
    generate_swipe_right_fixture("tools/fixtures/synthetic_swipe_right.jsonl")
    generate_swipe_up_fixture("tools/fixtures/synthetic_swipe_up.jsonl")
    generate_swipe_down_fixture("tools/fixtures/synthetic_swipe_down.jsonl")
    generate_idle_jitter_fixture("tools/fixtures/synthetic_idle_jitter.jsonl")
    generate_slow_swipe_fixture("tools/fixtures/synthetic_slow_swipe.jsonl")
    generate_diagonal_fixture("tools/fixtures/synthetic_diagonal.jsonl")
    generate_pinch_then_swipe_fixture("tools/fixtures/synthetic_pinch_then_swipe.jsonl")
    generate_hand_lost_mid_swipe_fixture("tools/fixtures/synthetic_hand_lost_mid_swipe.jsonl")
    generate_face_proximity_fixture("tools/fixtures/synthetic_face_proximity.jsonl")
    generate_scroll_down_fixture("tools/fixtures/synthetic_scroll_down.jsonl")
    generate_scroll_up_fixture("tools/fixtures/synthetic_scroll_up.jsonl")

