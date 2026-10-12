#!/usr/bin/env python3
"""Unit tests for the event-level scorer in eval_gestures.py.

These verify scoring LOGIC on hand-built frame streams (hit / miss / wrong-class /
double-fire / idle false trigger / ignore zones). They are not accuracy measurements.
Run: python3 -m unittest tools/test_eval_gestures.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eval_gestures as ev  # noqa: E402


def frames(label, t0, t1, fired_at=None, fired="swipe", fired_action="", predicted="idle", fps=30):
    out = []
    n = int((t1 - t0) * fps)
    for i in range(n):
        t = t0 + i / fps
        f = ""
        fa = ""
        if fired_at is not None and abs(t - fired_at) < 0.5 / fps:
            f = fired
            fa = fired_action
        out.append({"timestamp": t, "groundTruth": label, "predictedIntent": predicted, "firedIntent": f, "firedAction": fa})
    return out


class EventScorer(unittest.TestCase):
    def test_hit_with_latency(self):
        recs = frames("ignore", 0, 1) + frames("swipe_left", 1, 2.6, fired_at=1.4) + frames("ignore", 2.6, 3.6)
        r = ev.evaluate_events(recs)["per_class"]["swipe"]
        self.assertEqual((r["windows"], r["hit"], r["miss"], r["wrong"]), (1, 1, 0, 0))
        self.assertAlmostEqual(r["latencies"][0], 0.4, delta=0.04)

    def test_miss(self):
        recs = frames("swipe_left", 0, 1.6)
        r = ev.evaluate_events(recs)["per_class"]["swipe"]
        self.assertEqual((r["hit"], r["miss"]), (0, 1))

    def test_wrong_class_is_clash(self):
        # user swipes, app fires air_scroll instead
        recs = frames("swipe_left", 0, 1.6, fired_at=0.5, fired="air_scroll")
        res = ev.evaluate_events(recs)
        self.assertEqual(res["per_class"]["swipe"]["wrong"], 1)
        self.assertEqual(res["confusion"]["swipe"].get("air_scroll"), 1)

    def test_correct_plus_extra_wrong_counts_clash(self):
        recs = frames("swipe_left", 0, 1.6)
        recs[10]["firedIntent"] = "swipe"
        recs[20]["firedIntent"] = "pinch_dock"
        res = ev.evaluate_events(recs)
        self.assertEqual(res["per_class"]["swipe"]["hit"], 1)
        self.assertEqual(res["confusion"]["swipe"].get("pinch_dock"), 1)

    def test_double_fire(self):
        recs = frames("swipe_right", 0, 1.6)
        recs[10]["firedIntent"] = "swipe"
        recs[25]["firedIntent"] = "swipe"
        self.assertEqual(ev.evaluate_events(recs)["per_class"]["swipe"]["double_fire"], 1)

    def test_idle_false_trigger_rate(self):
        recs = frames("idle", 0, 60, fired_at=10, fired="swipe")
        res = ev.evaluate_events(recs)
        self.assertEqual(res["idle_false_triggers"], {"swipe": 1})
        self.assertAlmostEqual(res["idle_false_triggers_per_min"], 1.0, delta=0.05)

    def test_ignore_zone_not_scored(self):
        recs = frames("ignore", 0, 5, fired_at=2, fired="swipe") + frames("idle", 5, 65)
        res = ev.evaluate_events(recs)
        self.assertEqual(sum(res["idle_false_triggers"].values()), 0)

    def test_pinch_state_rising_edge_counts_once(self):
        recs = frames("pinch_dock", 0, 3.2, predicted="pinch_dock")
        r = ev.evaluate_events(recs)["per_class"]["pinch_dock"]
        self.assertEqual((r["hit"], r["double_fire"]), (1, 0))

    def test_direction_mismatch_is_wrong_not_hit(self):
        # user swipes physical left, app fires swipe_right
        recs = frames("swipe_left", 0, 1.6, fired_at=0.5, fired="swipe", fired_action="swipe_right")
        res = ev.evaluate_events(recs)
        self.assertEqual(res["per_class"]["swipe"]["hit"], 0)
        self.assertEqual(res["per_class"]["swipe"]["wrong"], 1)
        self.assertEqual(res["confusion"]["swipe"].get("swipe_right"), 1)
        self.assertEqual(res["direction_confusion"]["swipe_left"].get("swipe_right"), 1)

    def test_direction_match_with_fired_action(self):
        # user swipes physical left, app fires swipe_left
        recs = frames("swipe_left", 0, 1.6, fired_at=0.5, fired="swipe", fired_action="swipe_left")
        res = ev.evaluate_events(recs)
        self.assertEqual(res["per_class"]["swipe"]["hit"], 1)
        self.assertEqual(res["per_class"]["swipe"]["wrong"], 0)
        self.assertEqual(res["direction_confusion"]["swipe_left"].get("swipe_left"), 1)

    def test_vertical_swipe_direction_confusion(self):
        # user swipes down (Desktop), app fires swipe_up (Mission Control)
        recs = frames("swipe_down", 0, 1.6, fired_at=0.5, fired="swipe", fired_action="swipe_up")
        res = ev.evaluate_events(recs)
        self.assertEqual(res["per_class"]["swipe"]["hit"], 0)
        self.assertEqual(res["per_class"]["swipe"]["wrong"], 1)
        self.assertEqual(res["direction_confusion"]["swipe_down"].get("swipe_up"), 1)

    def test_scroll_direction_matching_and_mismatch(self):
        # hit scroll_down
        recs_hit = frames("scroll_down", 0, 1.6, fired_at=0.5, fired="air_scroll", fired_action="scroll_down")
        res_hit = ev.evaluate_events(recs_hit)
        self.assertEqual(res_hit["per_class"]["air_scroll"]["hit"], 1)
        self.assertEqual(res_hit["direction_confusion"]["scroll_down"].get("scroll_down"), 1)

        # mismatch: user did scroll_down, app fired scroll_up
        recs_mis = frames("scroll_down", 0, 1.6, fired_at=0.5, fired="air_scroll", fired_action="scroll_up")
        res_mis = ev.evaluate_events(recs_mis)
        self.assertEqual(res_mis["per_class"]["air_scroll"]["hit"], 0)
        self.assertEqual(res_mis["per_class"]["air_scroll"]["wrong"], 1)
        self.assertEqual(res_mis["direction_confusion"]["scroll_down"].get("scroll_up"), 1)

    def test_legacy_macro_fallback_when_action_unspecified(self):
        # Old recording has fired="swipe", no firedAction. Still counted as hit for swipe_left window.
        recs = frames("swipe_left", 0, 1.6, fired_at=0.5, fired="swipe")
        res = ev.evaluate_events(recs)
        self.assertEqual(res["per_class"]["swipe"]["hit"], 1)
        self.assertEqual(res["per_class"]["swipe"]["wrong"], 0)


class IncidentEvaluationTests(unittest.TestCase):
    def test_wilson_interval_zero(self):
        self.assertIsNone(ev.wilson_score_interval(0, 0))
        self.assertIsNone(ev.wilson_score_interval(5, 0))

    def test_wilson_interval_arithmetic(self):
        interval = ev.wilson_score_interval(10, 100)
        self.assertIsNotNone(interval)
        lo, hi = interval
        self.assertTrue(0.04 < lo < 0.10)
        self.assertTrue(0.10 < hi < 0.18)

    def test_load_dataset_skips_header(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w+", suffix=".jsonl", delete=False) as f:
            f.write('{"incident":"misfire","createdAt":"2026-10-12T14:00:00Z","appVersion":"dev","note":""}\n')
            f.write('{"timestamp":1.0,"groundTruth":"idle","predictedIntent":"idle"}\n')
            f_path = f.name
        try:
            loaded = ev.load_dataset(f_path)
            self.assertEqual(len(loaded), 1)
            self.assertEqual(loaded[0]["groundTruth"], "idle")
        finally:
            os.remove(f_path)

    def test_evaluate_incidents_misfire_rate(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            # 3 fires
            for i in range(3):
                with open(os.path.join(tmpdir, f"file_{i}_fire.jsonl"), "w") as f:
                    f.write('{"incident":"fire","createdAt":"2026-10-12T14:00:00Z","appVersion":"dev","note":""}\n')
                    f.write('{"timestamp":1.0,"groundTruth":"unlabeled","predictedIntent":"swipe","firedIntent":"swipe"}\n')
            # 1 misfire
            with open(os.path.join(tmpdir, "file_3_misfire.jsonl"), "w") as f:
                f.write('{"incident":"misfire","createdAt":"2026-10-12T14:05:00Z","appVersion":"dev","note":""}\n')
                f.write('{"timestamp":2.0,"groundTruth":"misfire","predictedIntent":"swipe","firedIntent":"swipe"}\n')

            res = ev.evaluate_incidents(tmpdir)
            self.assertEqual(res["counts"]["fire"], 3)
            self.assertEqual(res["counts"]["misfire"], 1)
            self.assertAlmostEqual(res["misfire_rate"], 0.25)
            self.assertIsNotNone(res["wilson_interval"])
            self.assertEqual(res["per_intent_misfires"].get("swipe"), 1)


if __name__ == "__main__":
    unittest.main()
