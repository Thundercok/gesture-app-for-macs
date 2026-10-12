#!/usr/bin/env python3
"""
tools/sweep.py - Grid-search hyperparameter tuner for GestureFlow gesture engine

Sweeps over GestureTuning parameters, replaying candidate parameter vectors headlessly
through the native binary, scoring event recall, direction accuracy, and false triggers.

Requirements:
- Stdlib only (json, csv, os, sys, argparse, subprocess, tempfile).
- Must refuse to run when input dataset has fewer than 20 labelled gesture windows ("not enough real data").
"""

import argparse
import csv
import json
import os
import subprocess
import sys
import tempfile
from typing import Dict, List, Any

# Default path to binary
DEFAULT_BINARY = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "GestureFlowApp/.build/arm64-apple-macosx/debug/GestureFlow"
)

# Reference eval_gestures module
from eval_gestures import load_dataset, evaluate_events


def count_labeled_windows(records: List[Dict[str, Any]]) -> int:
    """Counts the number of non-idle gesture episodes in records."""
    count = 0
    in_gesture = False
    for rec in records:
        gt = str(rec.get("groundTruth", "idle")).lower()
        is_gesture = gt not in ("idle", "0", "none", "noise", "scratch", "type", "unlabeled")
        if is_gesture and not in_gesture:
            count += 1
            in_gesture = True
        elif not is_gesture:
            in_gesture = False
    return count


def default_tuning_grid() -> List[Dict[str, Any]]:
    """Generates standard parameter combinations for sensitivity search."""
    grid = []
    # Test safe, balanced, and sensitive anchor points
    for disp in [0.055, 0.065, 0.085]:
        for vel in [0.40, 0.50, 0.65]:
            for dwell in [0.03, 0.05, 0.15]:
                tuning = {
                    "preset": "balanced",
                    "swipeMinDisplacement": disp,
                    "swipeMinVelocity": vel,
                    "swipeAxisDominance": 1.30,
                    "openPalmDwellSeconds": dwell,
                    "pinchCalmHandSpeed": 0.42,
                    "postPinchSwipeGuardSeconds": 0.35,
                    "swipeCooldownSeconds": 0.45,
                    "scrollFlickMinVelocity": 0.42
                }
                grid.append(tuning)
    return grid


def run_sweep(
    data_path: str,
    output_csv_path: str,
    binary_path: str = DEFAULT_BINARY,
    grid: List[Dict[str, Any]] = None,
    allow_small_dataset: bool = False
) -> None:
    if not os.path.isfile(binary_path):
        print(f"Error: GestureFlow binary not found at '{binary_path}'. Run 'swift build' first.", file=sys.stderr)
        sys.exit(1)

    records = load_dataset(data_path)
    if not records:
        print(f"Error: No valid records found in '{data_path}'.", file=sys.stderr)
        sys.exit(1)

    window_count = count_labeled_windows(records)
    if window_count < 20 and not allow_small_dataset:
        print(
            f"Error: Input dataset has only {window_count} labelled gesture windows (minimum 20 required).\n"
            f"Not enough real data to sweep parameters reliably without overfitting. Record more sessions first.",
            file=sys.stderr
        )
        sys.exit(1)

    if grid is None:
        grid = default_tuning_grid()

    print(f"Starting sweep over {len(grid)} parameter sets on '{data_path}' ({len(records)} frames, {window_count} gesture windows)...")

    fieldnames = [
        "swipeMinDisplacement",
        "swipeMinVelocity",
        "openPalmDwellSeconds",
        "overall_recall",
        "total_hits",
        "total_misses",
        "total_wrongs",
        "double_fires",
        "false_triggers_per_min"
    ]

    results = []

    for idx, params in enumerate(grid, start=1):
        # Write temporary tuning JSON
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f_tune:
            json.dump(params, f_tune)
            tune_path = f_tune.name

        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f_out:
            out_path = f_out.name

        try:
            cmd = [
                binary_path,
                "--replay", data_path,
                "--tuning", tune_path,
                "--out", out_path
            ]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            if res.returncode != 0:
                print(f"[Warning] Run {idx} failed with code {res.returncode}: {res.stderr}")
                continue

            replayed_records = load_dataset(out_path)
            # Merge with ground truth
            merged = []
            for i in range(min(len(records), len(replayed_records))):
                item = dict(records[i])
                item["firedIntent"] = replayed_records[i].get("firedIntent", "")
                item["firedAction"] = replayed_records[i].get("firedAction", "")
                merged.append(item)

            ev_results = evaluate_events(merged)

            total_hits = sum(m["hit"] for m in ev_results["per_class"].values())
            total_misses = sum(m["miss"] for m in ev_results["per_class"].values())
            total_wrongs = sum(m["wrong"] for m in ev_results["per_class"].values())
            double_fires = sum(m["double_fire"] for m in ev_results["per_class"].values())
            total_windows = sum(m["windows"] for m in ev_results["per_class"].values())
            overall_recall = (total_hits / total_windows * 100.0) if total_windows > 0 else 0.0

            row = {
                "swipeMinDisplacement": params["swipeMinDisplacement"],
                "swipeMinVelocity": params["swipeMinVelocity"],
                "openPalmDwellSeconds": params["openPalmDwellSeconds"],
                "overall_recall": round(overall_recall, 2),
                "total_hits": total_hits,
                "total_misses": total_misses,
                "total_wrongs": total_wrongs,
                "double_fires": double_fires,
                "false_triggers_per_min": round(ev_results.get("idle_false_triggers_per_min", 0.0), 2)
            }
            results.append(row)
            print(f"[{idx}/{len(grid)}] disp={params['swipeMinDisplacement']} vel={params['swipeMinVelocity']} dwell={params['openPalmDwellSeconds']}s -> recall={row['overall_recall']}% wrongs={total_wrongs} false/min={row['false_triggers_per_min']}")

        finally:
            if os.path.exists(tune_path):
                os.remove(tune_path)
            if os.path.exists(out_path):
                os.remove(out_path)

    os.makedirs(os.path.dirname(os.path.abspath(output_csv_path)), exist_ok=True)
    with open(output_csv_path, "w", newline="", encoding="utf-8") as f_csv:
        writer = csv.DictWriter(f_csv, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"\nSweep complete! Saved {len(results)} configurations to '{output_csv_path}'.")


def main():
    parser = argparse.ArgumentParser(description="Sweep GestureTuning parameters across recorded dataset.")
    parser.add_argument("--data", "-d", required=True, help="Path to input dataset JSONL file")
    parser.add_argument("--output-csv", "-o", required=True, help="Path to output CSV results file")
    parser.add_argument("--binary", "-b", default=DEFAULT_BINARY, help="Path to GestureFlow binary")
    parser.add_argument("--allow-small-dataset", action="store_true", help="Allow running on datasets with < 20 windows (for integration tests only)")

    args = parser.parse_args()
    run_sweep(
        data_path=args.data,
        output_csv_path=args.output_csv,
        binary_path=args.binary,
        allow_small_dataset=args.allow_small_dataset
    )


if __name__ == "__main__":
    main()
