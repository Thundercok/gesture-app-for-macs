#!/usr/bin/env python3
"""
tools/test_robustness_synthetic.py - Unit test for synthetic perturbation harness (Fast Mode)
"""

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from robustness_synthetic import (
    POSITIVE_FIXTURES,
    format_markdown_report,
    run_full_suite,
)


class TestSyntheticRobustnessHarness(unittest.TestCase):
    def test_fast_mode_execution_and_reporting(self):
        results = run_full_suite(fast_mode=True)
        self.assertGreater(len(results), 0, "Fast mode must evaluate conditions")

        for r in results:
            self.assertEqual(r["total"], 1, "Fast mode uses exactly 1 seed")
            self.assertEqual(r["errors"], 0, f"Error occurred during evaluation: {r}")
            self.assertEqual(r["hits"], 1, f"Expected 100% hit on fast mode baseline: {r}")

        report = format_markdown_report(results, "test_sha_12345", "python3 tools/robustness_synthetic.py --fast")
        expected_header = "# Synthetic perturbation of synthetic fixtures. Code-path robustness only. Not recognition accuracy on real hands."
        self.assertIn(expected_header, report, "Report must contain exact required header")
        self.assertIn("test_sha_12345", report)


if __name__ == "__main__":
    unittest.main()
