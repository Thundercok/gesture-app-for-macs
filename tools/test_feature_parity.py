#!/usr/bin/env python3
"""
tools/test_feature_parity.py - Verifies Swift <-> Python 56D feature extraction parity.
Runs both extractors on every .jsonl fixture in tools/fixtures/ and asserts
per-frame numerical parity with abs_tol=1e-4.
"""

import os
import sys
import json
import csv
import glob
import subprocess
import unittest
from typing import List, Tuple

from tools.export_features import normalize_landmarks


class TestFeatureParity(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        # Locate project root and binary
        cls.project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        cls.app_path = os.path.join(cls.project_root, "GestureFlowApp")
        cls.fixtures_dir = os.path.join(cls.project_root, "tools", "fixtures")
        cls.fixture_files = sorted(glob.glob(os.path.join(cls.fixtures_dir, "*.jsonl")))
        assert len(cls.fixture_files) > 0, f"No fixture files found in {cls.fixtures_dir}"

    def run_swift_dump(self, fixture_path: str, out_csv: str, use_raw: bool = True) -> int:
        binary_candidates = [
            os.path.join(self.project_root, "GestureFlowApp/.build/arm64-apple-macosx/debug/GestureFlow"),
            os.path.join(self.project_root, "GestureFlowApp/.build/debug/GestureFlow"),
        ]
        binary = next((b for b in binary_candidates if os.path.isfile(b) and os.access(b, os.X_OK)), None)
        if binary:
            cmd = [binary, "--dump-features", fixture_path, "--out", out_csv]
        else:
            cmd = [
                "swift", "run", "--package-path", self.app_path, "GestureFlow",
                "--dump-features", fixture_path,
                "--out", out_csv
            ]
        if use_raw:
            cmd.append("--raw")
        res = subprocess.run(cmd, cwd=self.project_root, capture_output=True, text=True)
        return res.returncode

    def test_all_fixtures_normalization_parity(self):
        """Tests that Swift and Python 56D normalization match within 1e-4 tolerance on all fixtures."""
        tmp_csv = "/tmp/test_parity_dump.csv"

        for fixture_path in self.fixture_files:
            fname = os.path.basename(fixture_path)
            ret = self.run_swift_dump(fixture_path, tmp_csv, use_raw=True)
            self.assertEqual(ret, 0, f"Swift --dump-features failed for {fname}")

            with open(tmp_csv, "r", encoding="utf-8") as f:
                reader = csv.reader(f)
                header = next(reader)
                swift_rows = list(reader)

            with open(fixture_path, "r", encoding="utf-8") as f:
                py_frames = []
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('{"incident":'):
                        continue
                    rec = json.loads(line)
                    if rec.get("handDetected") and len(rec.get("primaryPoints", [])) == 21:
                        py_frames.append(rec)

            self.assertEqual(
                len(swift_rows), len(py_frames),
                f"Frame count mismatch for {fname}: Swift={len(swift_rows)}, Py={len(py_frames)}"
            )

            max_diff = 0.0
            first_fail = None

            for row_idx, (s_row, p_frame) in enumerate(zip(swift_rows, py_frames)):
                frame_idx = int(s_row[0])
                s_feats = [float(x) for x in s_row[1:]]
                raw_points = [(p["x"], p["y"]) for p in p_frame["primaryPoints"]]
                p_feats, _ = normalize_landmarks(raw_points)

                self.assertEqual(len(s_feats), 56, f"Expected 56 features in Swift row {row_idx}")
                self.assertEqual(len(p_feats), 56, f"Expected 56 features in Python row {row_idx}")

                for feat_idx, (sf, pf) in enumerate(zip(s_feats, p_feats)):
                    diff = abs(sf - pf)
                    if diff > max_diff:
                        max_diff = diff
                    if diff > 1e-4 and first_fail is None:
                        first_fail = (frame_idx, feat_idx, sf, pf, diff)

            if first_fail is not None:
                frame_idx, feat_idx, sf, pf, diff = first_fail
                col_name = header[feat_idx + 1] if feat_idx + 1 < len(header) else f"feat_{feat_idx}"
                self.fail(
                    f"Parity failure in {fname} at frame {frame_idx}, feature {feat_idx} ({col_name}): "
                    f"Swift={sf}, Python={pf}, abs_diff={diff:.6f} > 1e-4"
                )

            print(f"[FeatureParity] {fname}: PASS (max diff = {max_diff:.2e})")

        if os.path.exists(tmp_csv):
            try:
                os.remove(tmp_csv)
            except OSError:
                pass


if __name__ == "__main__":
    unittest.main()
