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


def frames(label, t0, t1, fired_at=None, fired="swipe", predicted="idle", fps=30):
    out = []
    n = int((t1 - t0) * fps)
    for i in range(n):
        t = t0 + i / fps
        f = ""
        if fired_at is not None and abs(t - fired_at) < 0.5 / fps:
            f = fired
        out.append({"timestamp": t, "groundTruth": label, "predictedIntent": predicted, "firedIntent": f})
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


if __name__ == "__main__":
    unittest.main()
