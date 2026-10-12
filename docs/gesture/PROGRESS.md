# GestureFlow Development Progress Log

## WP0 — Preflight — 2026-10-12
- Status: DONE
- Commit: 4108648
- What changed:
  - Confirmed working branch `revision/gestures` is clean.
  - Swift debug build completed cleanly (0 errors, 0 warnings).
  - Evaluator test suite `tools/test_eval_gestures.py` passed (8/8 tests OK).
- Verification:
  - `swift build`: 0.46s exit 0
  - `python3 -m unittest tools/test_eval_gestures.py -v`: 8 passed in 0.007s
- Open issues: none

## WP1 — Passive "flight recorder" + misfire hotkey — 2026-10-12
- Status: DONE
- Commit: 0033e72
- What changed:
  - Created `Tracking/IncidentRecorder.swift` with lock-protected 4.0s ring buffer (240 frames @ 60 FPS) and storage cap enforcement (200 MB).
  - Factored out `makeFrameRecord(...)` in `DatasetRecorder.swift` to share schema across recorders.
  - Added global & local keyboard hotkeys for ⌃⌥⌘M (`.misfire` + Basso sound) and ⌃⌥⌘N (`.missed`).
  - Added menu bar items for marking misfires, marking missed gestures, and toggling passive recording.
  - Wired auto-fire dumping (2.0s pre + 1.0s post) and 10-minute quiet baseline snapshots.
  - Documented incident format in `docs/gesture/INCIDENTS.md`.
  - Extended `tools/eval_gestures.py` with `--incidents` mode, calculating counts, misfire rate, and 95% Wilson score confidence interval.
  - Added 4 unit tests in `tools/test_eval_gestures.py` covering header skipping, Wilson score intervals, and misfire calculations.
- Verification:
  - `swift build`: clean in 13.29s (0 errors, 0 warnings).
  - `python3 -m unittest tools/test_eval_gestures.py -v`: 12/12 passed in 0.090s.
  - `python3 tools/eval_gestures.py --incidents ~/Library/Application\ Support/GestureFlow/incidents`: clean exit 0 on empty directory.
- Open issues: none

## WP2 — GestureTuning, Safe/Balanced/Sensitive presets, sensitivity control — 2026-10-12
- Status: DONE
- Commit: 8f80d3e
- What changed:
  - Created `Tracking/GestureTuning.swift` encapsulating motion thresholds, dwelling parameters, cooldowns, and presets (Safe, Balanced, Sensitive) with thread-safe persistence in `UserDefaults` (`gf.tuning.v1`).
  - `balanced` preset numerically matches the exact baseline constants (swipe displacement 0.065, velocity 0.50, dominance 1.30, calm hand 0.42, post-pinch guard 0.35s, swipe cooldown 0.45s, scroll flick min velocity 0.42).
  - Added time-based `openPalmDwellSeconds` tracking in `GestureEngine.swift` via `openPalmSince` timestamp.
  - Replaced hardcoded thresholds in `GestureEngine.swift` and `ScrollEngine.swift` with dynamic reads from `GestureTuning.current`.
  - Added menu bar submenu "Độ nhạy cử chỉ (Sensitivity)" with radio state selection for Safe, Balanced, and Sensitive presets.
- Verification:
  - `swift build`: clean in 8.25s (0 errors, 0 warnings).
  - `python3 -m unittest tools/test_eval_gestures.py -v`: 12/12 passed in 0.026s.
  - Manual runtime check: NOT RUN (needs user).
- Open issues: none

## WP3 — Direction-aware fired events — 2026-10-12
- Status: DONE
- Commit: fd23dea
- What changed:
  - Added `firedAction: String` to `HandFrameRecord` with backward-compatible JSON decoding.
  - Extended `IntentArbiter.commitAction(...)` with concrete action string parameter and exposed `lastCommittedActionName`.
  - Wired explicit physical motion names (`"swipe_left"`, `"swipe_right"`, `"swipe_up"`, `"swipe_down"`, `"pinch_dock"`, `"scroll_down"`, `"scroll_up"`, `"scroll_brake"`) across `GestureEngine.swift`, `ScrollEngine.swift`, and `main.swift`.
  - Updated `DatasetRecorder.recordFrame(...)` and `IncidentRecorder.dumpFrames(...)` to record and persist `firedAction`.
  - Upgraded `tools/eval_gestures.py` event evaluation to evaluate directional matching (`swipe_left` vs `swipe_right`, `scroll_down` vs `scroll_up`), added a dedicated Direction Confusion Table, and maintained fallback to macro classes on legacy recordings.
  - Added 5 unit tests in `tools/test_eval_gestures.py` verifying directional hits, directional mismatches scored as `wrong`, vertical swipe confusion, scroll direction matching, and legacy macro fallback (17/17 tests passing).
- Verification:
  - `swift build`: clean (0 errors, 0 warnings).
  - `python3 -m unittest tools/test_eval_gestures.py -v`: 17/17 passed in 0.146s.
  - `python3 tools/eval_gestures.py --test`: clean exit 0.
- Open issues: none

## WP4 — Research spike: pretrained hand-gesture models on macOS — 2026-10-12
- Status: DONE
- Commit: d284ed6
- What changed:
  - Authored `docs/gesture/RESEARCH_PRETRAINED.md` evaluating 4 architectural options: MediaPipe Gesture Recognizer, Apple Create ML Hand Pose Classifier, CoreML converted open models (HaGRID), and Plain Normalized Landmark MLP.
  - Compared integration effort, Apple Silicon latency, model size, license constraints, dependency burden, and dynamic swipe compatibility.
  - Established Go/No-Go decision: NO-GO on external pixel/C++ models (MediaPipe/HaGRID); GO on lightweight Landmark MLP / Create ML model in Shadow Mode (WP7) for static posture gating, retaining deterministic kinematic arbitration for dynamic gestures.
- Verification:
  - Document review complete; conforms to academic rules (no synthetic benchmarks claimed as real, cited sources and licenses).
- Open issues: none

## WP5 — Replay harness (enables tuning without hands) — 2026-10-12
- Status: DONE
- Commits: 11a5a98, 3605b13, 70dc379
- What changed:
  - Sub-step 1 (`11a5a98`):
    - Abstracted clock with `Clock` protocol (`SystemClock` for live runtime, `ReplayClock` for virtual time).
    - Isolated side-effects with `ActionSink` protocol (`LiveActionSink` for OS integration, `RecordingActionSink` for offline capture without hardware events).
    - Extracted pure feature calculation into `HandFeatureExtractor.landmarks(...)`.
    - Injected Clock, ActionSink, and IntentArbiter instances into `GestureEngine.swift` and `ScrollEngine.swift`.
  - Sub-step 2 (`3605b13`):
    - Extended `HandFrameRecord` with optional replay fields: `confidence`, `faceBBox`, `isInInteractionRange`, `handCentroid`, `tiltAngleDegrees` (with flexible JSON decoding supporting older recordings and both array/dictionary representations).
    - Created `Tracking/ReplayRunner.swift` for headless, deterministic offline replay over JSONL files.
    - Wired `--replay <path>`, `--tuning safe|balanced|sensitive|<json>`, `--out <path>`, and `--mode <nav|scroll|all>` CLI flags in `main.swift`.
  - Sub-step 3 (`70dc379`):
    - Created synthetic test fixtures in `tools/fixtures/` (`synthetic_swipe_left.jsonl`, `synthetic_pinch.jsonl`).
    - Added golden references under `tools/golden/` locking byte-for-byte deterministic outputs using `.sortedKeys` JSON formatting.
    - Implemented `tools/test_replay.py` asserting exact replayed action sequences and 100% byte-for-byte parity against golden references.
    - Extended `tools/eval_gestures.py` with `--replayed <path>` to evaluate replayed outputs against dataset ground truths.
    - Implemented `tools/sweep.py` for grid search over `GestureTuning` parameters with guard requiring >= 20 gesture windows on real datasets.
    - Unit tests expanded to 22 tests across test suites (18 in `test_eval_gestures.py`, 4 in `test_replay.py`), all green.
- Verification:
  - `swift build`: clean in 10.63s (0 errors, 0 warnings).
  - `python3 -m unittest tools/test_eval_gestures.py -v`: 18/18 passed in 0.067s.
  - `python3 -m unittest tools/test_replay.py -v`: 4/4 passed in 0.694s.
  - Determinism test: `diff -u tools/golden/... <replayed>` returns completely empty (exit 0).
  - Side-effect isolation: grep confirms 0 direct calls to `ActionDispatcher.` inside engines and replay runner.
- Open issues: none

## 2026-10-12: WP6 — Structural Refactor (Behaviour-Preserving)

- Commits:
  - `9889f1b`: `refactor(app): split main.swift (no behaviour change)`
  - `ce6545a`: `refactor(tracking): split GestureEngine process into helper stages`
- Status: **DONE**
- Deliverables:
  - Split `main.swift` (~1070 lines) into modular app components under `GestureFlowApp/Sources/GestureFlow/App/`:
    - `AppState.swift`: Observable application state, system mode enumeration, camera display mode enumeration.
    - `AppDelegate.swift`: Application lifecycle, window setup, spatial switcher dock setup, permission checking.
    - `MenuBar.swift`: NSStatusItem menu configuration, mode switching, sensitivity preset updates, incident actions.
    - `KeyboardMonitors.swift`: Global and local keyboard event listeners for incident tagging (`⌃⌥⌘M`, `⌃⌥⌘N`) and dataset labeling keys.
    - `Pipeline.swift`: Camera frame capture, hand tracking, engine routing, bimanual zoom calculations, intentionality gating overlay presentation.
    - `GateVerification.swift`: Intentionality gating and telemetry test harness (`runGateVerification`).
    - `main.swift`: Trimmed down to clean, compact entry point handling CLI routing (`--replay`, `--test-gates`) and `NSApplication` startup.
  - Refactored `GestureEngine.process(_:)` in `GestureFlowApp/Sources/GestureFlow/Tracking/GestureEngine.swift`:
    - Separated into ordered private helper methods: `updateSuppressionState`, `updateHandKinematics`, `evaluateSwipe`, `evaluatePinchDock`, `evaluateStandby`, `evaluateArmed`, `evaluateDockScrub`, `handleHandLost`.
    - Decomposed compound boolean chains (>4 terms) into clear intermediate named conditions.
    - Preserved exact execution and early-return semantics.
- Verification & Benchmarks:
  - Byte-for-byte golden replay parity:
    - `diff -u tools/golden/synthetic_pinch.golden.jsonl /tmp/after_synthetic_pinch.jsonl`: Identical (diff empty, code 0).
    - `diff -u tools/golden/synthetic_swipe_left.golden.jsonl /tmp/after_synthetic_swipe_left.jsonl`: Identical (diff empty, code 0).
  - Test suites: `python3 -m unittest tools/test_replay.py tools/test_eval_gestures.py -v`: 22/22 tests passing.
  - Clean build benchmark (from scratch):
    - Pre-refactor: `Build complete! (492.77s) (swift build 239.34s user 49.99s system)`
    - Post-refactor: `Build complete! (389.52s) (swift build 240.51s user 46.06s system)`
    - Clean build speedup: ~103.25s reduction (~21.0% faster clean compilation).
    - Incremental rebuild speedup: `21.32s`.
- Open issues: none


