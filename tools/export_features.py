#!/usr/bin/env python3
"""
tools/export_features.py - Feature extraction and normalization for Hand Pose / Posture Classifier.

Performs:
1. Per-frame wrist-translation: translate wrist (landmark 0) to origin.
2. Scale normalization: scale by distance from wrist to middle MCP (landmark 9).
3. Rotation normalization: rotate so vector wrist -> middle MCP points vertically up (+Y).
4. Mirroring normalization: reflect left hand across Y axis so pinky is on +X, matching right hand.
5. Engineered features: finger curl angles, tip-to-wrist distances, inter-finger distances.
6. Session-level train/test splitting (never by frame) with split.json manifest.
7. Explicit ground-truth label to posture mapping.
"""

import os
import sys
import json
import csv
import math
import random
import argparse
from typing import List, Tuple, Dict, Any, Optional

LABEL_TO_POSTURE: Dict[str, str] = {
    # Idle / resting / neutral
    "idle": "none",
    "none": "none",
    "scratch_head": "none",
    "rest_cheek": "none",
    "scratch_chin": "none",
    "air_push": "none",
    "unknown": "none",

    # Open palm postures
    "open_palm": "open_palm",
    "swipe_left": "open_palm",
    "swipe_right": "open_palm",
    "swipe_up": "open_palm",
    "swipe_down": "open_palm",
    "palm_dwell": "open_palm",

    # Pinch postures
    "pinch": "pinch",
    "pinch_dock": "pinch",
    "pinch_drag": "pinch",
    "pinch_commit": "pinch",

    # Two fingers postures
    "two_fingers": "two_fingers",
    "scroll_up": "two_fingers",
    "scroll_down": "two_fingers",
    "air_scroll": "two_fingers",

    # Fist postures
    "fist": "fist",
}

POSTURE_CLASSES = ["none", "open_palm", "pinch", "two_fingers", "fist"]


def normalize_landmarks(raw_points: List[Tuple[float, float]]) -> Tuple[List[float], Dict[str, float]]:
    """
    Normalizes a 21-landmark hand pose into canonical right-hand frame.
    Returns:
        (feature_vector, metadata_dict)
    """
    if len(raw_points) != 21:
        raise ValueError(f"Expected 21 landmarks, got {len(raw_points)}")

    w_x, w_y = raw_points[0]
    # Screen coordinates have origin at top-left (Y down).
    # Convert to standard Cartesian with wrist at origin and +Y pointing up towards screen top:
    # x_cart = x - w_x
    # y_cart = w_y - y
    translated = [(p[0] - w_x, w_y - p[1]) for p in raw_points]

    m_x, m_y = translated[9]
    scale = math.hypot(m_x, m_y)
    if scale < 1e-6:
        scale = 1.0

    scaled = [(p[0] / scale, p[1] / scale) for p in translated]

    # Rotate so wrist -> middleMCP (point 9) points vertically up (+Y, angle pi/2)
    m9_x, m9_y = scaled[9]
    current_angle = math.atan2(m9_y, m9_x)
    target_angle = math.pi / 2.0
    delta_theta = target_angle - current_angle

    cos_d = math.cos(delta_theta)
    sin_d = math.sin(delta_theta)

    rotated = [
        (p[0] * cos_d - p[1] * sin_d, p[0] * sin_d + p[1] * cos_d)
        for p in scaled
    ]

    # Mirroring check: in canonical right hand palm-facing camera,
    # Pinky MCP (17) is to the right of Index MCP (5): (rotated[17].x - rotated[5].x > 0).
    # If rotated[17].x < rotated[5].x, it is a mirrored/left-hand configuration.
    dx_mcp = rotated[17][0] - rotated[5][0]
    is_mirrored = dx_mcp < 0.0

    if is_mirrored:
        canonical = [(-p[0], p[1]) for p in rotated]
    else:
        canonical = rotated

    # 42 coordinates
    coords_42: List[float] = []
    for p in canonical:
        coords_42.append(round(p[0], 6))
        coords_42.append(round(p[1], 6))

    # Engineered metrics
    def dist(i: int, j: int) -> float:
        return math.hypot(canonical[i][0] - canonical[j][0], canonical[i][1] - canonical[j][1])

    palm_width = dist(5, 17)
    thumb_index_dist = dist(4, 8)
    thumb_middle_dist = dist(4, 12)
    index_middle_dist = dist(8, 12)

    # Tip to wrist distances (wrist is 0,0)
    tip_wrist_dists = [
        math.hypot(canonical[4][0], canonical[4][1]),
        math.hypot(canonical[8][0], canonical[8][1]),
        math.hypot(canonical[12][0], canonical[12][1]),
        math.hypot(canonical[16][0], canonical[16][1]),
        math.hypot(canonical[20][0], canonical[20][1]),
    ]

    # Finger curl cosine angles
    def joint_cos(p_base: int, p_mid: int, p_tip: int) -> float:
        v1_x = canonical[p_mid][0] - canonical[p_base][0]
        v1_y = canonical[p_mid][1] - canonical[p_base][1]
        v2_x = canonical[p_tip][0] - canonical[p_mid][0]
        v2_y = canonical[p_tip][1] - canonical[p_mid][1]
        norm1 = math.hypot(v1_x, v1_y)
        norm2 = math.hypot(v2_x, v2_y)
        if norm1 < 1e-6 or norm2 < 1e-6:
            return 1.0
        dot = (v1_x * v2_x + v1_y * v2_y) / (norm1 * norm2)
        return max(-1.0, min(1.0, dot))

    curls = [
        joint_cos(1, 2, 4),    # Thumb
        joint_cos(5, 6, 8),    # Index
        joint_cos(9, 10, 12),  # Middle
        joint_cos(13, 14, 16), # Ring
        joint_cos(17, 18, 20), # Pinky
    ]

    engineered = [
        round(palm_width, 6),
        round(thumb_index_dist, 6),
        round(thumb_middle_dist, 6),
        round(index_middle_dist, 6),
    ] + [round(d, 6) for d in tip_wrist_dists] + [round(c, 6) for c in curls]

    features = coords_42 + engineered
    meta = {
        "scale": scale,
        "delta_theta": delta_theta,
        "is_mirrored": is_mirrored,
    }
    return features, meta


def get_feature_column_names() -> List[str]:
    names: List[str] = []
    for i in range(21):
        names.append(f"lm_{i}_x")
        names.append(f"lm_{i}_y")
    names.extend([
        "eng_palm_width",
        "eng_thumb_index_dist",
        "eng_thumb_middle_dist",
        "eng_index_middle_dist",
        "eng_tip_wrist_thumb",
        "eng_tip_wrist_index",
        "eng_tip_wrist_middle",
        "eng_tip_wrist_ring",
        "eng_tip_wrist_pinky",
        "eng_curl_thumb",
        "eng_curl_index",
        "eng_curl_middle",
        "eng_curl_ring",
        "eng_curl_pinky",
    ])
    return names


def parse_frames_from_file(file_path: str) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    if not os.path.exists(file_path):
        return records

    with open(file_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue

            # Look for landmark points
            pts: Optional[List[Tuple[float, float]]] = None
            if "primaryPoints" in rec and isinstance(rec["primaryPoints"], list) and len(rec["primaryPoints"]) == 21:
                pts = [(float(p.get("x", 0.0)), float(p.get("y", 0.0))) for p in rec["primaryPoints"]]
            elif "landmarks" in rec and isinstance(rec["landmarks"], list) and len(rec["landmarks"]) == 21:
                pts = [(float(p.get("x", 0.0)), float(p.get("y", 0.0))) for p in rec["landmarks"]]
            elif "primaryLandmarks" in rec and isinstance(rec["primaryLandmarks"], list) and len(rec["primaryLandmarks"]) == 21:
                pts = [(float(p.get("x", 0.0)), float(p.get("y", 0.0))) for p in rec["primaryLandmarks"]]

            if pts is None:
                continue

            gt_label = rec.get("groundTruth", rec.get("label", "idle"))
            posture_class = LABEL_TO_POSTURE.get(gt_label, "none")

            records.append({
                "source_file": os.path.basename(file_path),
                "timestamp": rec.get("timestamp", 0.0),
                "frame_index": rec.get("frameIndex", 0),
                "raw_label": gt_label,
                "posture_class": posture_class,
                "raw_points": pts,
            })
    return records


def export_features(
    input_paths: List[str],
    output_csv: str,
    split_json: str,
    test_ratio: float = 0.30,
    seed: int = 42,
) -> Dict[str, Any]:
    file_list: List[str] = []
    for p in input_paths:
        if os.path.isdir(p):
            for fname in sorted(os.listdir(p)):
                if fname.endswith(".jsonl"):
                    file_list.append(os.path.join(p, fname))
        elif os.path.isfile(p):
            file_list.append(p)

    file_list = sorted(list(set(file_list)))
    if not file_list:
        print("[Export] No input JSONL files found.")
        return {"total_files": 0, "total_samples": 0}

    # Session/file-level split (never by frame!)
    rng = random.Random(seed)
    shuffled_files = list(file_list)
    rng.shuffle(shuffled_files)

    n_test = max(1, int(len(shuffled_files) * test_ratio)) if len(shuffled_files) > 1 else 0
    test_files = set(shuffled_files[:n_test])
    train_files = set(shuffled_files[n_test:])

    split_manifest = {
        "seed": seed,
        "test_ratio": test_ratio,
        "train_files": sorted(list(train_files)),
        "test_files": sorted(list(test_files)),
    }

    os.makedirs(os.path.dirname(os.path.abspath(split_json)) or ".", exist_ok=True)
    with open(split_json, "w", encoding="utf-8") as f:
        json.dump(split_manifest, f, indent=2)

    feature_col_names = get_feature_column_names()
    csv_header = ["source_file", "split", "frame_index", "timestamp", "raw_label", "posture_class"] + feature_col_names

    os.makedirs(os.path.dirname(os.path.abspath(output_csv)) or ".", exist_ok=True)
    total_samples = 0
    class_counts: Dict[str, int] = {c: 0 for c in POSTURE_CLASSES}

    with open(output_csv, "w", newline="", encoding="utf-8") as out_f:
        writer = csv.writer(out_f)
        writer.writerow(csv_header)

        for fpath in file_list:
            split_tag = "test" if fpath in test_files else "train"
            frames = parse_frames_from_file(fpath)
            for fr in frames:
                try:
                    feat_vec, _ = normalize_landmarks(fr["raw_points"])
                except Exception:
                    continue

                row = [
                    fr["source_file"],
                    split_tag,
                    fr["frame_index"],
                    fr["timestamp"],
                    fr["raw_label"],
                    fr["posture_class"],
                ] + feat_vec
                writer.writerow(row)
                total_samples += 1
                class_counts[fr["posture_class"]] = class_counts.get(fr["posture_class"], 0) + 1

    summary = {
        "total_files": len(file_list),
        "train_files_count": len(train_files),
        "test_files_count": len(test_files),
        "total_samples": total_samples,
        "class_counts": class_counts,
        "output_csv": output_csv,
        "split_json": split_json,
    }
    return summary


def main():
    parser = argparse.ArgumentParser(description="Export and normalize hand features for posture classifier.")
    parser.add_argument("--data", nargs="+", default=["tools/fixtures"], help="Data directories or files")
    parser.add_argument("--incidents", default=None, help="Incidents directory")
    parser.add_argument("--output", default="tools/data/features.csv", help="Output features CSV path")
    parser.add_argument("--split", default="tools/data/split.json", help="Output split manifest JSON path")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for file split")
    parser.add_argument("--test-ratio", type=float, default=0.30, help="Test file ratio")
    args = parser.parse_args()

    inputs = list(args.data)
    if args.incidents:
        inputs.append(args.incidents)

    res = export_features(
        input_paths=inputs,
        output_csv=args.output,
        split_json=args.split,
        test_ratio=args.test_ratio,
        seed=args.seed,
    )
    print("=== Feature Export Summary ===")
    print(json.dumps(res, indent=2))


if __name__ == "__main__":
    main()
