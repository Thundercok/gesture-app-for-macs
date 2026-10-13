# GestureFlow — Spatial Hand-Gesture Controller for macOS

> **Target Platform**: macOS 14.0+ (Sonoma, Sequoia)  
> **Hardware Target**: Apple Silicon (M1/M2/M3/M4) with Apple Neural Engine (ANE)  
> **Language & Frameworks**: Swift 5.9+, SwiftUI, Apple Vision (`Vision.framework`), AVFoundation, CoreGraphics, CoreML, Accessibility (`AXUIElement`)  
> **Source Directory**: `GestureFlowApp/`

---

## 1. Overview

**GestureFlow** is a native, low-latency (60 FPS active / 15 FPS idle auto-throttled) spatial hand-gesture controller for macOS. It combines Apple Vision 21-point hand pose estimation with deterministic kinematic arbitration (`IntentArbiter`), configurable sensitivity presets (`GestureTuning`), an offline deterministic replay harness (`--replay`), a passive flight-recorder (`IncidentRecorder`), and an optional Core ML posture classifier in shadow mode (`PostureClassifier`).

---

## 2. Build & Run

```bash
# Build debug binary via Swift Package Manager
cd GestureFlowApp
swift build

# Launch GestureFlow
.build/arm64-apple-macosx/debug/GestureFlow

# Launch voice-guided 7-minute dataset recording session
.build/arm64-apple-macosx/debug/GestureFlow --guided

# Run deterministic headless replay on a recorded JSONL file
.build/arm64-apple-macosx/debug/GestureFlow --replay <input.jsonl> --tuning balanced --output /tmp/replayed.jsonl
```

---

## 3. Required macOS Permissions

GestureFlow requires three macOS TCC permissions under **System Settings → Privacy & Security**:

| Permission | Purpose | Where to Enable |
| :--- | :--- | :--- |
| **Camera** | Captures live video frames into `Vision.framework` (`VNDetectHumanHandPoseRequest`) in memory | Privacy & Security → Camera |
| **Accessibility** | Synthesizes Space switches (`⌃←` / `⌃→`), Mission Control (`⌃↑`), Show Desktop (`⌘F3`), smooth scrolling (`CGEvent`), and app activation (`AXUIElement`) | Privacy & Security → Accessibility |
| **Input Monitoring** | Listens for global incident-marking hotkeys (`⌃⌥⌘M` / `⌃⌥⌘N`) and ground-truth dataset labeling keys (`0`–`8`) when the HUD is unfocused | Privacy & Security → Input Monitoring |

---

## 4. System Modes & Sensitivity Presets

### System Modes
Switch modes from the menu bar icon (`hand.raised.fill`), the HUD mode badge, or via shortcut keys:
1. **Air Scroll (`⌘1`)**: Two-finger vertical flicks with iOS-style momentum decay (`0.942` per 16ms tick) and open-palm immediate brake.
2. **Mac Navigation (`⌘2`)**:
   - Open-palm horizontal swipes (`swipe_left` / `swipe_right`) to switch Desktop Spaces.
   - Open-palm vertical swipes (`swipe_up` for Mission Control, `swipe_down` for Show Desktop).
   - Open-palm scan → pinch-and-hold → horizontal scrub to open and select from the Spatial App Switcher Dock.
3. **Spatial Zoom (`⌘3`)**: Bimanual (two-hand) pinch-and-spread proportional magnification (`⌘+` / `⌘-`).

### Sensitivity Presets (`GestureTuning`)
Selectable under the menu bar submenu **Độ nhạy cử chỉ (Sensitivity)** and persisted in `UserDefaults` (`gf.tuning.v1`):
- **An toàn (`Safe`)**: Higher velocity (`0.65`), displacement (`0.085`), axis dominance (`1.50`), and open-palm dwell (`0.15s`) to minimize accidental triggers during typing or talking.
- **Cân bằng (`Balanced` — Default)**: Baseline thresholds (`swipeMinVelocity = 0.50`, `swipeMinDisplacement = 0.065`, `openPalmDwellSeconds = 0.05`).
- **Nhạy (`Sensitive`)**: Lighter thresholds (`swipeMinVelocity = 0.40`, `swipeMinDisplacement = 0.055`, `openPalmDwellSeconds = 0.03`) for effortless triggering.
- **Hiệu chuẩn (`60s Calibration`)**: Interactive 60-second wizard measuring median palm size and 5 natural swipes, storing raw measurements alongside derived thresholds (65% of natural median motion).

---

## 5. Hotkeys Reference

| Hotkey | Scope | Action |
| :--- | :--- | :--- |
| `⌃⌥⌘M` | Global & Local | **Mark Misfire Incident** (`IncidentRecorder.markUser(.misfire)`): dumps the last 4.0s of landmarks to disk. If **Hoàn tác khi đánh dấu bắn sai** is enabled in the menu bar and an auto-fire occurred within 3.0s, automatically performs the inverse action. |
| `⌃⌥⌘N` | Global & Local | **Mark Missed Gesture Incident** (`IncidentRecorder.markUser(.missed)`): dumps the last 4.0s of landmarks when an intended gesture failed to fire. |
| `⌘1` / `⌘2` / `⌘3` | Menu Bar | Switch between **Air Scroll**, **Mac Navigation**, and **Spatial Zoom** modes. |
| `⌘D` / `⌘M` | Menu Bar | Show/Hide Debug HUD (`⌘D`) or Toggle Compact Pill / Expanded Viewport (`⌘M`). |
| `⌘R` | Menu Bar | Start/Stop continuous JSONL dataset recording. |
| `0`–`8` | While Recording (`⌘R`) | Set live ground-truth label (`0`: `idle`, `1`: `pinch_dock`, `2`: `swipe_left`, `3`: `swipe_right`, `4`: `swipe_up`, `5`: `swipe_down`, `6`: `scroll_down`, `7`: `scroll_up`, `8`: `zoom`). Locked during `--guided` sessions. |

---

## 6. Privacy Statement & Data Locations

- **Zero Pixel Storage Guarantee**: GestureFlow **never** writes camera images, video frames, or raw pixel buffers (`CVPixelBuffer` / `NSImage`) to disk. Camera frames exist strictly in volatile RAM for the duration of the `VNDetectHumanHandPoseRequest` inference call (~2–4 ms).
- **What Is Stored**: Incident logs and dataset recordings store **only** 21 normalized 2D hand landmark coordinates (`x, y` in `[0, 1]`), per-joint confidence scalars, anonymous normalized face bounding box coordinates (`x, y, w, h` for face-proximity suppression), and engine state strings.
- **Local Storage Paths**:
  - Passive Flight-Recorder Incidents (capped at 200 MB FIFO): `~/Library/Application Support/GestureFlow/incidents/`
  - Guided & Manual Dataset Recordings: `~/Library/Application Support/GestureFlow/recordings/`
  - Calibration Raw Measurements: `~/Library/Application Support/GestureFlow/calibration.json`
- **Opt-Out**: Passive incident recording can be toggled off at any time from the menu bar (**Ghi sự cố thụ động (Flight Recorder)**).

---

## 7. Offline Evaluation, Replay & Posture Training

```bash
# 1. Run all Python unit tests (scorer, feature invariance, deterministic replay)
python3 -m unittest discover -s tools -p "test_*.py" -v

# 2. Evaluate recorded datasets (frame-level + directional event-level + p50/p95 latency)
python3 tools/eval_gestures.py --data ~/Library/Application\ Support/GestureFlow/recordings

# 3. Evaluate passive flight-recorder incidents (misfires, missed gestures, 95% Wilson CI)
python3 tools/eval_gestures.py --incidents ~/Library/Application\ Support/GestureFlow/incidents

# 4. Evaluate shadow-mode posture classifier agreement vs heuristic posture
python3 tools/eval_gestures.py --data ~/Library/Application\ Support/GestureFlow/recordings --shadow

# 5. Grid-search GestureTuning thresholds via deterministic replay (requires >= 20 real gesture windows)
python3 tools/sweep.py --data ~/Library/Application\ Support/GestureFlow/recordings

# 6. Export canonical 56D features (session-level split) and train Core ML PostureClassifier
python3 tools/export_features.py --data ~/Library/Application\ Support/GestureFlow/recordings --out-dir /tmp/gf_features
python3 tools/train_posture.py --features /tmp/gf_features/features.jsonl --split /tmp/gf_features/split.json
```
