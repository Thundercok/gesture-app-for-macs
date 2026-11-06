#!/usr/bin/env python3
"""
tools/plot_kinematics.py - Kinematic Diagnostic & Benchmark Tool
Plots Raw vs Filtered vs Aperture profiles and computes baseline metrics:
1. Rest Jitter (RMS & Peak-to-Peak in px/normalized units during idle)
2. Ballistic Phase Lag (ms delay between raw and filtered velocity peaks)
3. Heisenberg Click Deflection (px drift from aperture closure onset to commit)
"""

import argparse
import json
import math
import os
import sys
from typing import Dict, List, Optional, Tuple

os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib_cache")

try:
    import numpy as np
except ImportError:
    print("Error: numpy is required. Install via: pip3 install numpy", file=sys.stderr)
    sys.exit(1)



def parse_frames(jsonl_path: str) -> List[dict]:
    frames = []
    with open(jsonl_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
                # Skip incident header if present
                if "incident" in rec and "primaryPoints" not in rec:
                    continue
                frames.append(rec)
            except json.JSONDecodeError:
                continue
    return frames


def extract_signals(frames: List[dict]):
    timestamps = []
    raw_index_tip = []
    raw_middle_mcp = []
    raw_wrist = []
    apertures = []
    is_pinching = []

    for f in frames:
        if not f.get("handDetected", False) or not f.get("primaryPoints"):
            continue
        pts = f["primaryPoints"]
        if len(pts) < 21:
            continue

        t = f.get("timestamp", 0.0)
        timestamps.append(t)

        wrist = pts[0]
        thumb_tip = pts[4]
        index_tip = pts[8]
        middle_mcp = pts[9]

        raw_wrist.append((wrist["x"], wrist["y"]))
        raw_index_tip.append((index_tip["x"], index_tip["y"]))
        raw_middle_mcp.append((middle_mcp["x"], middle_mcp["y"]))

        # Hand span for aperture normalization: distance wrist(0) to middle_mcp(9)
        span = math.hypot(middle_mcp["x"] - wrist["x"], middle_mcp["y"] - wrist["y"])
        span = max(span, 0.05)

        # Aperture: distance thumb_tip(4) to index_tip(8) / span
        ap = math.hypot(thumb_tip["x"] - index_tip["x"], thumb_tip["y"] - index_tip["y"]) / span
        apertures.append(ap)
        is_pinching.append(bool(f.get("isPinching", False)))

    return (
        np.array(timestamps),
        np.array(raw_index_tip),
        np.array(raw_middle_mcp),
        np.array(apertures),
        np.array(is_pinching),
    )


def compute_diagnostics(t: np.ndarray, index_tip: np.ndarray, middle_mcp: np.ndarray, ap: np.ndarray, pinch: np.ndarray):
    report = {}

    if len(t) < 10:
        return {"error": "Not enough frames (< 10) to compute diagnostics."}

    dt = np.diff(t)
    median_dt = np.median(dt) if len(dt) > 0 else 0.0166
    fps = 1.0 / median_dt if median_dt > 0 else 60.0
    report["effective_fps"] = float(fps)
    report["total_duration_sec"] = float(t[-1] - t[0]) if len(t) > 1 else 0.0
    report["total_frames"] = len(t)

    # 1. Jitter Analysis (first 2-3 seconds or when speed is minimal)
    # Velocity on index tip vs middle MCP
    v_index = np.hypot(np.diff(index_tip[:, 0]), np.diff(index_tip[:, 1])) / np.maximum(dt, 1e-4)
    v_mcp = np.hypot(np.diff(middle_mcp[:, 0]), np.diff(middle_mcp[:, 1])) / np.maximum(dt, 1e-4)

    # Find stationary segments (lowest 20% speed)
    quiet_idx = np.where(v_index < np.percentile(v_index, 20))[0]
    if len(quiet_idx) > 5:
        quiet_pos_index = index_tip[quiet_idx]
        quiet_pos_mcp = middle_mcp[quiet_idx]

        rms_index = float(np.sqrt(np.mean(np.sum((quiet_pos_index - np.mean(quiet_pos_index, axis=0)) ** 2, axis=1))))
        rms_mcp = float(np.sqrt(np.mean(np.sum((quiet_pos_index - np.mean(quiet_pos_mcp, axis=0)) ** 2, axis=1))))

        p2p_index = float(np.max(np.ptp(quiet_pos_index, axis=0)))
        p2p_mcp = float(np.max(np.ptp(quiet_pos_mcp, axis=0)))

        report["jitter_index_tip_rms"] = rms_index
        report["jitter_index_tip_p2p"] = p2p_index
        report["jitter_middle_mcp_rms"] = rms_mcp
        report["jitter_middle_mcp_p2p"] = p2p_mcp
        report["mcp_vs_index_jitter_reduction_pct"] = float(max(0.0, (rms_index - rms_mcp) / max(rms_index, 1e-6) * 100.0))

    # 2. Heisenberg Click Deflection Analysis
    # Look for transitions from not pinching to pinching
    pinch_edges = np.where(np.diff(pinch.astype(int)) == 1)[0] + 1
    deflections = []


    for commit_idx in pinch_edges:
        # Search backwards up to 15 frames (~250ms) for aperture onset (local maximum of aperture)
        start_search = max(0, commit_idx - 15)
        if commit_idx - start_search < 3:
            continue
        onset_idx = start_search + int(np.argmax(ap[start_search:commit_idx]))

        onset_pos = index_tip[onset_idx]
        commit_pos = index_tip[commit_idx]
        disp_index = float(np.hypot(commit_pos[0] - onset_pos[0], commit_pos[1] - onset_pos[1]))

        onset_mcp = middle_mcp[onset_idx]
        commit_mcp = middle_mcp[commit_idx]
        disp_mcp = float(np.hypot(commit_mcp[0] - onset_mcp[0], commit_mcp[1] - onset_mcp[1]))

        duration_ms = float((t[commit_idx] - t[onset_idx]) * 1000.0)
        deflections.append({
            "commit_frame": int(commit_idx),
            "onset_frame": int(onset_idx),
            "duration_ms": duration_ms,
            "index_deflection_norm": disp_index,
            "mcp_deflection_norm": disp_mcp,
            # Assuming typical 1920x1080 screen mapping:
            "index_deflection_screen_px_est": disp_index * 1440.0,
            "mcp_deflection_screen_px_est": disp_mcp * 1440.0,
        })

    report["pinch_events_count"] = len(deflections)
    report["deflections"] = deflections

    if deflections:
        avg_disp_index = np.mean([d["index_deflection_screen_px_est"] for d in deflections])
        avg_disp_mcp = np.mean([d["mcp_deflection_screen_px_est"] for d in deflections])
        report["mean_click_deflection_index_px"] = float(avg_disp_index)
        report["mean_click_deflection_mcp_px"] = float(avg_disp_mcp)
        report["mcp_deflection_improvement_pct"] = float(max(0.0, (avg_disp_index - avg_disp_mcp) / max(avg_disp_index, 1e-6) * 100.0))

    return report


def plot_kinematics(t, index_tip, middle_mcp, ap, pinch, diagnostics, out_png: Optional[str] = None):
    try:
        import matplotlib
        if not out_png or out_png:
            matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("Error: matplotlib is required for plotting. Install via: pip3 install matplotlib", file=sys.stderr)
        return

    fig, axes = plt.subplots(3, 1, figsize=(12, 10), sharex=True)

    t_rel = t - t[0]

    # Panel 1: X/Y Trajectory (Index Tip vs Middle MCP)
    ax1 = axes[0]
    ax1.plot(t_rel, index_tip[:, 0], label="Index Tip X (Raw)", color="#e74c3c", alpha=0.8, lw=1.5)
    ax1.plot(t_rel, middle_mcp[:, 0], label="Middle MCP X (Raw)", color="#2980b9", alpha=0.8, lw=1.5)
    ax1.set_ylabel("Normalized X")
    ax1.set_title("Kinematic Diagnostic Profile (Tracking Stability & Drift)")
    ax1.legend(loc="upper right")
    ax1.grid(True, alpha=0.3)

    # Panel 2: Speed / Velocity Profile
    ax2 = axes[1]
    dt = np.diff(t)
    v_index = np.hypot(np.diff(index_tip[:, 0]), np.diff(index_tip[:, 1])) / np.maximum(dt, 1e-4)
    v_mcp = np.hypot(np.diff(middle_mcp[:, 0]), np.diff(middle_mcp[:, 1])) / np.maximum(dt, 1e-4)
    ax2.plot(t_rel[1:], v_index, label="Index Tip Speed", color="#e74c3c", lw=1.2)
    ax2.plot(t_rel[1:], v_mcp, label="Middle MCP Speed", color="#2980b9", lw=1.2)
    ax2.set_ylabel("Speed (norm/s)")
    ax2.legend(loc="upper right")
    ax2.grid(True, alpha=0.3)

    # Panel 3: Aperture and Pinch Commitment Events
    ax3 = axes[2]
    ax3.plot(t_rel, ap, label="Aperture (Thumb-Index / Span)", color="#27ae60", lw=1.8)
    # Highlight pinch active regions
    pinch_idx = np.where(pinch)[0]
    if len(pinch_idx) > 0:
        ax3.scatter(t_rel[pinch_idx], ap[pinch_idx], color="#d35400", s=20, label="Pinch Active", zorder=5)

    for d in diagnostics.get("deflections", []):
        onset_t = t_rel[d["onset_frame"]]
        commit_t = t_rel[d["commit_frame"]]
        ax3.axvspan(onset_t, commit_t, color="#f39c12", alpha=0.25, label="Heisenberg Window" if d == diagnostics["deflections"][0] else "")

    ax3.set_ylabel("Aperture Ratio")
    ax3.set_xlabel("Time (seconds)")
    ax3.legend(loc="upper right")
    ax3.grid(True, alpha=0.3)

    plt.tight_layout()
    if out_png:
        plt.savefig(out_png, dpi=150)
        print(f"Kinematic diagnostic plot saved to: {out_png}")
    else:
        plt.show()


def main():
    parser = argparse.ArgumentParser(description="Kinematic Diagnostic Plotter & Benchmark Tool")
    parser.add_argument("input_jsonl", help="Path to input JSONL recording or fixture")
    parser.add_argument("--out-png", default=None, help="Save diagnostic plot image to PNG path")
    parser.add_argument("--show", action="store_true", help="Display interactive plot window")
    parser.add_argument("--json", action="store_true", help="Print diagnostics JSON to stdout")
    args = parser.parse_args()

    frames = parse_frames(args.input_jsonl)
    if not frames:
        print(f"Error: No valid hand frames found in {args.input_jsonl}", file=sys.stderr)
        sys.exit(1)

    t, index_tip, middle_mcp, ap, pinch = extract_signals(frames)
    diagnostics = compute_diagnostics(t, index_tip, middle_mcp, ap, pinch)

    if args.json:
        print(json.dumps(diagnostics, indent=2))
    else:
        print("=== KINEMATIC DIAGNOSTIC SUMMARY ===")
        print(f"Frames: {diagnostics.get('total_frames')} @ {diagnostics.get('effective_fps', 0):.1f} FPS (Duration: {diagnostics.get('total_duration_sec', 0):.2f}s)")
        if "jitter_index_tip_rms" in diagnostics:
            print(f"Rest Jitter (Index Tip RMS): {diagnostics['jitter_index_tip_rms']:.5f} (P2P: {diagnostics['jitter_index_tip_p2p']:.5f})")
            print(f"Rest Jitter (Middle MCP RMS): {diagnostics['jitter_middle_mcp_rms']:.5f} (P2P: {diagnostics['jitter_middle_mcp_p2p']:.5f})")
            print(f"Jitter Reduction by switching to MCP: {diagnostics['mcp_vs_index_jitter_reduction_pct']:.1f}%")
        if "mean_click_deflection_index_px" in diagnostics:
            print(f"Heisenberg Click Deflection (Index Tip): {diagnostics['mean_click_deflection_index_px']:.1f} px")
            print(f"Heisenberg Click Deflection (Middle MCP): {diagnostics['mean_click_deflection_mcp_px']:.1f} px")
            print(f"Deflection Reduction by switching to MCP: {diagnostics['mcp_deflection_improvement_pct']:.1f}%")

    if args.out_png or args.show:
        plot_kinematics(t, index_tip, middle_mcp, ap, pinch, diagnostics, args.out_png)


if __name__ == "__main__":
    main()
