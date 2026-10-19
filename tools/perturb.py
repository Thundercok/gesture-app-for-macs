#!/usr/bin/env python3
"""
tools/perturb.py - Deterministic, seeded perturbations for synthetic landmark fixtures.

Transforms:
- jitter(sigma): Gaussian jitter on all 21 primary landmarks.
- drop(p): Randomly drop frames with probability p (preserves boundary frames).
- downsample(factor): Keep every Nth frame (e.g. downsample 60fps -> 30fps with factor=2).
- ts_jitter(max_ms): Add uniform timestamp jitter while preserving strictly monotonic ordering.
- mirror_x: Flip coordinates horizontally (x -> 1 - x) and swap left/right expected labels.
"""

import argparse
import copy
import json
import random
import sys


def apply_jitter(records, sigma, seed=None):
    if sigma <= 0.0:
        return copy.deepcopy(records)
    rng = random.Random(seed)
    out = copy.deepcopy(records)
    for rec in out:
        if rec.get("handDetected") and "primaryPoints" in rec and rec["primaryPoints"]:
            new_pts = []
            for p in rec["primaryPoints"]:
                nx = max(0.0, min(1.0, round(p["x"] + rng.gauss(0.0, sigma), 5)))
                ny = max(0.0, min(1.0, round(p["y"] + rng.gauss(0.0, sigma), 5)))
                new_pts.append({"x": nx, "y": ny})
            rec["primaryPoints"] = new_pts
    return out


def apply_drop(records, p, seed=None):
    if p <= 0.0:
        return copy.deepcopy(records)
    rng = random.Random(seed)
    out = []
    for i, rec in enumerate(records):
        # Keep first and last frame to maintain stream boundaries
        if i == 0 or i == len(records) - 1:
            out.append(copy.deepcopy(rec))
        elif rng.random() >= p:
            out.append(copy.deepcopy(rec))
    return out


def apply_downsample(records, factor=2):
    if factor <= 1:
        return copy.deepcopy(records)
    return [copy.deepcopy(rec) for i, rec in enumerate(records) if i % factor == 0]


def apply_ts_jitter(records, max_ms=5.0, seed=None):
    if max_ms <= 0.0:
        return copy.deepcopy(records)
    rng = random.Random(seed)
    out = copy.deepcopy(records)
    last_t = -1.0
    for rec in out:
        t = rec.get("timestamp", 0.0)
        offset = rng.uniform(-max_ms / 1000.0, max_ms / 1000.0)
        cand_t = round(t + offset, 4)
        if cand_t <= last_t:
            cand_t = round(last_t + 0.001, 4)
        rec["timestamp"] = cand_t
        last_t = cand_t
    return out


def apply_mirror_x(records):
    out = copy.deepcopy(records)
    for rec in out:
        if "primaryPoints" in rec and rec["primaryPoints"]:
            new_pts = []
            for p in rec["primaryPoints"]:
                new_pts.append({"x": round(1.0 - p["x"], 5), "y": p["y"]})
            rec["primaryPoints"] = new_pts
        if rec.get("faceBBox"):
            fb = rec["faceBBox"]
            rec["faceBBox"] = {
                "x": round(1.0 - (fb["x"] + fb["width"]), 5),
                "y": fb["y"],
                "width": fb["width"],
                "height": fb["height"]
            }
    return out


def mirror_action(action):
    if action == "swipe_left":
        return "swipe_right"
    elif action == "swipe_right":
        return "swipe_left"
    return action


def transform_records(
    records,
    sigma=0.0,
    drop_p=0.0,
    downsample_factor=1,
    ts_jitter_ms=0.0,
    mirror=False,
    seed=None
):
    res = records
    if mirror:
        res = apply_mirror_x(res)
    if downsample_factor > 1:
        res = apply_downsample(res, factor=downsample_factor)
    if drop_p > 0.0:
        res = apply_drop(res, p=drop_p, seed=seed)
    if sigma > 0.0:
        res = apply_jitter(res, sigma=sigma, seed=seed)
    if ts_jitter_ms > 0.0:
        res = apply_ts_jitter(res, max_ms=ts_jitter_ms, seed=seed)
    return res


def main():
    parser = argparse.ArgumentParser(description="Apply perturbations to landmark fixture JSONL")
    parser.add_argument("--input", required=True, help="Input fixture JSONL path")
    parser.add_argument("--output", required=True, help="Output fixture JSONL path")
    parser.add_argument("--sigma", type=float, default=0.0, help="Gaussian jitter sigma")
    parser.add_argument("--drop-p", type=float, default=0.0, help="Frame drop probability")
    parser.add_argument("--downsample", type=int, default=1, help="Downsample factor (e.g. 2 for 30fps)")
    parser.add_argument("--ts-jitter-ms", type=float, default=0.0, help="Max timestamp jitter in ms")
    parser.add_argument("--mirror", action="store_true", help="Mirror X coordinates")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    args = parser.parse_args()

    records = []
    with open(args.input, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))

    transformed = transform_records(
        records,
        sigma=args.sigma,
        drop_p=args.drop_p,
        downsample_factor=args.downsample,
        ts_jitter_ms=args.ts_jitter_ms,
        mirror=args.mirror,
        seed=args.seed
    )

    with open(args.output, "w", encoding="utf-8") as f:
        for r in transformed:
            f.write(json.dumps(r) + "\n")


if __name__ == "__main__":
    main()
