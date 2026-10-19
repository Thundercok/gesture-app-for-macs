#!/usr/bin/env python3
"""
tools/test_export_features.py - Unit tests for feature extraction and normalization invariance.
"""

import math
import unittest
from typing import List, Tuple
from tools.export_features import normalize_landmarks, LABEL_TO_POSTURE, POSTURE_CLASSES


class TestFeatureNormalization(unittest.TestCase):
    def setUp(self):
        # Canonical test right hand (21 landmarks)
        # Wrist at (0.5, 0.8), fingers extended upwards
        self.base_hand: List[Tuple[float, float]] = [
            (0.50, 0.80), # 0: Wrist
            (0.44, 0.74), # 1: Thumb CMC
            (0.40, 0.68), # 2: Thumb MCP
            (0.38, 0.62), # 3: Thumb IP
            (0.36, 0.58), # 4: Thumb Tip
            (0.46, 0.66), # 5: Index MCP
            (0.45, 0.56), # 6: Index PIP
            (0.45, 0.48), # 7: Index DIP
            (0.45, 0.40), # 8: Index Tip
            (0.50, 0.64), # 9: Middle MCP
            (0.50, 0.54), # 10: Middle PIP
            (0.50, 0.46), # 11: Middle DIP
            (0.50, 0.38), # 12: Middle Tip
            (0.54, 0.66), # 13: Ring MCP
            (0.55, 0.56), # 14: Ring PIP
            (0.55, 0.48), # 15: Ring DIP
            (0.55, 0.42), # 16: Ring Tip
            (0.58, 0.69), # 17: Pinky MCP
            (0.59, 0.61), # 18: Pinky PIP
            (0.60, 0.55), # 19: Pinky DIP
            (0.60, 0.50), # 20: Pinky Tip
        ]

    def test_translation_invariance(self):
        base_feat, _ = normalize_landmarks(self.base_hand)

        # Shift by (+0.35, -0.42)
        shifted_hand = [(x + 0.35, y - 0.42) for (x, y) in self.base_hand]
        shifted_feat, _ = normalize_landmarks(shifted_hand)

        for b, s in zip(base_feat, shifted_feat):
            self.assertAlmostEqual(b, s, places=4, msg="Translation altered normalized feature")

    def test_scale_invariance(self):
        base_feat, _ = normalize_landmarks(self.base_hand)

        # Scale by 2.5x around origin
        scaled_hand = [(x * 2.5, y * 2.5) for (x, y) in self.base_hand]
        scaled_feat, _ = normalize_landmarks(scaled_hand)

        for b, s in zip(base_feat, scaled_feat):
            self.assertAlmostEqual(b, s, places=4, msg="Scale factor altered normalized feature")

    def test_rotation_invariance(self):
        base_feat, _ = normalize_landmarks(self.base_hand)

        # Rotate entire hand by 45 degrees around wrist
        angle = math.pi / 4.0
        cos_a = math.cos(angle)
        sin_a = math.sin(angle)
        w_x, w_y = self.base_hand[0]

        rotated_hand: List[Tuple[float, float]] = []
        for x, y in self.base_hand:
            dx = x - w_x
            dy = y - w_y
            rx = w_x + (dx * cos_a - dy * sin_a)
            ry = w_y + (dx * sin_a + dy * cos_a)
            rotated_hand.append((rx, ry))

        rotated_feat, _ = normalize_landmarks(rotated_hand)

        for b, r in zip(base_feat, rotated_feat):
            self.assertAlmostEqual(b, r, places=4, msg="In-plane rotation altered normalized feature")

    def test_mirroring_invariance(self):
        base_feat, base_meta = normalize_landmarks(self.base_hand)
        self.assertFalse(base_meta["is_mirrored"])

        # Mirror horizontally across wrist X to produce a left hand
        w_x = self.base_hand[0][0]
        mirrored_hand = [(2 * w_x - x, y) for (x, y) in self.base_hand]
        mirrored_feat, mirrored_meta = normalize_landmarks(mirrored_hand)

        self.assertTrue(mirrored_meta["is_mirrored"])

        # Canonical right-hand features should match mirrored hand
        for b, m in zip(base_feat, mirrored_feat):
            self.assertAlmostEqual(b, m, places=4, msg="Mirroring produced asymmetric canonical feature")

    def test_invalid_landmarks_count_raises(self):
        short_hand = self.base_hand[:15]
        with self.assertRaises(ValueError):
            normalize_landmarks(short_hand)

    def test_label_mapping_coverage(self):
        self.assertEqual(LABEL_TO_POSTURE["idle"], "none")
        self.assertEqual(LABEL_TO_POSTURE["swipe_left"], "open_palm")
        self.assertEqual(LABEL_TO_POSTURE["pinch_dock"], "pinch")
        self.assertEqual(LABEL_TO_POSTURE["scroll_up"], "two_fingers")
        for cls_name in LABEL_TO_POSTURE.values():
            self.assertIn(cls_name, POSTURE_CLASSES)

    def test_export_features_with_swift_pipeline(self):
        """Tests that export_features can delegate to Swift binary pipeline for filtered features."""
        import os
        import tempfile
        import shutil
        from tools.export_features import export_features, find_swift_binary

        swift_bin = find_swift_binary()
        if not swift_bin:
            self.skipTest("GestureFlow binary not compiled")

        temp_dir = tempfile.mkdtemp()
        try:
            out_csv = os.path.join(temp_dir, "features.csv")
            out_split = os.path.join(temp_dir, "split.json")
            fixture = os.path.join(os.path.dirname(__file__), "fixtures", "synthetic_swipe_left.jsonl")

            res = export_features(
                input_paths=[fixture],
                output_csv=out_csv,
                split_json=out_split,
                use_swift_pipeline=True,
                swift_binary=swift_bin
            )

            self.assertTrue(res["used_swift_pipeline"])
            self.assertTrue(os.path.isfile(out_csv))
            self.assertTrue(os.path.isfile(out_split))
            self.assertGreater(res["total_samples"], 0)
            self.assertGreater(res["class_counts"]["open_palm"], 0)
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
