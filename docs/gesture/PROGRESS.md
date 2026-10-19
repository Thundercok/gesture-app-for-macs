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

## 2026-10-12: WP7 — Training Data Tooling + Posture Classifier in Shadow Mode

- Commits:
  - `02a5df8`: `feat(tools): feature export and posture trainer`
  - `8a99d2b`: `feat(posture): shadow-mode classifier wrapper`
- Status: **DONE (Code & Tooling Complete) / BLOCKED AT DATA GATE (`NEEDS-USER` for >=3 real sessions)**
- Deliverables:
  - Implemented `tools/export_features.py`:
    - Pure Python stdlib feature exporter computing a canonical 56D vector (42 normalized landmark coordinates + 14 engineered distances/curl angles).
    - Enforces translation invariance (wrist at origin), scale invariance (divided by wrist-to-middleMCP length), rotation invariance (aligned to vertical $+Y$), and handedness mirroring invariance (canonicalized to right-hand frame).
    - Performs strict session/file-level train/test splitting (`split.json`), preventing frame-level temporal leakage.
    - Maps ground-truth labels to 5 canonical posture classes (`none`, `open_palm`, `pinch`, `two_fingers`, `fist`).
  - Implemented `tools/test_export_features.py`:
    - 6 unit tests verifying translation, scale, in-plane rotation, and horizontal mirroring invariance on synthetic hands.
  - Implemented `tools/train_posture.py`:
    - Trains `MLPClassifier(hidden_layer_sizes=(64, 64), activation='relu')` on training sessions and evaluates per-class precision, recall, F1, and confusion matrix on held-out sessions.
    - Enforces mandatory diversity gate: prints loud `INSUFFICIENT DIVERSITY` banner and refuses to export `PostureClassifier.mlmodel` when fewer than 3 distinct recording sessions exist.
    - Exports Core ML NeuralNetwork via `coremltools` MIL builder when the gate passes.
  - Created `docs/gesture/MODEL_CARD.md`:
    - Documented model architecture, library versions (`scikit-learn 1.9.0`, `coremltools 9.0`, `numpy 2.5.1`), 56D feature specification, and promotion gate criteria.
  - Implemented `GestureFlowApp/Sources/GestureFlow/Tracking/PostureClassifier.swift`:
    - Loads `PostureClassifier.mlmodel` / `.mlmodelc` if present; otherwise acts as a safe no-op pass-through (`isAvailable == false`).
    - Implements 5-frame majority vote smoothing + 3-frame hysteresis ($\ge 0.70$ confidence threshold).
    - Runs in parallel to heuristic posture detection, logging `shadowPosture` and `shadowAgrees` in `HandFrameRecord` and `IncidentRecorder`.
    - Added `GestureTuning.useLearnedPosture` (default `false`).
  - Extended `tools/eval_gestures.py` with `--shadow` to report heuristic vs model disagreement matrices and user misfire alignment.
- Verification:
  - `swift build`: clean in 30.19s (0 errors, 0 warnings).
  - `python3 -m unittest discover -s tools -p "test_*.py" -v`: 29/29 tests passing in 0.640s.
- Open issues / Gate:
  - Model export and promotion gate (`useLearnedPosture = true`) remain intentionally halted at the data gate (`NEEDS-USER`: record $\ge 3$ sessions via `GestureFlow --guided`).

## 2026-10-12: WP8 — Pretrained-Model Decision (Follow-up to WP4)

- Status: **SKIPPED**
- Reason: `skipped: WP4 recommended Option 4 (Lightweight MLP on normalized 2D landmarks, already implemented in WP7) over heavy external dependencies (MediaPipe / Core ML conversion), and real shadow evaluation data is pending user recordings (NEEDS-USER).`

## 2026-10-13: WP9 — UX and Robustness

- Commits:
  - `f79d134`: `feat(hud): show why a gesture was rejected`
  - `a422ab9`: `feat(feedback): undo on misfire mark`
  - `c20ce17`: `feat(calibration): onboarding wizard`
  - `3c6fa23`: `docs(robustness): condition matrix`
- Status: **DONE**
- Deliverables:
  - **WP9.1 (Why-not-recognised HUD Badge)**: Created `Tracking/RejectReason.swift` (`faceOverlap`, `edgeOnPalm`, `notStable`, `tooSlow`, `tooShort`, `axisAmbiguous`, `cooldown`, `arbiterBusy`, `pinchGuard`, `lowConfidence`), emitted reject reasons from `GestureEngine` when candidate hand speed $\ge 0.22$, auto-cleared after 1.0s in `AppState`, and displayed via dedicated `@ViewBuilder private var rejectReasonBadge` in `HUDView.swift`.
  - **WP9.2 (Undo / Feedback Loop on Misfire Mark)**: Added `IntentArbiter.recentCommittedAction(within: 3.0)` and `ActionDispatcher.performUndo(forAction:)` (supporting inverse Space switches, Escape to exit Mission Control, and Show Desktop toggle). Wired behind menu bar toggle `"Hoàn tác khi đánh dấu bắn sai"` (default `false`) for `⌃⌥⌘M` and menu item triggers.
  - **WP9.3 (Calibration Onboarding Wizard)**: Created `Tracking/CalibrationWizard.swift` implementing a 60-second voice-guided wizard (10s open-palm size measurement + 5 × 10s natural horizontal swipe trials). Persists raw `CalibrationMeasurements` to `UserDefaults` (`gf.calibration.raw.v1`) and `~/Library/Application Support/GestureFlow/calibration.json`, and derives `GestureTuning` velocity/displacement thresholds at 65% of natural median motion. Wired to menu item `"Hiệu chuẩn (60s Calibration)..."`. (`NEEDS-USER` to run with live hands).
  - **WP9.4 (Robustness Matrix Doc)**: Created `docs/gesture/ROBUSTNESS.md` with 12 physical test conditions (lighting, FPS, handedness, distance, glasses, background clutter), exact recording/replay/evaluation commands, and all result cells marked `not measured` (`NEEDS-USER`) per Rule R3.
  - **WP9.5 (Replay Frame-to-Action Latency)**: Added `latencyMs` calculation (frame timestamp minus ground-truth window onset) and p50/p95 summary reporting to both `ReplayRunner.swift` and `tools/eval_gestures.py`.
- Verification:
  - `swift build`: clean (0 errors, 0 warnings).
  - `python3 -m unittest discover -s tools -p "test_*.py" -v`: 29/29 tests passing.

## 2026-10-13: WP10 — Release Hygiene

- Status: **DONE**
- Deliverables:
  - Updated `GestureFlowApp/README.md` with build/run instructions, macOS TCC permissions table (Camera, Accessibility, Input Monitoring), system modes, sensitivity presets, hotkeys reference table, strict zero-pixel privacy statement, data locations, and offline evaluation/replay/training commands.
  - Created `docs/gesture/CHANGELOG.md` summarizing WP0–WP10 with commit SHAs.
  - Executed final clean build from scratch (`rm -rf GestureFlowApp/.build && swift build`), verified 29/29 Python unit tests, and confirmed byte-for-byte golden replay parity.

## 2026-10-19: WP11 — Repo hygiene
- Status: DONE
- Commits: `4274e94` chore(repo): update remote and gitignore
- What changed:
  - Updated origin remote URL to `https://github.com/Thundercok/gesture-app-for-macs.git` and verified fetch.
  - Updated `.gitignore` to explicitly cover `*.mlmodelc` and `tools/data/`.
  - Checked `git ls-files` for tracked build products or binaries; none found.
- Verification (verbatim):
  - `git remote -v` → `origin https://github.com/Thundercok/gesture-app-for-macs.git (fetch)`
  - `git status` → `nothing to commit, working tree clean`
- Live behaviour change: none
- NEEDS-USER: none

## 2026-10-19: WP12 — Fix B1: IntentArbiter clock domain
- Status: DONE
- Commits: `9bc942e` fix(arbiter): use one clock domain for cooldown checks
- What changed:
  - Replaced `clock.uptime` with `clock.now.timeIntervalSinceReferenceDate` in `isInCooldown` and `currentIntent` within `IntentArbiter.swift` so cooldown comparisons match the reference date timestamps set in `commitAction`.
- Verification (verbatim):
  - `swift build` → `Build complete! (16.23s)`
  - `python3 -m unittest discover -s tools -p "test_*.py" -v` → `Ran 29 tests in 1.085s OK`
  - `git diff tools/golden` → empty output (0 differences)
- Live behaviour change: Live recordings now show `predictedIntent` returning to `idle` after cooldown expires instead of being permanently locked in cooldown. Older live recordings may contain inflated `cooldown` stretches. Frame-level metrics across the fix boundary should not be directly compared.
- NEEDS-USER: none

## 2026-10-19: WP13 — Swift unit-test target
- Status: DONE
- Commits: `ac3df11` test(swift): add GestureFlowTests target
- What changed:
  - Added `.testTarget(name: "GestureFlowTests", dependencies: ["GestureFlow"], path: "Tests/GestureFlowTests")` to `GestureFlowApp/Package.swift`.
  - Created initial test case `GestureFlowApp/Tests/GestureFlowTests/SmokeTests.swift` testing `GestureTuning.balanced.swipeMinVelocity == 0.50` with `@testable import GestureFlow`.
  - Created executable helper script `tools/run_swift_tests.sh`.
- Verification (verbatim):
  - `swift test` → `Executed 1 test, with 0 failures (0 unexpected) in 0.003 (0.003) seconds`
  - `python3 -m unittest discover -s tools -p "test_*.py" -v` → `Ran 29 tests in 0.221s OK`
  - `git diff tools/golden` → empty output (0 differences)
- Live behaviour change: none
- NEEDS-USER: none
## 2026-10-19: WP14 — Fix B2: Backward-compatible GestureTuning decoding
- Status: DONE
- Commits: `e943772` fix(tuning): decode settings saved before useLearnedPosture existed
- What changed:
  - Added custom `CodingKeys`, memberwise `init`, and `init(from decoder:)` in `GestureTuning.swift` so that JSON payloads lacking `useLearnedPosture` or `preset` decode with default values (`false` and `.balanced` respectively).
  - Created `GestureFlowApp/Tests/GestureFlowTests/GestureTuningTests.swift` verifying legacy JSON decoding without `useLearnedPosture`, `TuningPreset.balanced` baseline equivalence, lerp endpoints, and round-trip JSON serialization.
- Verification (verbatim):
  - `swift test` → `Executed 5 tests, with 0 failures (0 unexpected) in 0.005 (0.008) seconds`
  - `python3 -m unittest discover -s tools -p "test_*.py"` → `Ran 29 tests in 0.973s OK`
  - `git diff tools/golden` → empty output (0 differences)
- Live behaviour change: Users who stored custom preferences prior to WP7 will not encounter decoding failures or drop back to defaults.
- NEEDS-USER: none

## 2026-10-19: WP15 — Undo routed through ActionSink + tests
- Status: DONE
- Commits: `78a408a` refactor(undo): plan inverse actions through ActionSink
- What changed:
  - Created `GestureFlowApp/Sources/GestureFlow/Tracking/UndoPlanner.swift` with pure `InverseAction` mapping (`swipe_left` → `.switchSpace(.left)`, `swipe_right` → `.switchSpace(.right)`, `swipe_up` → `.pressEscape`, `swipe_down` → `.toggleShowDesktop`) and localized descriptions.
  - Added `pressEscape()` to `ActionSink` protocol, implemented in `LiveActionSink` (delegating to `ActionDispatcher.pressEscape()`) and `RecordingActionSink` (recording `"press_escape"`).
  - Refactored `ActionDispatcher.performUndo` to route execution through `UndoPlanner` and an injected `ActionSink` (defaulting to `LiveActionSink.shared`).
  - Added `GestureFlowApp/Tests/GestureFlowTests/UndoPlannerTests.swift` covering mapping table across all `FINE_DIRECTIONAL_CLASSES` plus non-directional/invalid inputs, action dispatch recording verification, and `IntentArbiter.recentCommittedAction` 3.0s boundary conditions via `ReplayClock`.
- Verification (verbatim):
  - `swift test` → `Executed 8 tests, with 0 failures (0 unexpected) in 0.024 (0.028) seconds`
  - `python3 -m unittest discover -s tools -p "test_*.py"` → `Ran 29 tests in 1.119s OK`
  - `git diff tools/golden` → empty output (0 differences)
- Live behaviour change: none (forward and inverse action semantics remain identical).
- NEEDS-USER: none

## 2026-10-19: WP16 — Calibration wizard rework (B3)
- Status: DONE
- Commits: `bb9e44e` fix(calibration): measure engine-equivalent windowed velocity, thread-safe, revertible
- What changed:
  - Extracted pure mathematical routines into `GestureFlowApp/Sources/GestureFlow/Tracking/CalibrationMath.swift` (`windowedPeakVelocity`, `windowedPeakDisplacement`, `derive`, `median`) replicating `GestureEngine.evaluateSwipe` offsets (3...7) and time delta windowing (0.035s <= dt <= 0.180s).
  - Reworked `CalibrationWizard.swift` with an `NSLock` protecting internal mutable state across timer and frame callbacks, dispatching UI callbacks to `main`, and storing `previousTuningBeforeCalibration` with `revertLastCalibration()`.
  - Added `case custom` to `TuningPreset`, set it upon calibration completion, ensured graceful fallback to `.balanced` for unrecognised preset strings, and added "Hoàn tác hiệu chuẩn" menu item in `MenuBar.swift`.
  - Added headless `--calibrate-replay <file.jsonl>` CLI command in `main.swift` via `CalibrationReplayRunner.swift`.
  - Added unit test suite `CalibrationMathTests.swift` (5 tests covering straight-line motion, jitter robustness vs old per-frame amplification, clamp bounds, and median calculation) and added custom/unknown preset tests to `GestureTuningTests.swift`.
- Verification (verbatim):
  - `swift test` → `Executed 15 tests, with 0 failures (0 unexpected) in 0.007 (0.012) seconds`
  - `swift run GestureFlow --calibrate-replay tools/fixtures/synthetic_swipe_left.jsonl` → `Trials: 1, Peak Speeds: ["2.917"], Displacements: ["0.220"], Derived Thresholds: swipeMinVelocity=0.85, swipeMinDisplacement=0.110`
  - `python3 -m unittest discover -s tools -p "test_*.py"` → `Ran 29 tests in 0.292s OK`
  - `git diff tools/golden` → empty output (0 differences)
- Live behaviour change: Calibration thresholds now accurately reflect engine-equivalent kinematics without per-frame noise amplification, and calibrated settings can be reverted via the menu bar.
- NEEDS-USER: Live microphone / camera calibration wizard run remains NEEDS-USER.


