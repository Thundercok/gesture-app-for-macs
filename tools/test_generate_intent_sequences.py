#!/usr/bin/env python3
"""
Unit tests for tools/generate_intent_sequences.py and tools/train_intent.py.
"""

import os
import sys
import unittest
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from tools.generate_intent_sequences import (
    generate_intent_stream,
    export_intent_dataset,
    INTENT_CLASSES,
    WINDOW_SIZE,
)
from tools.train_intent import load_dataset


class TestIntentSequences(unittest.TestCase):
    def test_generate_intent_stream_structure(self):
        frames = generate_intent_stream(
            subject_id="test_sub",
            scale=1.0,
            tilt_rad=0.0,
            mirror=False,
            noise_sigma=0.001,
            seed=42,
            segments_per_class=2,
            frames_per_segment=10
        )
        self.assertGreater(len(frames), 50)
        # Check that all 5 classes are generated
        intents_present = set(f["intent"] for f in frames)
        for c in INTENT_CLASSES:
            self.assertIn(c, intents_present)

        # Check frame structure
        f0 = frames[0]
        self.assertEqual(len(f0["primaryPoints"]), 21)
        self.assertIn("x", f0["primaryPoints"][0])
        self.assertIn("y", f0["primaryPoints"][0])

    def test_export_intent_dataset_produces_valid_files(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            csv_path, split_path = export_intent_dataset(output_dir=tmp_dir)
            self.assertTrue(os.path.isfile(csv_path))
            self.assertTrue(os.path.isfile(split_path))

            X_train, y_train, X_test, y_test, train_sess, test_sess = load_dataset(csv_path, split_path)
            self.assertGreater(len(X_train), 100)
            self.assertGreater(len(X_test), 20)
            self.assertEqual(X_train.shape[1], WINDOW_SIZE * 56)
            self.assertEqual(len(train_sess), 5)
            self.assertEqual(len(test_sess), 1)


if __name__ == "__main__":
    unittest.main()
