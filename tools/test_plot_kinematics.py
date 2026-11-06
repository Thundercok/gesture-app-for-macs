#!/usr/bin/env python3
"""
Unit tests for tools/plot_kinematics.py
"""

import json
import os
import subprocess
import sys
import unittest
import numpy as np

from tools.plot_kinematics import parse_frames, extract_signals, compute_diagnostics


class TestPlotKinematics(unittest.TestCase):
    def test_parse_frames_skips_incident_header(self):
        fixture_path = "tools/fixtures/synthetic_pinch.jsonl"
        frames = parse_frames(fixture_path)
        self.assertGreater(len(frames), 0)
        for f in frames:
            self.assertIn("primaryPoints", f)

    def test_extract_signals(self):
        fixture_path = "tools/fixtures/synthetic_pinch.jsonl"
        frames = parse_frames(fixture_path)
        t, index_tip, middle_mcp, ap, pinch = extract_signals(frames)
        self.assertEqual(len(t), len(index_tip))
        self.assertEqual(len(t), len(middle_mcp))
        self.assertEqual(len(t), len(ap))
        self.assertEqual(len(t), len(pinch))
        self.assertTrue(np.all(ap >= 0.0))

    def test_compute_diagnostics_insufficient_frames(self):
        t = np.array([0.0, 0.016])
        res = compute_diagnostics(t, np.zeros((2, 2)), np.zeros((2, 2)), np.zeros(2), np.zeros(2))
        self.assertIn("error", res)

    def test_compute_diagnostics_heisenberg_deflection(self):
        # 20 frames at 60 FPS
        t = np.linspace(0.0, 0.33, 20)
        # Index tip drifts by 0.05 normalized units during pinch onset (frames 5 to 10)
        index_tip = np.zeros((20, 2))
        index_tip[10:, 0] = 0.05
        # Middle MCP remains perfectly stationary
        middle_mcp = np.zeros((20, 2))
        # Aperture closes from 0.8 to 0.1 at frame 10
        ap = np.ones(20) * 0.8
        ap[5:10] = np.linspace(0.8, 0.1, 5)
        ap[10:] = 0.08
        # Pinch committed at frame 10
        pinch = np.zeros(20, dtype=bool)
        pinch[10:] = True

        diag = compute_diagnostics(t, index_tip, middle_mcp, ap, pinch)
        self.assertEqual(diag["pinch_events_count"], 1)
        self.assertGreater(diag["mean_click_deflection_index_px"], 0.0)
        self.assertEqual(diag["mean_click_deflection_mcp_px"], 0.0)
        self.assertAlmostEqual(diag["mcp_deflection_improvement_pct"], 100.0, places=1)

    def test_cli_json_mode(self):
        cmd = [sys.executable, "tools/plot_kinematics.py", "tools/fixtures/synthetic_pinch.jsonl", "--json"]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout)
        self.assertIn("total_frames", data)
        self.assertEqual(data["pinch_events_count"], 1)


if __name__ == "__main__":
    unittest.main()
