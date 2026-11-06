#!/usr/bin/env python3
"""
Unit tests for ISO 9241-9 Fitts' Law scientific benchmark harness (tools/bench_fitts.py).
"""

import sys
import os
import math
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from tools.bench_fitts import (
    FittsTarget,
    FittsKinematicSimulator,
    FittsBenchmarkRunner,
    run_benchmark,
    format_markdown_table
)


class TestFittsBenchmark(unittest.TestCase):
    def setUp(self):
        self.runner = FittsBenchmarkRunner(circle_radius=280.0, center=(500.0, 500.0))

    def test_iso_targets_generation(self):
        targets = self.runner.generate_iso_targets(n_targets=16, target_width=48.0)
        self.assertEqual(len(targets), 16)

        # Check each target is on the circle radius 280.0 from center (500, 500)
        for t in targets:
            dist = math.hypot(t.center_x - 500.0, t.center_y - 500.0)
            self.assertAlmostEqual(dist, 280.0, places=2)
            self.assertEqual(t.width, 48.0)
            self.assertEqual(t.radius, 24.0)

    def test_fitts_kinematic_simulation(self):
        sim = FittsKinematicSimulator()
        start = (200.0, 200.0)
        dest = (600.0, 600.0)
        raw_frames = sim.generate_movement(start=start, target=dest, target_width=48.0, seed=123)

        self.assertGreater(len(raw_frames), 15)
        # Check start point proximity
        self.assertAlmostEqual(raw_frames[0]["x"], 200.0, delta=10.0)
        self.assertAlmostEqual(raw_frames[0]["y"], 200.0, delta=10.0)

        # Check pinch aperture drops at the end
        self.assertGreater(raw_frames[0]["aperture"], 0.65)
        self.assertLess(raw_frames[-1]["aperture"], 0.25)
        self.assertTrue(raw_frames[-1]["is_click_frame"])

    def test_pre_click_lock_eliminates_deflection(self):
        t1 = FittsTarget(0, 200.0, 500.0, 48.0, 24.0)
        t2 = FittsTarget(1, 800.0, 500.0, 48.0, 24.0)

        m_raw = self.runner.run_trial("raw", t1, t2, seed=42)
        m_locked = self.runner.run_trial("pre_click_lock", t1, t2, seed=42)

        # Raw pointer should have noticeable mechanical click deflection
        self.assertGreater(m_raw.click_deflection, 3.0)
        # Pre-click locked pointer must freeze coordinate, achieving exactly 0.00 deflection
        self.assertAlmostEqual(m_locked.click_deflection, 0.0, places=3)

    def test_magnetic_snapping_pull_and_breakaway(self):
        target = FittsTarget(0, 500.0, 500.0, 48.0, 24.0)

        # At low speed (100 px/s), cursor at (490, 500) should be pulled toward 500
        snapped_x, snapped_y = FittsBenchmarkRunner._apply_magnetic_snap(490.0, 500.0, target, speed_px_s=100.0)
        self.assertGreater(snapped_x, 490.0)
        self.assertEqual(snapped_y, 500.0)

        # At breakaway speed (700 px/s >= 650), magnetic pull should be 0.0
        escaped_x, escaped_y = FittsBenchmarkRunner._apply_magnetic_snap(490.0, 500.0, target, speed_px_s=700.0)
        self.assertEqual(escaped_x, 490.0)
        self.assertEqual(escaped_y, 500.0)

    def test_run_benchmark_ablation_suite(self):
        results = run_benchmark(n_targets=8, target_widths=[48.0], seed=99)
        summary = results["summary"]

        expected_conditions = [
            "raw",
            "one_euro",
            "viscous_damping",
            "pre_click_lock",
            "magnetic_snapping",
            "full_gestureflow"
        ]

        for cond in expected_conditions:
            self.assertIn(cond, summary)
            s = summary[cond]
            self.assertGreater(s["mean_throughput_bps"], 2.0)
            self.assertGreater(s["target_accuracy_pct"], 60.0)
            self.assertGreater(s["mean_integrated_jerk"], 0.0)

        # Full engine should have higher accuracy and 0 overshoots
        self.assertEqual(summary["full_gestureflow"]["mean_overshoots"], 0.0)
        self.assertGreaterEqual(summary["full_gestureflow"]["target_accuracy_pct"], summary["raw"]["target_accuracy_pct"])

        # Markdown formatting check
        md = format_markdown_table(results)
        self.assertIn("ISO 9241-9 Fitts' Law Benchmark Report", md)
        self.assertIn("Full GestureFlow Engine", md)


if __name__ == "__main__":
    unittest.main()
