# GestureFlow Flight Recorder & Incident Format

## Overview
The Flight Recorder (`IncidentRecorder.swift`) passively monitors live gesture interaction in the background with zero disk writes during normal idle operation. An in-memory ring buffer retains the last ~4.0 seconds (approx 240 frames @ 60 FPS) of compact landmark telemetry.

Disk writes occur strictly on three triggers:
1. **Auto-fire (`fire`)**: Any time `IntentArbiter.commitSequence` increments (an action fired), the preceding 2.0s and subsequent 1.0s window are saved.
2. **User Marked Misfire (`misfire`)**: When the user presses **⌃⌥⌘M** (Ctrl+Opt+Cmd+M) or clicks "Đánh dấu vừa bắn sai" in the menu bar, the last 4.0s of frames are captured and tagged as `misfire`.
3. **User Marked Missed Gesture (`missed`)**: When the user performs a gesture but the system fails to trigger, pressing **⌃⌥⌘N** (Ctrl+Opt+Cmd+N) captures the last 4.0s tagged as `missed`.
4. **Quiet Baseline (`quiet`)**: A 2.0s sample taken every 10 minutes when a hand is present to track true negatives.

## Privacy & Storage Guarantee
- **Zero Camera Image Pixels**: Only 21 normalized 2D/3D joint coordinates, timestamps, and internal detector flags are stored.
- **Storage Cap**: When the `incidents/` folder exceeds 200 MB, the oldest incident files are automatically deleted.
- **Storage Location**: `~/Library/Application Support/GestureFlow/incidents/`

## File Schema (.jsonl)
Each incident file is named `<yyyyMMdd_HHmmss>_<kind>.jsonl`.
The **first line** is a metadata header:
```json
{
  "incident": "misfire",
  "createdAt": "2026-10-12T14:30:00Z",
  "appVersion": "revision/gestures",
  "note": "user marked misfire"
}
```
All subsequent lines are standard `HandFrameRecord` objects (one JSON object per frame) identical to the dataset recording schema:
```json
{
  "timestamp": 12345.678,
  "frameIndex": 412,
  "groundTruth": "misfire",
  "predictedIntent": "swipe",
  "firedIntent": "swipe",
  "handDetected": true,
  "fingerCount": 5,
  "isPinching": false,
  "isTwoFingers": false,
  "isRaisedHand": true,
  "estimatedDepth": 0.35,
  "facingCamera": 0.92,
  "primaryPoints": [{"x": 0.45, "y": 0.62}, ...],
  "secondaryPoints": null
}
```

## How to Analyze
Run the evaluator CLI tool against the incidents directory:
```bash
python3 tools/eval_gestures.py --incidents ~/Library/Application\ Support/GestureFlow/incidents
```
Output includes:
- Counts of `fire`, `misfire`, `missed`, `quiet` events.
- **Misfire Rate** = `misfire / (fire + misfire)` with Wilson 95% confidence interval.
- Per-intent breakdown of spurious firings.
- Approximate hours of active computer usage covered.
