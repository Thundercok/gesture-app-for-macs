# GestureFlow Robustness Condition Matrix (WP9.4)

> **Rule R3 (Academic Integrity)**: All result cells below are initialized to `not measured`. Never fill cells from synthetic fixtures, unit tests, or estimation. Populate a row only after recording a real `--guided` session under that physical condition and running the evaluation command shown below.

## 1. Recording & Evaluation Protocol

For each condition `<cond_id>` in the table below:

```bash
# 1. Record a 7-minute voice-guided session under the specified physical condition
cd /Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp
.build/arm64-apple-macosx/debug/GestureFlow --guided --record ~/Library/Application\ Support/GestureFlow/recordings/robustness_<cond_id>.jsonl

# 2. Replay deterministically through the engine (optional if evaluating raw recording directly, required after tuning changes)
.build/arm64-apple-macosx/debug/GestureFlow \
  --replay ~/Library/Application\ Support/GestureFlow/recordings/robustness_<cond_id>.jsonl \
  --out /tmp/replay_<cond_id>.jsonl

# 3. Evaluate event-level recall, direction confusion, false triggers/min, and frame-to-action latency (p50/p95)
cd /Users/thundercock2/Documents/Github/Project-G1
python3 tools/eval_gestures.py \
  --data ~/Library/Application\ Support/GestureFlow/recordings/robustness_<cond_id>.jsonl \
  --replayed /tmp/replay_<cond_id>.jsonl
```

---

## 2. Condition Matrix

| Condition ID | Dimension | Physical Setup | Target FPS | Recording File | Swipe Recall (%) | Scroll Recall (%) | Pinch Recall (%) | False Triggers / min | Latency p50 / p95 (ms) | Status |
| :--- | :--- | :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `light_normal` | Lighting | Indoor normal desk lighting (~300–500 lux) | 60 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |
| `light_low` | Lighting | Dim room / evening monitor-glow only (<50 lux) | 30 / 60 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |
| `light_backlit` | Lighting | Strong window or lamp behind user (backlit silhouette) | 60 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |
| `fps_60` | Frame Rate | Good lighting, active 60 FPS capture | 60 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |
| `fps_30` | Frame Rate | Low-light auto-exposure drop or 30 FPS webcam | 30 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |
| `hand_right` | Handedness | Right hand performing all single-hand gestures | 60 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |
| `hand_left` | Handedness | Left hand performing all single-hand gestures | 60 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |
| `dist_near` | Distance | Close to MacBook webcam (~25–35 cm) | 60 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |
| `dist_normal` | Distance | Typical ergonomic desk distance (~40–55 cm) | 60 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |
| `dist_far` | Distance | Leaning back (~60–75 cm, near upper interaction bound) | 60 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |
| `user_glasses` | Accessories | User wearing eyeglasses / reflective lenses | 60 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |
| `bg_clutter` | Background | Busy background / other people or moving objects in view | 60 | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `not measured` | `NEEDS-USER` |

---

## 3. Data Currently in the Repository

The repository contains **no real hand recordings**. The only JSONL files are synthetic test fixtures (`tools/fixtures/*.jsonl`) and their golden replay outputs (`tools/golden/*.golden.jsonl`). They test code paths only and must **never** be used to fill the matrix above.
