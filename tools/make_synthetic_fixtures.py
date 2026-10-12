#!/usr/bin/env python3
"""
tools/make_synthetic_fixtures.py - Generates deterministic synthetic landmark fixtures for replay testing.
"""

import json
import os

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

if __name__ == "__main__":
    os.makedirs("tools/fixtures", exist_ok=True)
    generate_swipe_left_fixture("tools/fixtures/synthetic_swipe_left.jsonl")
    generate_pinch_fixture("tools/fixtures/synthetic_pinch.jsonl")
