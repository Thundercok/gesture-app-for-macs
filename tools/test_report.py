#!/usr/bin/env python3
"""
tools/test_report.py - Unit and Integration Tests for One-Command Evaluation Report Generator
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = TOOLS_DIR.parent
FIXTURES_DIR = TOOLS_DIR / "fixtures"
REPORT_SCRIPT = TOOLS_DIR / "report.py"


class TestReportGenerator(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.output_report = os.path.join(self.temp_dir, "REPORT_TEST.md")

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_report_generation_on_fixtures_with_synthetic_stamp(self):
        """Asserts that report.py runs on fixtures, generates all required sections, and stamps SYNTHETIC."""
        cmd = [
            sys.executable,
            str(REPORT_SCRIPT),
            "--recordings", str(FIXTURES_DIR),
            "--out", self.output_report,
            "--allow-synthetic"
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"report.py failed: {res.stderr}\n{res.stdout}")
        self.assertTrue(os.path.isfile(self.output_report), "Report output file was not created.")

        with open(self.output_report, "r", encoding="utf-8") as f:
            content = f.read()

        # 1. Assert mandatory synthetic warning banner
        self.assertIn("# SYNTHETIC INPUT — NOT REAL DATA", content)
        self.assertIn("SYNTHETIC INPUT — NOT REAL DATA", content)

        # 2. Assert all required report sections
        self.assertIn("## 1. Input Datasets & Incident Logs", content)
        self.assertIn("## 2. Replay & Event-Level Evaluation", content)
        self.assertIn("## 3. Incident Evaluation & Flight-Recorder Analysis", content)
        self.assertIn("## 4. Posture Classifier Shadow Evaluation", content)
        self.assertIn("## 5. Robustness Condition Matrix", content)
        self.assertIn("## 6. Verification & Reproduction Commands", content)

        # 3. Assert Sweep Guard triggered on small fixtures (< 20 windows)
        self.assertIn("Sweep Guard", content)

        # 4. Assert specific fixture results are rendered
        self.assertIn("synthetic_swipe_left.jsonl", content)
        self.assertIn("synthetic_pinch.jsonl", content)
        self.assertIn("Directional Breakdown", content)

    def test_robustness_condition_table_population(self):
        """Asserts that files named robustness_<cond_id>.jsonl populate the robustness table copy."""
        # Create a single test condition fixture
        cond_dir = os.path.join(self.temp_dir, "recs")
        os.makedirs(cond_dir, exist_ok=True)
        sample_fixture = FIXTURES_DIR / "synthetic_swipe_left.jsonl"
        cond_fixture = os.path.join(cond_dir, "robustness_light_normal.jsonl")
        shutil.copyfile(sample_fixture, cond_fixture)

        cmd = [
            sys.executable,
            str(REPORT_SCRIPT),
            "--recordings", cond_dir,
            "--out", self.output_report,
            "--allow-synthetic"
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"report.py failed: {res.stderr}")

        with open(self.output_report, "r", encoding="utf-8") as f:
            content = f.read()

        # Check that light_normal is marked MEASURED while others remain NEEDS-USER
        self.assertIn("| `light_normal` | Lighting | Indoor normal desk lighting (~300–500 lux) | 60 | `robustness_light_normal.jsonl` | 100.0% |", content)
        self.assertIn("| `light_low` | Lighting | Dim room / evening monitor-glow only (<50 lux) | 30 / 60 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |", content)


if __name__ == "__main__":
    unittest.main()
