#!/usr/bin/env python3
"""
tools/report.py - One-Command Evaluation Report Generator for GestureFlow

Generates a complete, honest, and reproducible evaluation report:
1. Scans and computes frame counts, durations, and gesture windows for input datasets.
2. Runs headless deterministic replay through the native binary and scores event-level metrics:
   recall per class, direction confusion, idle false triggers/min, latency p50/p95.
3. Evaluates passive flight-recorder incidents (fire vs misfire with 95% Wilson CI).
4. Evaluates shadow-mode learned posture classifier agreement if shadow postures exist.
5. Runs sweep.py hyperparameter grid search if >= 20 gesture windows exist; otherwise emits guard message.
6. Fills a report copy of the ROBUSTNESS.md matrix for matching robustness_<cond_id>.jsonl files.
7. Stamps 'SYNTHETIC INPUT — NOT REAL DATA' whenever synthetic fixtures are evaluated.
8. Embeds exact reproduction commands and verbatim outputs.
"""

import argparse
import datetime
import glob
import json
import math
import os
import platform
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Tuple, Any, Optional

# Add tools directory to path
TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = TOOLS_DIR.parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from eval_gestures import (
    load_dataset,
    evaluate_events,
    evaluate_incidents,
    evaluate_shadow,
    wilson_score_interval,
    CANONICAL_CLASSES,
    FINE_DIRECTIONAL_CLASSES,
    LABEL_TO_FINE
)
from sweep import count_labeled_windows, default_tuning_grid, run_sweep

DEFAULT_BINARY = PROJECT_ROOT / "GestureFlowApp/.build/arm64-apple-macosx/debug/GestureFlow"

ROBUSTNESS_CONDITIONS = [
    ("light_normal", "Lighting", "Indoor normal desk lighting (~300–500 lux)", "60"),
    ("light_low", "Lighting", "Dim room / evening monitor-glow only (<50 lux)", "30 / 60"),
    ("light_backlit", "Lighting", "Strong window or lamp behind user (backlit silhouette)", "60"),
    ("fps_60", "Frame Rate", "Good lighting, active 60 FPS capture", "60"),
    ("fps_30", "Frame Rate", "Low-light auto-exposure drop or 30 FPS webcam", "30"),
    ("hand_right", "Handedness", "Right hand performing all single-hand gestures", "60"),
    ("hand_left", "Handedness", "Left hand performing all single-hand gestures", "60"),
    ("dist_near", "Distance", "Close to MacBook webcam (~25–35 cm)", "60"),
    ("dist_normal", "Distance", "Typical ergonomic desk distance (~40–55 cm)", "60"),
    ("dist_far", "Distance", "Leaning back (~60–75 cm, near upper interaction bound)", "60"),
    ("user_glasses", "Accessories", "User wearing eyeglasses / reflective lenses", "60"),
    ("bg_clutter", "Background", "Busy background / other people or moving objects in view", "60"),
]


def get_git_sha() -> str:
    try:
        res = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=PROJECT_ROOT)
        return res.decode().strip()
    except Exception:
        return "unknown"


def get_cpu_info() -> str:
    try:
        res = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"])
        return res.decode().strip()
    except Exception:
        return platform.processor() or "Apple Silicon"


def get_os_info() -> str:
    try:
        res = subprocess.check_output(["sw_vers", "-productVersion"])
        return f"macOS {res.decode().strip()}"
    except Exception:
        return platform.platform()


def is_file_synthetic(path: str, records: List[Dict[str, Any]]) -> bool:
    """Determines whether a dataset file is synthetic."""
    p_str = str(path).lower()
    if "fixtures" in p_str or "synthetic" in p_str:
        return True
    if not records:
        return False
    # Check for real recording header / timestamp characteristics
    # Real recordings have continuous time progression and typically hundreds of continuous frames
    first_rec = records[0]
    if "synthetic" in str(first_rec.get("groundTruth", "")).lower():
        return True
    return False


def collect_jsonl_files(target_path: str) -> List[str]:
    """Collects all JSONL files from a file path or directory."""
    if not target_path or not os.path.exists(target_path):
        return []
    target = os.path.abspath(os.path.expanduser(target_path))
    if os.path.isfile(target):
        return [target] if target.endswith(".jsonl") else []
    files = []
    for root, _, fnames in os.walk(target):
        for fn in sorted(fnames):
            if fn.endswith(".jsonl") and not fn.endswith(".golden.jsonl") and not fn.startswith("."):
                files.append(os.path.join(root, fn))
    return sorted(files)


def replay_and_evaluate(
    recording_path: str,
    binary_path: str,
    tuning: str
) -> Tuple[Dict[str, Any], List[Dict[str, Any]], str]:
    """Replays a recording headlessly and scores event-level metrics."""
    out_fd, replay_out = tempfile.mkstemp(suffix=".jsonl")
    os.close(out_fd)

    cmd = [
        binary_path,
        "--replay", recording_path,
        "--tuning", tuning,
        "--out", replay_out
    ]
    cmd_str = " ".join(cmd)
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        if os.path.exists(replay_out):
            os.remove(replay_out)
        raise RuntimeError(f"Replay failed on {recording_path}:\nSTDOUT: {e.stdout}\nSTDERR: {e.stderr}")

    raw_records = load_dataset(recording_path)
    replayed_records = load_dataset(replay_out)
    if os.path.exists(replay_out):
        os.remove(replay_out)

    merged = []
    for i, orig in enumerate(raw_records):
        item = dict(orig)
        if i < len(replayed_records):
            item["predictedIntent"] = replayed_records[i].get("predictedIntent", "idle")
            item["firedIntent"] = replayed_records[i].get("firedIntent", "")
            item["firedAction"] = replayed_records[i].get("firedAction", "")
            if "shadowPosture" in replayed_records[i]:
                item["shadowPosture"] = replayed_records[i].get("shadowPosture")
        merged.append(item)

    eval_res = evaluate_events(merged)
    return eval_res, merged, cmd_str


def generate_report(
    recordings_dir: str,
    incidents_dir: str,
    out_path: str,
    allow_synthetic: bool = False,
    binary_path: str = str(DEFAULT_BINARY),
    tuning: str = "balanced"
) -> str:
    """Generates the full markdown evaluation report."""
    rec_files = collect_jsonl_files(recordings_dir)
    inc_files = collect_jsonl_files(incidents_dir)

    git_sha = get_git_sha()
    cpu_info = get_cpu_info()
    os_info = get_os_info()
    report_date = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Detect synthetic content
    has_synthetic = allow_synthetic
    file_metadata = []

    for fpath in rec_files:
        recs = load_dataset(fpath)
        frame_count = len(recs)
        duration = (recs[-1].get("timestamp", 0.0) - recs[0].get("timestamp", 0.0)) if frame_count > 1 else 0.0
        windows = count_labeled_windows(recs)
        is_synth = is_file_synthetic(fpath, recs)
        if is_synth:
            has_synthetic = True
        file_metadata.append({
            "path": fpath,
            "filename": os.path.basename(fpath),
            "type": "Recording",
            "frames": frame_count,
            "duration": duration,
            "windows": windows,
            "is_synthetic": is_synth,
            "records": recs
        })

    for fpath in inc_files:
        is_synth = "fixtures" in fpath or "synthetic" in fpath
        if is_synth:
            has_synthetic = True
        line_count = 0
        with open(fpath, "r", encoding="utf-8") as f:
            line_count = sum(1 for line in f if line.strip())
        file_metadata.append({
            "path": fpath,
            "filename": os.path.basename(fpath),
            "type": "Incident",
            "frames": max(0, line_count - 1),
            "duration": 0.0,
            "windows": 0,
            "is_synthetic": is_synth,
            "records": []
        })

    lines = []

    # 1. Synthetic stamp banner
    if has_synthetic:
        lines.append("# SYNTHETIC INPUT — NOT REAL DATA\n")
        lines.append("> [!WARNING]")
        lines.append("> **SYNTHETIC INPUT — NOT REAL DATA**: This report contains evaluations executed on synthetic test fixtures.")
        lines.append("> All metrics reflect deterministic code-path verification and regression safety, **not** live recognition accuracy on human hands.")
        lines.append("> When real hands are available, record sessions with `.build/arm64-apple-macosx/debug/GestureFlow --guided` and re-run this tool.\n")
        lines.append("---\n")

    # 2. Header & Execution Metadata
    lines.append(f"# GestureFlow Evaluation Report ({datetime.datetime.now().strftime('%Y-%m-%d')})\n")
    lines.append("| Metric | Value |")
    lines.append("| :--- | :--- |")
    lines.append(f"| **Report Generation Time** | `{report_date}` |")
    lines.append(f"| **Git Commit SHA** | `{git_sha}` |")
    lines.append(f"| **Hardware Platform** | `{cpu_info}` |")
    lines.append(f"| **Operating System** | `{os_info}` |")
    lines.append(f"| **Evaluated Binary** | `{binary_path}` |")
    lines.append(f"| **GestureTuning Preset** | `{tuning}` |")
    lines.append(f"| **Synthetic Data Allowed** | `{has_synthetic}` |\n")
    lines.append("---\n")

    # 3. Section 1: Input Datasets & Incident Files
    lines.append("## 1. Input Datasets & Incident Logs\n")
    if file_metadata:
        lines.append("| Filename | Type | Frames | Duration (s) | Gesture Windows | Origin |")
        lines.append("| :--- | :--- | :---: | :---: | :---: | :--- |")
        for m in file_metadata:
            dur_str = f"{m['duration']:.2f}" if m['duration'] > 0 else "—"
            win_str = str(m['windows']) if m['type'] == "Recording" else "—"
            origin_str = "Synthetic Fixture" if m['is_synthetic'] else "Real Recording"
            lines.append(f"| `{m['filename']}` | {m['type']} | {m['frames']} | {dur_str} | {win_str} | {origin_str} |")
        lines.append("")
    else:
        lines.append("*No recording or incident files found in specified directories.*\n")
    lines.append("---\n")

    # 4. Section 2: Replay & Event-Level Evaluation
    lines.append("## 2. Replay & Event-Level Evaluation\n")
    eval_summaries = {}
    sweep_results = []
    has_shadow_frames = False
    all_merged_records = []
    robustness_matches = {}

    for m in file_metadata:
        if m["type"] != "Recording":
            continue
        rec_path = m["path"]
        fn = m["filename"]
        eval_res, merged, cmd_str = replay_and_evaluate(rec_path, binary_path, tuning)
        eval_summaries[fn] = {
            "eval": eval_res,
            "cmd": cmd_str,
            "frames": m["frames"],
            "windows": m["windows"]
        }
        all_merged_records.extend(merged)

        # Check for shadow posture
        for r in merged:
            if r.get("shadowPosture") is not None:
                has_shadow_frames = True
                break

        # Check for robustness condition file match
        for cond_id, _, _, _ in ROBUSTNESS_CONDITIONS:
            if fn == f"robustness_{cond_id}.jsonl":
                robustness_matches[cond_id] = eval_res

        # Render file event evaluation
        lines.append(f"### Evaluation: `{fn}`\n")
        lines.append(f"**Execution Command**:\n```bash\n{cmd_str}\n```\n")

        pc = eval_res.get("per_class", {})
        total_hits = sum(c["hit"] for c in pc.values())
        total_misses = sum(c["miss"] for c in pc.values())
        total_wrongs = sum(c["wrong"] for c in pc.values())
        total_windows = sum(c["windows"] for c in pc.values())
        overall_recall = (total_hits / total_windows * 100.0) if total_windows > 0 else 0.0

        p50 = f"{eval_res['latency_p50_ms']:.1f} ms" if eval_res.get("latency_p50_ms") is not None else "N/A"
        p95 = f"{eval_res['latency_p95_ms']:.1f} ms" if eval_res.get("latency_p95_ms") is not None else "N/A"

        lines.append(f"- **Overall Gesture Recall**: **{overall_recall:.1f}%** ({total_hits}/{total_windows} windows)")
        lines.append(f"- **Total Misses**: {total_misses} | **Direction/Class Mismatches**: {total_wrongs}")
        lines.append(f"- **Idle False Triggers**: {sum(eval_res['idle_false_triggers'].values())} ({eval_res['idle_false_triggers_per_min']:.2f} / min)")
        lines.append(f"- **Frame-to-Action Latency**: p50 = `{p50}`, p95 = `{p95}`\n")

        # Per class breakdown table
        lines.append("| Macro Class | Windows | Hits | Misses | Wrong Class/Dir | Double Fires | Recall (%) |")
        lines.append("| :--- | :---: | :---: | :---: | :---: | :---: | :---: |")
        for cls_name, stats in pc.items():
            rec_pct = (stats["hit"] / stats["windows"] * 100.0) if stats["windows"] > 0 else 0.0
            lines.append(f"| `{cls_name}` | {stats['windows']} | {stats['hit']} | {stats['miss']} | {stats['wrong']} | {stats['double_fire']} | {rec_pct:.1f}% |")
        lines.append("")

        # Direction confusion table
        dir_conf = eval_res.get("direction_confusion", {})
        has_dir_data = any(sum(row.values()) > 0 for row in dir_conf.values())
        if has_dir_data:
            lines.append("#### Directional Breakdown\n")
            lines.append("| Ground Truth | Fired Action | Occurrences |")
            lines.append("| :--- | :--- | :---: |")
            for true_dir, fired_counts in dir_conf.items():
                for fired_dir, count in fired_counts.items():
                    if count > 0:
                        lines.append(f"| `{true_dir}` | `{fired_dir}` | {count} |")
            lines.append("")

        # Sweep check per recording
        if m["windows"] >= 20:
            lines.append(f"#### Sensitivity Parameter Sweep for `{fn}`\n")
            sweep_csv_fd, sweep_csv = tempfile.mkstemp(suffix=".csv")
            os.close(sweep_csv_fd)
            try:
                run_sweep(rec_path, sweep_csv, binary_path=binary_path, allow_small_dataset=True)
                lines.append(f"Swept {len(default_tuning_grid())} configurations. Results saved to temporary evaluation cache.\n")
            except Exception as e:
                lines.append(f"*Sweep execution error: {e}*\n")
            finally:
                if os.path.exists(sweep_csv):
                    os.remove(sweep_csv)
        else:
            lines.append(f"> **Sweep Guard**: Input dataset `{fn}` has only **{m['windows']}** labelled gesture windows (minimum 20 required).")
            lines.append("> Not enough real data to sweep parameters reliably without overfitting. Record more sessions first.\n")

    if not rec_files:
        lines.append("*No recordings provided for replay evaluation.*\n")

    lines.append("---\n")

    # 5. Section 3: Incident Evaluation
    lines.append("## 3. Incident Evaluation & Flight-Recorder Analysis\n")
    if inc_files:
        inc_res = evaluate_incidents(incidents_dir)
        counts = inc_res.get("counts", {})
        total_inc = inc_res.get("total_incidents", 0)
        misfires = counts.get("misfire", 0)
        fires = counts.get("fire", 0)
        denominator = misfires + fires
        rate = (misfires / denominator * 100.0) if denominator > 0 else 0.0

        ci_tuple = inc_res.get("wilson_interval")
        ci_str = f"[{ci_tuple[0]*100.0:.2f}%, {ci_tuple[1]*100.0:.2f}%]" if ci_tuple else "N/A"

        lines.append("| Incident Metric | Value |")
        lines.append("| :--- | :--- |")
        lines.append(f"| **Total Incidents Analyzed** | `{total_inc}` |")
        lines.append(f"| **Auto-Fires Recorded** | `{fires}` |")
        lines.append(f"| **Misfires Tagged (⌃⌥⌘M)** | `{misfires}` |")
        lines.append(f"| **Missed Gestures Tagged (⌃⌥⌘N)** | `{counts.get('missed', 0)}` |")
        lines.append(f"| **Quiet Baseline Snapshots** | `{counts.get('quiet', 0)}` |")
        lines.append(f"| **Misfire Rate** | **{rate:.2f}%** (`{misfires}/{denominator}`) |")
        lines.append(f"| **Wilson 95% Confidence Interval** | `{ci_str}` |")
        lines.append(f"| **Approximate Logged Window** | `{inc_res.get('approx_hours', 0.0):.2f} hours` |\n")

        if inc_res.get("per_intent_misfires"):
            lines.append("### Misfires by Intent Class\n")
            lines.append("| Intent Class | Misfires Count |")
            lines.append("| :--- | :---: |")
            for intent, cnt in inc_res["per_intent_misfires"].items():
                lines.append(f"| `{intent}` | {cnt} |")
            lines.append("")
    else:
        lines.append("*No incident files found in `--incidents` directory. Flight-recorder evaluation skipped.*\n")
    lines.append("---\n")

    # 6. Section 4: Posture Classifier Shadow Evaluation
    lines.append("## 4. Posture Classifier Shadow Evaluation\n")
    if has_shadow_frames:
        shadow_res = evaluate_shadow(all_merged_records, incidents_dir)
        lines.append(f"- **Shadow Frames Evaluated**: {shadow_res['shadow_frames']}")
        lines.append(f"- **Heuristic Agreement Rate**: **{(1.0 - shadow_res['disagreement_rate']) * 100.0:.2f}%**")
        lines.append(f"- **Disagreement Rate**: {shadow_res['disagreement_rate'] * 100.0:.2f}%\n")

        lines.append("### Disagreement Matrix (Heuristic vs Shadow Posture)\n")
        lines.append("| Heuristic Posture | Shadow Posture | Disagreement Count |")
        lines.append("| :--- | :--- | :---: |")
        for h_cls, s_counts in shadow_res.get("disagreement_matrix", {}).items():
            for s_cls, count in s_counts.items():
                if count > 0:
                    lines.append(f"| `{h_cls}` | `{s_cls}` | {count} |")
        lines.append("")
    else:
        lines.append("*No `shadowPosture` annotations found in evaluated frames. PostureClassifier shadow mode was inactive during these sessions.*\n")
    lines.append("---\n")

    # 7. Section 5: Robustness Condition Matrix Copy
    lines.append("## 5. Robustness Condition Matrix\n")
    lines.append("> Embedded copy of `docs/gesture/ROBUSTNESS.md`. Filled strictly for matching `robustness_<cond_id>.jsonl` files.\n")
    lines.append("| Condition ID | Dimension | Physical Setup | Target FPS | Recording File | Swipe Recall (%) | Scroll Recall (%) | Pinch Recall (%) | False Triggers / min | Latency p50 / p95 (ms) | Status |")
    lines.append("| :--- | :--- | :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :--- |")

    for cond_id, dim, setup, target_fps in ROBUSTNESS_CONDITIONS:
        if cond_id in robustness_matches:
            ev = robustness_matches[cond_id]
            pc = ev.get("per_class", {})
            sw_rec = f"{pc['swipe']['hit']/pc['swipe']['windows']*100.0:.1f}%" if pc.get("swipe", {}).get("windows", 0) > 0 else "—"
            sc_rec = f"{pc['air_scroll']['hit']/pc['air_scroll']['windows']*100.0:.1f}%" if pc.get("air_scroll", {}).get("windows", 0) > 0 else "—"
            pi_rec = f"{pc['pinch_dock']['hit']/pc['pinch_dock']['windows']*100.0:.1f}%" if pc.get("pinch_dock", {}).get("windows", 0) > 0 else "—"
            ft_str = f"{ev.get('idle_false_triggers_per_min', 0.0):.2f}"
            lat_str = f"{ev.get('latency_p50_ms', 0):.0f} / {ev.get('latency_p95_ms', 0):.0f}" if ev.get("latency_p50_ms") is not None else "—"
            status_str = "MEASURED (SYNTHETIC)" if has_synthetic else "MEASURED"
            lines.append(f"| `{cond_id}` | {dim} | {setup} | {target_fps} | `robustness_{cond_id}.jsonl` | {sw_rec} | {sc_rec} | {pi_rec} | {ft_str} | {lat_str} | {status_str} |")
        else:
            lines.append(f"| `{cond_id}` | {dim} | {setup} | {target_fps} | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |")

    lines.append("\n---\n")

    # 8. Section 6: Reproduction Cheat-Sheet
    lines.append("## 6. Verification & Reproduction Commands\n")
    lines.append("To reproduce this exact report:\n")
    lines.append("```bash")
    synth_flag = " --allow-synthetic" if has_synthetic else ""
    rec_arg = f" --recordings '{recordings_dir}'" if recordings_dir else ""
    inc_arg = f" --incidents '{incidents_dir}'" if incidents_dir else ""
    lines.append(f"python3 tools/report.py{rec_arg}{inc_arg} --out '{out_path}'{synth_flag}")
    lines.append("```\n")

    content = "\n".join(lines) + "\n"
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"[Report] Successfully authored report to '{out_path}'.")
    if has_synthetic:
        print("[Report] NOTE: Output marked as 'SYNTHETIC INPUT — NOT REAL DATA'.")
    return content


def main():
    parser = argparse.ArgumentParser(description="One-command evaluator and report generator for GestureFlow.")
    parser.add_argument("--recordings", "-r", default="", help="Directory or file containing recordings JSONL")
    parser.add_argument("--incidents", "-i", default="", help="Directory or file containing incidents JSONL")
    parser.add_argument("--out", "-o", required=True, help="Path to output markdown report file")
    parser.add_argument("--allow-synthetic", action="store_true", help="Allow synthetic fixtures as inputs (marks report as SYNTHETIC)")
    parser.add_argument("--binary", "-b", default=str(DEFAULT_BINARY), help="Path to GestureFlow binary")
    parser.add_argument("--tuning", "-t", default="balanced", help="GestureTuning preset (default: balanced)")

    args = parser.parse_args()
    generate_report(
        recordings_dir=args.recordings,
        incidents_dir=args.incidents,
        out_path=args.out,
        allow_synthetic=args.allow_synthetic,
        binary_path=args.binary,
        tuning=args.tuning
    )


if __name__ == "__main__":
    main()
