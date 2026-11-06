#!/usr/bin/env python3
"""
tools/test_generate_synthetic_postures.py - Unit tests for synthetic posture generator.
"""

import os
import shutil
import tempfile
import unittest

from tools.generate_synthetic_postures import (
    generate_session_frames,
    generate_all_synthetic_sessions,
    make_none_landmarks,
)


class TestGenerateSyntheticPostures(unittest.TestCase):
    def test_session_generation_structure_and_classes(self):
        records = generate_session_frames(
            session_id="test_session.jsonl",
            subject_scale=1.0,
            tilt_range=(-10.0, 10.0),
            noise_sigma=0.002,
            mirror=False,
            samples_per_class=10,
            seed=42,
        )

        # 5 classes * 10 samples + 5 classes * 2 reset frames = 60 frames
        self.assertEqual(len(records), 60)

        ground_truths = set(r["groundTruth"] for r in records if r["handDetected"])
        self.assertIn("open_palm", ground_truths)
        self.assertIn("pinch", ground_truths)
        self.assertIn("two_fingers", ground_truths)
        self.assertIn("fist", ground_truths)
        self.assertIn("idle", ground_truths)

        for r in records:
            if r["handDetected"]:
                self.assertEqual(len(r["primaryPoints"]), 21)
                for pt in r["primaryPoints"]:
                    self.assertGreaterEqual(pt["x"], 0.0)
                    self.assertLessEqual(pt["x"], 1.0)
                    self.assertGreaterEqual(pt["y"], 0.0)
                    self.assertLessEqual(pt["y"], 1.0)

    def test_make_none_landmarks_variants(self):
        for v in [0, 1, 2]:
            pts = make_none_landmarks(0.5, 0.5, scale=1.0, variant=v)
            self.assertEqual(len(pts), 21)

    def test_batch_generation_creates_all_sessions(self):
        temp_dir = tempfile.mkdtemp()
        try:
            files = generate_all_synthetic_sessions(output_dir=temp_dir, samples_per_class=5)
            self.assertEqual(len(files), 6)
            for f in files:
                self.assertTrue(os.path.isfile(f))
                self.assertGreater(os.path.getsize(f), 0)
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
