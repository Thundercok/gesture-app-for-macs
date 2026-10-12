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
import math
import os
import sys
from collections import defaultdict
from typing import Dict, List, Tuple, Any, Optional

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

FINE_DIRECTIONAL_CLASSES = [
    "swipe_left",
    "swipe_right",
    "swipe_up",
    "swipe_down",
    "scroll_down",
    "scroll_up",
]

LABEL_TO_FINE = {
    "swipe_left": "swipe_left",
    "swipe_right": "swipe_right",
    "swipe_up": "swipe_up",
    "swipe_down": "swipe_down",
    "2": "swipe_left",
    "3": "swipe_right",
    "4": "swipe_up",
    "5": "swipe_down",

    "scroll_down": "scroll_down",
    "scroll_up": "scroll_up",
    "flick": "scroll_down",
    "6": "scroll_down",
    "7": "scroll_up",

    "pinch_dock": "pinch_dock",
    "pinch": "pinch_dock",
    "dock": "pinch_dock",
    "1": "pinch_dock",

    "zoom": "spatial_zoom",
    "spatial_zoom": "spatial_zoom",
    "8": "spatial_zoom",
}


def load_dataset(filepath: str) -> List[Dict[str, Any]]:
    """Loads a JSONL dataset file, skipping incident header if present."""
    records = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                if line_num == 1 and "incident" in record and "createdAt" in record:
                    continue
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


# ---------------------------------------------------------------------------
# Event-level evaluation
#
# Swipes/flicks are instantaneous: the arbiter claims and commits in a single
# frame, so a frame-level "state" confusion matrix almost never sees them.
# What matters to the user is: "did the right action fire once, and nothing
# fired when I wasn't gesturing?"  Windows are derived from contiguous
# ground-truth labels; label "ignore" marks transition time and is not scored.
# ---------------------------------------------------------------------------

EVENT_GRACE_S = 0.60   # a fire up to this long after the window ends still belongs to it
IGNORE_LABELS = {"ignore", "transition"}


def _ts(rec: Dict[str, Any]) -> float:
    if "timestamp" in rec:
        return float(rec["timestamp"])
    return float(rec.get("frameIndex", 0)) / 30.0


def extract_events(records: List[Dict[str, Any]]) -> List[Tuple[float, str, str]]:
    """Discrete fired events: explicit firedIntent/firedAction, plus pinch_dock state rising edges.
    
    Returns list of (timestamp, macro_class, fine_action).
    """
    events: List[Tuple[float, str, str]] = []
    prev_pinch = False
    for rec in records:
        t = _ts(rec)
        fired_intent = str(rec.get("firedIntent", "")).lower()
        fired_action = str(rec.get("firedAction", "")).lower()

        if fired_action:
            macro = LABEL_TO_MACRO.get(fired_action, "")
            if not macro and fired_intent:
                macro = PREDICTED_TO_MACRO.get(fired_intent, "")
            if macro and macro != "idle":
                fine = LABEL_TO_FINE.get(fired_action, fired_action)
                events.append((t, macro, fine))
        elif fired_intent:
            if fired_intent in PREDICTED_TO_MACRO and PREDICTED_TO_MACRO[fired_intent] != "idle":
                macro = PREDICTED_TO_MACRO[fired_intent]
                fine = LABEL_TO_FINE.get(fired_intent, macro)
                events.append((t, macro, fine))
            elif fired_intent in LABEL_TO_MACRO and LABEL_TO_MACRO[fired_intent] != "idle":
                macro = LABEL_TO_MACRO[fired_intent]
                fine = LABEL_TO_FINE.get(fired_intent, fired_intent)
                events.append((t, macro, fine))

        pinch_now = str(rec.get("predictedIntent", "")).lower() == "pinch_dock"
        if pinch_now and not prev_pinch:
            events.append((t, "pinch_dock", "pinch_dock"))
        prev_pinch = pinch_now
    return events


def build_windows(records: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    windows: List[Dict[str, Any]] = []
    cur = None
    for rec in records:
        raw = str(rec.get("groundTruth", "idle")).lower()
        t = _ts(rec)
        if raw in IGNORE_LABELS:
            macro = None
        else:
            macro = LABEL_TO_MACRO.get(raw, None)
        key = (raw, macro)
        if cur is None or cur["key"] != key:
            if cur is not None:
                windows.append(cur)
            cur = {"key": key, "raw": raw, "macro": macro, "t0": t, "t1": t}
        else:
            cur["t1"] = t
    if cur is not None:
        windows.append(cur)
    return windows


def is_event_match(event: Tuple[float, str, str], window: Dict[str, Any]) -> bool:
    """Checks whether fired event matches the ground truth window.
    
    If both window and event carry directional detail, directions must match.
    If either lacks directional detail (e.g. legacy recording), macro match suffices.
    """
    _, e_macro, e_fine = event
    w_macro = window.get("macro")
    if e_macro != w_macro:
        return False
    w_raw = window.get("raw", "")
    w_fine = LABEL_TO_FINE.get(w_raw, w_macro)
    if w_fine in FINE_DIRECTIONAL_CLASSES and e_fine in FINE_DIRECTIONAL_CLASSES:
        return w_fine == e_fine
    return True


def evaluate_events(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    records = sorted(records, key=_ts)
    events = extract_events(records)
    windows = build_windows(records)

    classes = [c for c in CANONICAL_CLASSES if c != "idle"]
    per_class = {c: {"windows": 0, "hit": 0, "miss": 0, "wrong": 0, "double_fire": 0, "latencies": []} for c in classes}
    confusion: Dict[str, Dict[str, int]] = {c: defaultdict(int) for c in classes}   # true -> fired class / "none"
    direction_confusion: Dict[str, Dict[str, int]] = {c: defaultdict(int) for c in FINE_DIRECTIONAL_CLASSES}
    used = set()

    for idx, w in enumerate(windows):
        if w["macro"] is None or w["macro"] == "idle":
            continue
        cls = w["macro"]
        w_raw = w.get("raw", "")
        w_fine = LABEL_TO_FINE.get(w_raw, cls)
        is_dir = w_fine in FINE_DIRECTIONAL_CLASSES

        lo, hi = w["t0"], w["t1"] + EVENT_GRACE_S
        in_win = [(i, e) for i, e in enumerate(events) if lo <= e[0] <= hi]
        for i, _ in in_win:
            used.add(i)
        pc = per_class[cls]
        pc["windows"] += 1

        correct = [e for _, e in in_win if is_event_match(e, w)]
        wrong = [e for _, e in in_win if not is_event_match(e, w)]

        if correct:
            pc["hit"] += 1
            pc["latencies"].append(correct[0][0] - w["t0"])
            confusion[cls][cls] += 1
            if is_dir:
                direction_confusion[w_fine][correct[0][2]] += 1
            if cls != "pinch_dock" and len(correct) > 1:
                pc["double_fire"] += 1
        else:
            if wrong:
                pc["wrong"] += 1
                we = wrong[0]
                fired_col = we[1] if we[1] != cls else we[2]
                confusion[cls][fired_col] += 1
                if is_dir:
                    direction_confusion[w_fine][we[2]] += 1
            else:
                pc["miss"] += 1
                confusion[cls]["none"] += 1
                if is_dir:
                    direction_confusion[w_fine]["none"] += 1

        # Any additional wrong-class or wrong-dir fire alongside a correct one is a clash symptom
        if correct and wrong:
            for we in wrong:
                fired_col = we[1] if we[1] != cls else we[2]
                confusion[cls][fired_col] += 1
                if is_dir:
                    direction_confusion[w_fine][we[2]] += 1

    # Idle: every fire not attributed to a gesture window and lying in idle time is a false trigger
    idle_time = 0.0
    idle_windows = []
    for w in windows:
        if w["macro"] == "idle":
            idle_time += max(0.0, w["t1"] - w["t0"])
            idle_windows.append(w)
    false_triggers: Dict[str, int] = defaultdict(int)
    for i, (t, c, act) in enumerate(events):
        if i in used:
            continue
        if any(w["t0"] <= t <= w["t1"] + EVENT_GRACE_S for w in idle_windows):
            false_triggers[c] += 1
    total_false = sum(false_triggers.values())
    far_per_min = (total_false / (idle_time / 60.0)) if idle_time > 0 else 0.0

    return {
        "per_class": per_class,
        "confusion": {k: dict(v) for k, v in confusion.items()},
        "direction_confusion": {k: dict(v) for k, v in direction_confusion.items()},
        "idle_seconds": idle_time,
        "idle_false_triggers": dict(false_triggers),
        "idle_false_triggers_per_min": far_per_min,
        "total_events": len(events),
    }


def print_event_report(res: Dict[str, Any]) -> None:
    print("\n" + "=" * 78)
    print(" EVENT-LEVEL REPORT (did the right action fire, once, and nothing else?) ".center(78))
    print("=" * 78)
    hdr = f"{'Class':<14} | {'Windows':>7} | {'Hit':>5} | {'Miss':>5} | {'Wrong':>5} | {'Recall':>7} | {'2x fire':>7} | {'Latency':>9}"
    print(hdr)
    print("-" * len(hdr))
    for cls, pc in res["per_class"].items():
        if pc["windows"] == 0:
            continue
        recall = pc["hit"] / pc["windows"]
        lat = (sum(pc["latencies"]) / len(pc["latencies"]) * 1000.0) if pc["latencies"] else float("nan")
        print(f"{cls:<14} | {pc['windows']:>7} | {pc['hit']:>5} | {pc['miss']:>5} | {pc['wrong']:>5} | {recall*100:>6.1f}% | {pc['double_fire']:>7} | {lat:>7.0f}ms")
    print("-" * len(hdr))
    print("\nWhat fired during each true gesture (rows = what you did, cols = what the app did):")
    cols = [c for c in CANONICAL_CLASSES if c != "idle"] + ["none"]
    extra_cols = []
    for row in res["confusion"].values():
        for k in row.keys():
            if k not in cols and k not in extra_cols:
                extra_cols.append(k)
    all_cols = [c for c in CANONICAL_CLASSES if c != "idle"] + extra_cols + ["none"]
    print(f"{'true':<14} | " + " | ".join(f"{c[:10]:>10}" for c in all_cols))
    for cls, row in res["confusion"].items():
        if res["per_class"][cls]["windows"] == 0:
            continue
        print(f"{cls:<14} | " + " | ".join(f"{row.get(c, 0):>10}" for c in all_cols))

    dir_conf = res.get("direction_confusion", {})
    has_dir_data = any(sum(row.values()) > 0 for row in dir_conf.values())
    if has_dir_data:
        print("\nDIRECTION CONFUSION (fine directional actions):")
        dir_cols = FINE_DIRECTIONAL_CLASSES + ["none"]
        extra_dir = []
        for row in dir_conf.values():
            for k in row.keys():
                if k not in dir_cols and k not in extra_dir:
                    extra_dir.append(k)
        full_dir_cols = FINE_DIRECTIONAL_CLASSES + extra_dir + ["none"]
        dhdr = f"{'true':<14} | " + " | ".join(f"{c[:10]:>10}" for c in full_dir_cols)
        print(dhdr)
        print("-" * len(dhdr))
        for dcls in FINE_DIRECTIONAL_CLASSES:
            row = dir_conf.get(dcls, {})
            if sum(row.values()) == 0:
                continue
            print(f"{dcls:<14} | " + " | ".join(f"{row.get(c, 0):>10}" for c in full_dir_cols))

    print(f"\nIdle time scored: {res['idle_seconds']:.0f}s")
    print(f"False triggers while idle: {sum(res['idle_false_triggers'].values())} "
          f"({res['idle_false_triggers_per_min']:.2f}/min)  by class: {res['idle_false_triggers']}")
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


def wilson_score_interval(successes: int, total: int, confidence: float = 0.95) -> Optional[Tuple[float, float]]:
    """Computes Wilson score confidence interval for a binomial proportion.
    
    Returns (lower, upper) or None if total == 0.
    """
    if total <= 0:
        return None
    z = 1.95996 if abs(confidence - 0.95) < 0.01 else 1.96
    p = float(successes) / float(total)
    denominator = 1.0 + (z * z) / total
    centre = (p + (z * z) / (2.0 * total)) / denominator
    spread = (z * math.sqrt((p * (1.0 - p) + (z * z) / (4.0 * total)) / total)) / denominator
    return (max(0.0, centre - spread), min(1.0, centre + spread))


def evaluate_incidents(incidents_path: str) -> Dict[str, Any]:
    """Analyzes incident log directory/files generated by IncidentRecorder."""
    target_path = os.path.expanduser(incidents_path)
    if not os.path.exists(target_path):
        return {
            "error": f"Path '{target_path}' does not exist.",
            "total_incidents": 0,
            "counts": {"fire": 0, "misfire": 0, "missed": 0, "quiet": 0},
            "misfire_rate": None,
            "wilson_interval": None,
            "per_intent_misfires": {},
            "approx_hours": 0.0
        }

    files = []
    if os.path.isdir(target_path):
        for root, _, fnames in os.walk(target_path):
            for fn in sorted(fnames):
                if fn.endswith(".jsonl"):
                    files.append(os.path.join(root, fn))
    elif os.path.isfile(target_path) and target_path.endswith(".jsonl"):
        files.append(target_path)

    counts = {"fire": 0, "misfire": 0, "missed": 0, "quiet": 0}
    per_intent_misfires = defaultdict(int)

    for fpath in files:
        header = None
        frames = []
        with open(fpath, "r", encoding="utf-8") as f:
            for lnum, line in enumerate(f, start=1):
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    if lnum == 1 and "incident" in obj:
                        header = obj
                    else:
                        frames.append(obj)
                except json.JSONDecodeError:
                    continue

        kind = None
        if header and "incident" in header:
            kind = str(header["incident"]).lower()
        else:
            base = os.path.basename(fpath).replace(".jsonl", "")
            for candidate in ["misfire", "missed", "quiet", "fire"]:
                if candidate in base:
                    kind = candidate
                    break

        if kind in counts:
            counts[kind] += 1

        if kind == "misfire":
            fired_set = set()
            for fr in frames:
                fi = str(fr.get("firedIntent", "")).lower()
                if fi and fi in PREDICTED_TO_MACRO and PREDICTED_TO_MACRO[fi] != "idle":
                    fired_set.add(PREDICTED_TO_MACRO[fi])
                pi = str(fr.get("predictedIntent", "")).lower()
                if pi and pi in PREDICTED_TO_MACRO and PREDICTED_TO_MACRO[pi] not in ("idle", "cooldown"):
                    fired_set.add(PREDICTED_TO_MACRO[pi])
            if not fired_set:
                per_intent_misfires["unknown"] += 1
            else:
                for intent in fired_set:
                    per_intent_misfires[intent] += 1

    total_decision_events = counts["fire"] + counts["misfire"]
    misfire_rate = (counts["misfire"] / total_decision_events) if total_decision_events > 0 else None
    interval = wilson_score_interval(counts["misfire"], total_decision_events)

    approx_hours = len(files) * (4.0 / 3600.0)
    if counts["quiet"] > 0:
        approx_hours = max(approx_hours, counts["quiet"] * (10.0 / 60.0))

    return {
        "total_incidents": len(files),
        "counts": counts,
        "misfire_rate": misfire_rate,
        "wilson_interval": interval,
        "per_intent_misfires": dict(per_intent_misfires),
        "approx_hours": approx_hours
    }


def print_incidents_report(results: Dict[str, Any], title: str = "PASSIVE FLIGHT RECORDER INCIDENT REPORT"):
    print("\n" + "=" * 78)
    print(f" {title.center(76)} ")
    print("=" * 78)

    counts = results["counts"]
    print(f" Total Incident Dumps:    {results['total_incidents']}")
    print(f"   - Auto-fires (fire):   {counts['fire']}")
    print(f"   - Misfires (⌃⌥⌘M):      {counts['misfire']}")
    print(f"   - Missed (⌃⌥⌘N):        {counts['missed']}")
    print(f"   - Quiet baselines:     {counts['quiet']}")
    print("-" * 78)

    if results["misfire_rate"] is not None:
        rate_pct = results["misfire_rate"] * 100.0
        interval_str = ""
        if results["wilson_interval"]:
            lo, hi = results["wilson_interval"]
            interval_str = f" [95% CI: {lo*100.0:.1f}% - {hi*100.0:.1f}%]"
        print(f" Misfire Rate:           {rate_pct:.1f}%{interval_str}")
        print(f"   (Calculated as misfire / (fire + misfire), n = {counts['fire'] + counts['misfire']})")
    else:
        print(" Misfire Rate:           N/A (No fires or misfires recorded yet)")

    if results["per_intent_misfires"]:
        print("\nMisfires Breakdown by Fired/Active Intent:")
        for intent, count in sorted(results["per_intent_misfires"].items(), key=lambda x: -x[1]):
            print(f"   - {intent:<16}: {count} incidents")

    if results["approx_hours"] > 0:
        print(f"\n Approximate active tracking covered: ~{results['approx_hours']:.1f} hours")
    print("=" * 78 + "\n")


def main():
    parser = argparse.ArgumentParser(description="Evaluate GestureFlow gesture recognition accuracy and confusion matrix.")
    parser.add_argument("--data", "-d", help="Path to recorded JSONL landmark dataset file or directory")
    parser.add_argument("--replayed", "-r", help="Path to replayed JSONL file produced by --replay (merges with ground truth from --data)")
    parser.add_argument("--incidents", "-i", help="Path to incident recording directory (evaluates misfire rate and flight recorder logs)")
    parser.add_argument("--test", action="store_true", help="Run self-test using synthetic benchmark data")
    parser.add_argument("--output-json", "-o", help="Optional output JSON path for evaluation results")

    args = parser.parse_args()

    if args.incidents:
        results = evaluate_incidents(args.incidents)
        print_incidents_report(results, title=f"INCIDENT REPORT: {os.path.basename(os.path.expanduser(args.incidents))}")
        if args.output_json:
            with open(args.output_json, "w", encoding="utf-8") as f:
                json.dump(results, f, indent=2)
            print(f"Saved JSON metrics to: {args.output_json}")
        return

    if args.replayed:
        replayed_path = os.path.expanduser(args.replayed)
        if not os.path.exists(replayed_path):
            print(f"Error: Replayed path '{replayed_path}' does not exist.", file=sys.stderr)
            sys.exit(1)
        replayed_records = load_dataset(replayed_path)

        if args.data:
            data_path = os.path.expanduser(args.data)
            if not os.path.exists(data_path):
                print(f"Error: Data path '{data_path}' does not exist.", file=sys.stderr)
                sys.exit(1)
            gt_records = load_dataset(data_path)
            records = []
            for i in range(min(len(gt_records), len(replayed_records))):
                merged = dict(gt_records[i])
                merged["firedIntent"] = replayed_records[i].get("firedIntent", "")
                merged["firedAction"] = replayed_records[i].get("firedAction", "")
                if "predictedIntent" in replayed_records[i]:
                    merged["predictedIntent"] = replayed_records[i]["predictedIntent"]
                records.append(merged)
        else:
            records = replayed_records
    elif args.test or not args.data:
        print("[Notice] Self-test: hand-made frames that check the SCORER ARITHMETIC only. These numbers say nothing about real recognition accuracy.")
        records = generate_synthetic_benchmark()
        results = evaluate_dataset(records)
        print_ascii_report(results, title="SYNTHETIC GESTURE RECOGNITION SELF-TEST")
        if args.output_json:
            with open(args.output_json, "w", encoding="utf-8") as f:
                json.dump(results, f, indent=2)
        return
    else:
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
        print(f"Error: No valid JSONL records found.", file=sys.stderr)
        sys.exit(1)

    results = evaluate_dataset(records)
    has_events = any("firedIntent" in r for r in records)
    if has_events:
        print_event_report(evaluate_events(records))
    else:
        print("[Warning] Records have no 'firedIntent' (recorded with an older build). "
              "Frame-level state accuracy under-reports instantaneous gestures such as swipes; re-record for event-level metrics.")
    source_name = os.path.basename(args.data or args.replayed or "replayed")
    print_ascii_report(results, title=f"FRAME-LEVEL STATE REPORT: {source_name}")

    if args.output_json:
        with open(args.output_json, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2)
        print(f"Saved JSON metrics to: {args.output_json}")


if __name__ == "__main__":
    main()
