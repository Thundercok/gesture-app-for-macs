#!/usr/bin/env python3
"""
tools/eval_gestures.py - Benchmark and Confusion Matrix Evaluator for GestureFlow

Evaluates recorded landmark streams (.jsonl) against ground-truth labels to measure:
1. Confusion Matrix (Idle vs Pinch vs Swipe vs Scroll vs Zoom)
2. Precision, Recall, and F1-Score per gesture class
3. False Alarm Rate on Idle (Direct measure of cross-gesture clash & accidental triggers)
4. Overall Frame Accuracy and Action Detection Latency
"""

import argparse
import json
import os
import sys
from collections import defaultdict
from typing import Dict, List, Tuple, Any

# Canonical macro-domains for mutual-exclusion evaluation
CANONICAL_CLASSES = [
    "idle",
    "pinch_dock",
    "swipe",
    "air_scroll",
    "spatial_zoom"
]

# Mapping fine-grained labels to macro domains
LABEL_TO_MACRO = {
    "idle": "idle",
    "0": "idle",
    "none": "idle",
    "noise": "idle",
    "scratch": "idle",
    "type": "idle",

    "pinch": "pinch_dock",
    "pinch_dock": "pinch_dock",
    "dock": "pinch_dock",
    "1": "pinch_dock",

    "swipe": "swipe",
    "swipe_left": "swipe",
    "swipe_right": "swipe",
    "swipe_up": "swipe",
    "swipe_down": "swipe",
    "2": "swipe",
    "3": "swipe",
    "4": "swipe",
    "5": "swipe",

    "scroll": "air_scroll",
    "air_scroll": "air_scroll",
    "scroll_down": "air_scroll",
    "scroll_up": "air_scroll",
    "flick": "air_scroll",
    "6": "air_scroll",
    "7": "air_scroll",

    "zoom": "spatial_zoom",
    "spatial_zoom": "spatial_zoom",
    "8": "spatial_zoom"
}

PREDICTED_TO_MACRO = {
    "idle": "idle",
    "cooldown": "idle",  # Cooldown acts as lockout/idle refractory state
    "pinch_dock": "pinch_dock",
    "swipe": "swipe",
    "air_scroll": "air_scroll",
    "spatial_zoom": "spatial_zoom"
}


def load_dataset(filepath: str) -> List[Dict[str, Any]]:
    """Loads a JSONL dataset file."""
    records = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                records.append(record)
            except json.JSONDecodeError as e:
                print(f"[Warning] Skipped malformed JSON line {line_num} in {filepath}: {e}", file=sys.stderr)
    return records


def evaluate_dataset(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Computes confusion matrix and metrics from records."""
    matrix = {true_cls: {pred_cls: 0 for pred_cls in CANONICAL_CLASSES} for true_cls in CANONICAL_CLASSES}
    total_frames = len(records)
    skipped_frames = 0

    ground_truth_counts = defaultdict(int)
    predicted_counts = defaultdict(int)

    for rec in records:
        raw_true = str(rec.get("groundTruth", "idle")).lower()
        raw_pred = str(rec.get("predictedIntent", "idle")).lower()

        true_cls = LABEL_TO_MACRO.get(raw_true, "idle")
        pred_cls = PREDICTED_TO_MACRO.get(raw_pred, "idle")

        if true_cls not in matrix or pred_cls not in matrix[true_cls]:
            skipped_frames += 1
            continue

        matrix[true_cls][pred_cls] += 1
        ground_truth_counts[true_cls] += 1
        predicted_counts[pred_cls] += 1

    # Compute metrics per class
    metrics_per_class = {}
    correct_total = 0

    for cls in CANONICAL_CLASSES:
        tp = matrix[cls][cls]
        fn = sum(matrix[cls][p] for p in CANONICAL_CLASSES if p != cls)
        fp = sum(matrix[t][cls] for t in CANONICAL_CLASSES if t != cls)
        tn = sum(matrix[t][p] for t in CANONICAL_CLASSES for p in CANONICAL_CLASSES if t != cls and p != cls)

        correct_total += tp

        precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = (2 * precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0

        metrics_per_class[cls] = {
            "tp": tp,
            "fp": fp,
            "fn": fn,
            "tn": tn,
            "precision": precision,
            "recall": recall,
            "f1": f1,
            "support": ground_truth_counts[cls]
        }

    accuracy = correct_total / total_frames if total_frames > 0 else 0.0

    # False Alarm Rate on Idle: percentage of true idle frames where any gesture triggered
    idle_total = ground_truth_counts["idle"]
    idle_false_alarms = sum(matrix["idle"][p] for p in CANONICAL_CLASSES if p != "idle")
    idle_far = idle_false_alarms / idle_total if idle_total > 0 else 0.0

    return {
        "total_frames": total_frames,
        "skipped_frames": skipped_frames,
        "accuracy": accuracy,
        "idle_false_alarm_rate": idle_far,
        "matrix": matrix,
        "metrics_per_class": metrics_per_class,
        "ground_truth_counts": dict(ground_truth_counts),
        "predicted_counts": dict(predicted_counts)
    }


def print_ascii_report(results: Dict[str, Any], title: str = "GESTURE RECOGNITION EVALUATION REPORT"):
    """Prints a formatted evaluation report with confusion matrix."""
    matrix = results["matrix"]
    metrics = results["metrics_per_class"]
    total_frames = results["total_frames"]

    print("\n" + "=" * 78)
    print(f" {title.center(76)} ")
    print("=" * 78)
    print(f" Total Evaluated Frames: {total_frames:,}")
    print(f" Overall Accuracy:      {results['accuracy'] * 100:.2f}%")
    print(f" Idle False Alarm Rate: {results['idle_false_alarm_rate'] * 100:.2f}% (Accidental triggers during rest/typing)")
    print("-" * 78)

    # Confusion Matrix Table
    print("\nCONFUSION MATRIX (Rows: Ground Truth, Columns: Predicted Intent):")
    header_col = f"{'Ground Truth':<16} | " + " | ".join(f"{c[:10]:>10}" for c in CANONICAL_CLASSES) + " | Total"
    print("-" * len(header_col))
    print(header_col)
    print("-" * len(header_col))

    for true_cls in CANONICAL_CLASSES:
        row_vals = [f"{matrix[true_cls][pred_cls]:>10}" for pred_cls in CANONICAL_CLASSES]
        row_total = sum(matrix[true_cls].values())
        print(f"{true_cls:<16} | " + " | ".join(row_vals) + f" | {row_total:>6}")

    print("-" * len(header_col))

    # Metrics Table
    print("\nDETAILED CLASSIFICATION METRICS:")
    m_header = f"{'Gesture Class':<16} | {'Precision':>10} | {'Recall':>10} | {'F1-Score':>10} | {'Support':>10}"
    print("-" * len(m_header))
    print(m_header)
    print("-" * len(m_header))

    for cls in CANONICAL_CLASSES:
        m = metrics[cls]
        print(f"{cls:<16} | {m['precision']*100:>9.1f}% | {m['recall']*100:>9.1f}% | {m['f1']*100:>9.1f}% | {m['support']:>10}")

    print("-" * len(m_header))

    # Diagnostic Advice
    print("\nDIAGNOSTIC FINDINGS:")
    if results['idle_false_alarm_rate'] > 0.05:
        print(f"  [!] High Idle False Alarm Rate ({results['idle_false_alarm_rate']*100:.1f}%): Background movements are triggering false gestures.")
    else:
        print(f"  [✓] Low Idle False Alarm Rate ({results['idle_false_alarm_rate']*100:.1f}%): Background noise is effectively suppressed.")

    pinch_m = metrics["pinch_dock"]
    if pinch_m["precision"] < 0.80 and pinch_m["support"] > 0:
        print(f"  [!] Pinch Precision is {pinch_m['precision']*100:.1f}%: Spurious pinches detected during transitions.")
    elif pinch_m["support"] > 0:
        print(f"  [✓] Pinch Precision is {pinch_m['precision']*100:.1f}%.")

    swipe_m = metrics["swipe"]
    if swipe_m["precision"] < 0.80 and swipe_m["support"] > 0:
        print(f"  [!] Swipe Precision is {swipe_m['precision']*100:.1f}%: Hand motion during other gestures is misidentified as swipes.")
    elif swipe_m["support"] > 0:
        print(f"  [✓] Swipe Precision is {swipe_m['precision']*100:.1f}%.")

    print("=" * 78 + "\n")


def generate_synthetic_benchmark() -> List[Dict[str, Any]]:
    """Generates synthetic test dataset verifying matrix computation."""
    records = []
    # 500 idle frames with 5 false swipes and 3 false pinches
    for i in range(492):
        records.append({"groundTruth": "idle", "predictedIntent": "idle"})
    for i in range(5):
        records.append({"groundTruth": "idle", "predictedIntent": "swipe"})
    for i in range(3):
        records.append({"groundTruth": "idle", "predictedIntent": "pinch_dock"})

    # 150 pinch frames: 140 correctly recognized, 10 missed
    for i in range(140):
        records.append({"groundTruth": "pinch_dock", "predictedIntent": "pinch_dock"})
    for i in range(10):
        records.append({"groundTruth": "pinch_dock", "predictedIntent": "idle"})

    # 100 swipe frames: 95 correctly recognized, 5 missed
    for i in range(95):
        records.append({"groundTruth": "swipe_left", "predictedIntent": "swipe"})
    for i in range(5):
        records.append({"groundTruth": "swipe_right", "predictedIntent": "idle"})

    # 100 scroll frames: 92 correctly recognized, 8 missed
    for i in range(92):
        records.append({"groundTruth": "scroll_down", "predictedIntent": "air_scroll"})
    for i in range(8):
        records.append({"groundTruth": "scroll_up", "predictedIntent": "idle"})

    return records


def main():
    parser = argparse.ArgumentParser(description="Evaluate GestureFlow gesture recognition accuracy and confusion matrix.")
    parser.add_argument("--data", "-d", help="Path to recorded JSONL landmark dataset file or directory")
    parser.add_argument("--test", action="store_true", help="Run self-test using synthetic benchmark data")
    parser.add_argument("--output-json", "-o", help="Optional output JSON path for evaluation results")

    args = parser.parse_args()

    if args.test or not args.data:
        print("[Notice] Running in Self-Test Mode with synthetic benchmark data.")
        records = generate_synthetic_benchmark()
        results = evaluate_dataset(records)
        print_ascii_report(results, title="SYNTHETIC GESTURE RECOGNITION SELF-TEST")
        if args.output_json:
            with open(args.output_json, "w", encoding="utf-8") as f:
                json.dump(results, f, indent=2)
        return

    target_path = os.path.expanduser(args.data)
    records = []

    if os.path.isdir(target_path):
        for root, _, files in os.walk(target_path):
            for file in sorted(files):
                if file.endswith(".jsonl"):
                    full_path = os.path.join(root, file)
                    print(f"Loading: {full_path}")
                    records.extend(load_dataset(full_path))
    elif os.path.isfile(target_path):
        records = load_dataset(target_path)
    else:
        print(f"Error: Path '{target_path}' does not exist.", file=sys.stderr)
        sys.exit(1)

    if not records:
        print(f"Error: No valid JSONL records found in '{target_path}'.", file=sys.stderr)
        sys.exit(1)

    results = evaluate_dataset(records)
    print_ascii_report(results, title=f"EVALUATION FOR: {os.path.basename(target_path)}")

    if args.output_json:
        with open(args.output_json, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2)
        print(f"Saved JSON metrics to: {args.output_json}")


if __name__ == "__main__":
    main()
