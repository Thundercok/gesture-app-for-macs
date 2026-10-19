#!/usr/bin/env python3
"""
tools/test_replay.py - Regression and Determinism Tests for Headless Replay Harness

Verifies:
1. Binary executes headlessly with code 0 on synthetic fixtures.
2. Replay produces exact expected action sequences (e.g. ["swipe_left"], ["pinch_dock"]).
3. Output is 100% byte-for-byte deterministic against golden references.
"""

import json
import os
import subprocess
import tempfile
import unittest

BINARY_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "GestureFlowApp/.build/arm64-apple-macosx/debug/GestureFlow"
)
FIXTURES_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "tools/fixtures"
)
GOLDEN_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "tools/golden"
)


class TestReplayHarness(unittest.TestCase):
    def setUp(self):
        self.assertTrue(
            os.path.isfile(BINARY_PATH),
            f"Binary not found at {BINARY_PATH}. Run 'swift build' first."
        )

    def _run_replay(self, fixture_name, tuning="balanced", extra_args=None):
        fixture_path = os.path.join(FIXTURES_DIR, fixture_name)
        self.assertTrue(os.path.isfile(fixture_path), f"Fixture not found: {fixture_path}")

        out_fd, out_path = tempfile.mkstemp(suffix=".jsonl")
        os.close(out_fd)

        cmd = [
            BINARY_PATH,
            "--replay", fixture_path,
            "--tuning", tuning,
            "--out", out_path
        ]
        if extra_args:
            cmd.extend(extra_args)

        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(result.returncode, 0, f"Replay failed: {result.stderr}\nStdout: {result.stdout}")

        records = []
        with open(out_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    records.append(json.loads(line))

        return out_path, records, result.stdout

    def test_all_fixtures_fire_expected_actions_and_match_goldens(self):
        expected_path = os.path.join(FIXTURES_DIR, "EXPECTED.json")
        self.assertTrue(os.path.isfile(expected_path), f"EXPECTED.json not found at {expected_path}")
        with open(expected_path, "r", encoding="utf-8") as f:
            expected_map = json.load(f)

        for fixture_name, expected_actions in expected_map.items():
            with self.subTest(fixture=fixture_name):
                out_path, records, stdout = self._run_replay(fixture_name, tuning="balanced")
                try:
                    fired_actions = [r["firedAction"] for r in records if r.get("firedAction")]
                    self.assertEqual(
                        fired_actions, expected_actions,
                        f"Fixture {fixture_name}: expected {expected_actions}, got {fired_actions}"
                    )

                    base = os.path.splitext(fixture_name)[0]
                    golden_path = os.path.join(GOLDEN_DIR, f"{base}.golden.jsonl")
                    self.assertTrue(os.path.isfile(golden_path), f"Golden file not found: {golden_path}")
                    with open(out_path, "rb") as f_out, open(golden_path, "rb") as f_gold:
                        self.assertEqual(
                            f_out.read(), f_gold.read(),
                            f"Fixture {fixture_name}: Replay output does not match golden byte-for-byte"
                        )
                finally:
                    if os.path.exists(out_path):
                        os.remove(out_path)

    def test_determinism_across_multiple_runs(self):
        expected_path = os.path.join(FIXTURES_DIR, "EXPECTED.json")
        with open(expected_path, "r", encoding="utf-8") as f:
            fixtures = list(json.load(f).keys())

        for fixture_name in fixtures:
            with self.subTest(fixture=fixture_name):
                out1, _, _ = self._run_replay(fixture_name, tuning="balanced")
                out2, _, _ = self._run_replay(fixture_name, tuning="balanced")
                try:
                    with open(out1, "rb") as f1, open(out2, "rb") as f2:
                        self.assertEqual(f1.read(), f2.read(), f"Repeated replays of {fixture_name} must produce identical bytes")
                finally:
                    for p in (out1, out2):
                        if os.path.exists(p):
                            os.remove(p)

    def test_sweep_guard_on_small_dataset(self):
        sweep_script = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "tools/sweep.py"
        )
        fixture_path = os.path.join(FIXTURES_DIR, "synthetic_swipe_left.jsonl")
        out_csv = tempfile.mktemp(suffix=".csv")
        try:
            cmd = ["python3", sweep_script, "--data", fixture_path, "--output-csv", out_csv]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            self.assertNotEqual(res.returncode, 0, "Sweep should refuse to run on small datasets (< 20 windows)")
            self.assertIn("minimum 20 required", res.stderr)
        finally:
            if os.path.exists(out_csv):
                os.remove(out_csv)


if __name__ == "__main__":
    unittest.main()
