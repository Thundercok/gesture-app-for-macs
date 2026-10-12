# GestureFlow Master Execution Plan (for an autonomous executor model)

> **Người đọc**: file này viết bằng tiếng Anh để model thực thi (Gemini) làm theo chính xác. Bạn (user) chỉ cần đọc mục 0 và mục 14.
> **Repo**: `/Users/thundercock2/Documents/Github/Project-G1` · **Branch làm việc**: `revision/gestures` · **App**: `GestureFlowApp/` (SwiftPM, macOS 14+, executable target `GestureFlow`).

---

## 0. TL;DR for the user

- The executor works through Work Packages (WP) **in order**. Each WP ends with a build, tests, a commit, and a line in `docs/gesture/PROGRESS.md`.
- Nothing in here requires your hands **except** the steps marked `NEEDS-USER`. The executor must stop at those, report, and continue with other unblocked WPs.
- No accuracy number may be reported unless it came from **real recorded data** (see Rule R3).

---

## 1. Hard rules (never violate)

| ID | Rule |
|---|---|
| R1 | Work only on branch `revision/gestures` (create `wip/<name>` branches only if explicitly instructed in a WP). Never touch `main`. |
| R2 | **Forbidden git commands**: `git reset --hard`, `git clean -fd`, `git push --force`/`-f`, `git checkout -- .`, `git branch -D`, `git rebase` on pushed commits. To undo your own mistake use `git revert <sha>` or fix forward. |
| R3 | **Academic/measurement integrity**: never claim recognition accuracy, recall, or "improved" from synthetic or hand-made frames. Synthetic data is allowed **only** for logic unit tests, and must be named so (e.g. `test_*`, `synthetic_*`). Any metric in docs/commit messages must cite the real `.jsonl` recording it came from (file name + date). If no real data exists, write "not measured". |
| R4 | Do not reintroduce depth-estimation-based gating (`MonocularDepthEstimator` thresholds). Monocular depth is unreliable and previously caused ~60% false suppressions. |
| R5 | Do not re-enable clap-to-switch-mode. Modes change only via ⌘1/⌘2/⌘3 and the menu bar. |
| R6 | Preserve existing comments/docstrings unrelated to your change. |
| R7 | Zero compiler **errors and warnings** in `swift build`. |
| R8 | Behaviour-preserving refactors (WP4) must be proven by replay golden output (WP3) being **byte-identical**. |
| R9 | Independent cold-start rule: any benchmark/replay must start engines from fresh state (call `IntentArbiter.shared.forceReset()` + new engine instances). Never carry state between recordings. |
| R10 | Do not run the app in a way that requires the user's camera or hands unless the WP says `NEEDS-USER`. You cannot gesture; do not pretend you tested gestures. |

---

## 2. Environment recipes and known pitfalls

### 2.1 Build
```bash
# From repo root. MUST use BypassSandbox:true for swift build (clang module cache is outside the workspace).
rm -f GestureFlowApp/.build/.lock GestureFlowApp/.build/build.db-journal   # only if a previous build was killed
cd GestureFlowApp && swift build
```
- Incremental build ≈ 15 s. Clean build ≈ 8 min (do **not** kill it; a killed build leaves a stale `.build/.lock`).
- Binary: `GestureFlowApp/.build/arm64-apple-macosx/debug/GestureFlow`.
- If a build seems hung >12 min, check the log; the Swift type-checker stalls on long boolean chains and deeply nested SwiftUI `@ViewBuilder` ladders.

### 2.2 Git
- `git add` / `git commit` fail inside the sandbox with `.git/index.lock: Operation not permitted`. Run them with `BypassSandbox:true`.
- Commit per WP with a Conventional-Commit message given in the WP.
- `git push` only when WP10 says so, and only `git push origin revision/gestures` (no force).

### 2.3 Swift type-checker rules (learned the hard way)
1. No boolean expression with more than ~4 terms inline. Split into named `let`s or nested `if`.
2. Give numeric literals explicit types in mixed `CGFloat`/`Double` expressions: `CGFloat(1.30)`, `Double(0.5)`.
3. In SwiftUI, extract each large conditional ladder into `@ViewBuilder private var xyz: some View`.
4. No closures with >1 statement inside a long chained expression.

### 2.4 Python tooling
```bash
python3 -m unittest tools/test_eval_gestures.py -v      # scorer logic tests (must stay green)
python3 tools/eval_gestures.py --data <file-or-dir>      # real-data evaluation
python3 tools/eval_gestures.py --test                    # arithmetic self-test ONLY (not accuracy)
```
Python 3 stdlib only unless a WP says otherwise.

### 2.5 Paths
- Recordings: `~/Library/Application Support/GestureFlow/recordings/*.jsonl`
- Telemetry: `~/Library/Application Support/GestureFlow/gesture_log.jsonl`
- Incidents (created by WP1): `~/Library/Application Support/GestureFlow/incidents/`

---

## 3. Repo map (current, commit `c7f2206`)

| File | Role |
|---|---|
| `Sources/GestureFlow/main.swift` (~1070 lines) | `AppState`, `AppDelegate`, menu bar, keyboard monitors, pipeline wiring, bimanual zoom, frame loop, `--record`/`--guided`/`--record-depth` flags |
| `Tracking/HandTracker.swift` | Vision `VNDetectHumanHandPoseRequest` → `HandLandmarks` (pinch, finger count, palm normal, etc.). `HandLandmarks` struct at top. Landmark confidence threshold 0.40 |
| `Tracking/GestureEngine.swift` | Swipes (L/R=Space, Up=Mission Control, Down=Desktop) + pinch-dock state machine. Swipe logic ≈ L185–300 |
| `Tracking/ScrollEngine.swift` | Two-finger air-scroll flicks and brake |
| `Tracking/IntentArbiter.swift` | Singleton mutual exclusion: `canBegin/claim/release/commitAction/forceReset`, `commitSequence`, `lastCommitted` |
| `Tracking/DatasetRecorder.swift` | JSONL recorder, `labelsLocked`, `firedIntent` |
| `Tracking/GuidedSession.swift` | Voice-guided auto-labelled recording (`--guided`) |
| `Tracking/TelemetryLogger.swift` | Simple append-only action log |
| `Tracking/ActionDispatcher.swift` | Synthesises macOS actions |
| `Tracking/OneEuroFilter.swift`, `MonocularDepthEstimator.swift`, `DepthRecorder.swift` | Filters / legacy depth tools (do not extend depth) |
| `UI/HUDView.swift`, `ApplicationSwitcherView.swift`, `HolographicSkeletonView.swift` | SwiftUI HUD, dock UI, skeleton overlay |
| `tools/eval_gestures.py`, `tools/test_eval_gestures.py` | Event-level + frame-level scorer and its logic tests |

Current swipe constants (all inline magic numbers in `GestureEngine.swift`):
`absDx/absDy >= 0.065`, `absVx/absVy >= 0.50`, axis dominance `1.30`, `stableOpenFrames >= 3`, `handSpeed < 0.42` (pinch), post-pinch guard `0.35 s`, swipe cooldown `0.42/0.45 s`, history window `0.035…0.180 s`.

---

## 4. Progress protocol (execute after **every** WP)

1. Ensure `swift build` has 0 errors/0 warnings; `python3 -m unittest tools/test_eval_gestures.py` green.
2. Append to `docs/gesture/PROGRESS.md` (create if missing):
   ```
   ## WP<N> — <title> — <ISO date>
   - Status: DONE | PARTIAL | BLOCKED(<reason>)
   - Commit: <sha>
   - What changed: <3-6 bullets>
   - Verification: <commands run + short result>
   - Open issues: <bullets or "none">
   ```
3. Commit docs together with the code (`BypassSandbox:true`).
4. If blocked (needs user hands, a decision, or a >3× repeated build failure): write `BLOCKED` entry, **skip to the next unblocked WP**, and list all blocked items in the final report.
5. Failure policy: if a WP breaks the build and 3 fix attempts fail, `git stash push -m "wp<N>-failed"`, mark BLOCKED with the compiler error text, move on. Do not discard work with forbidden commands.

---

## 5. Dependency graph

```
WP0 preflight
 ├─ WP1 passive incident logger + misfire hotkey
 ├─ WP2 GestureTuning + safe mode
 ├─ WP3 direction-aware fired events
 ├─ WP4 pretrained-model research spike (report only)
 └─ WP5 replay harness (needs WP2 + WP3)
        └─ WP6 behaviour-preserving refactor (needs WP5 goldens)
        └─ WP7 posture classifier in shadow mode (needs WP5; data-gated, NEEDS-USER for volume)
              └─ WP8 pretrained option (only if WP4 recommends and WP7 shadow data exists)
WP9 UX + robustness (needs WP1, WP2; WP9.5 needs WP5)
WP10 release hygiene (last)
```
Execute in numeric order unless blocked. (Numbering below follows execution order.)

---

# WORK PACKAGES

## WP0 — Preflight

**Goal**: confirm a clean, green baseline.

Steps:
1. `git status` → must be on `revision/gestures`; if the tree is dirty with unknown changes, **stop and report** (do not discard).
2. `git log -n 3 --oneline` → top commit should be `c7f2206` or a descendant.
3. Clean stale locks (see 2.1), run `swift build` (bypass sandbox).
4. Run `python3 -m unittest tools/test_eval_gestures.py -v`.
5. Create `docs/gesture/PROGRESS.md` with a header and a "WP0 DONE" entry.

Acceptance: build green, 8 tests pass, progress file exists.
Commit: `chore(gestures): add progress log` (only if files changed).

---

## WP1 — Passive "flight recorder" + misfire hotkey (highest priority, zero user effort)

**Why**: gives a real, continuously accumulating false-trigger metric from normal computer use, and real training material later. The user only has to press one hotkey when the app fires wrongly.

### Design
- A **ring buffer** keeps the last **4.0 s** of compact frames in memory (no disk writes during idle use).
- A dump ("incident") is written to disk when:
  - **A. Auto-fire**: any action commits (`IntentArbiter.commitSequence` changes). Dump the 2.0 s before + 1.0 s after (capture post-window asynchronously). Label: `fire`.
  - **B. Misfire mark**: user presses the global hotkey **⌃⌥⌘M** (also a menu item "Đánh dấu vừa bắn sai"). Dump the last 4.0 s. Label: `misfire`. Also show HUD action text `Đã đánh dấu bắn sai` and play `Basso`.
  - **C. Missed mark**: global hotkey **⌃⌥⌘N** / menu item "Đánh dấu vừa bỏ lỡ cử chỉ" — user tried a gesture and nothing fired. Dump last 4.0 s. Label: `missed`.
- Also write 1 sampled "quiet" snapshot (2 s) every 10 minutes when a hand is visible and no action fired, label `quiet` (to estimate base rates and negatives).
- Passive mode is **on by default**, toggle in menu bar ("Ghi sự cố thụ động"), disabled while `--record`/`--guided` is active (those already record everything).
- Storage cap: delete oldest incident files when total > **200 MB**.
- Privacy: store **only landmark coordinates + timestamps + engine state**, never camera pixels. Document this in the menu item tooltip and README.

### Files
- New: `Tracking/IncidentRecorder.swift`
- Edit: `main.swift` (feed frames, hotkeys, menu items), `HUDView.swift` only if a small badge is wanted (optional).
- New doc: `docs/gesture/INCIDENTS.md` (format + how to analyse).

### Specification
```swift
// IncidentRecorder.swift
final class IncidentRecorder {
    static let shared = IncidentRecorder()
    var isEnabled: Bool            // persisted in UserDefaults key "gf.passiveIncidents", default true
    func ingest(frame: HandFrameRecord)          // called every frame from main loop, cheap, lock-protected ring buffer (~4 s)
    func markAutoFire(intent: String)            // called when commitSequence increases; schedules post-window capture
    func markUser(_ kind: IncidentKind)          // .misfire / .missed
    func enforceStorageCap()                     // called after each write
}
enum IncidentKind: String { case fire, misfire, missed, quiet }
```
- Reuse `HandFrameRecord` (in `DatasetRecorder.swift`); factor out a function `makeFrameRecord(frameIndex:timestamp:primary:secondary:predictedIntent:firedIntent:groundTruth:)` so both recorders share it. **Do not** change JSON keys of existing fields.
- Each incident file: `incidents/<yyyyMMdd_HHmmss>_<kind>.jsonl`, first line is a header object `{"incident":"misfire","createdAt":"<ISO8601>","appVersion":"<git sha or dev>","note":""}`, followed by frame records. `groundTruth` for `fire`/`quiet` frames = `unlabeled`; for `misfire` = `misfire` (meaning: whatever fired in this window was wrong); for `missed` = `missed`.
- Frame ingestion must be allocation-light: store `HandFrameRecord` structs, cap at ~240 frames (4 s @ 60 fps).
- Global key monitor: extend `setupKeyboardMonitoring()` in `main.swift`; modifier check `event.modifierFlags.contains([.control, .option, .command])` and `event.charactersIgnoringModifiers?.lowercased()` equals `"m"` / `"n"`. Keep the existing digit-label monitors unchanged.

### Evaluator support (Python)
- Extend `tools/eval_gestures.py` with `--incidents <dir>` mode that prints:
  - count of `fire`, `misfire`, `missed`, `quiet` incidents,
  - **misfire rate** = misfire / (fire + misfire) with a 95% Wilson interval,
  - per-intent breakdown of misfires (from `firedIntent` inside the misfire window),
  - hours of active use covered (approx from timestamps of incident files; state it is approximate).
- Add unit tests in `tools/test_eval_gestures.py` for: header line skipped, misfire rate arithmetic, Wilson interval at n=0 returns `None`.

### Acceptance
- `swift build` clean. App launches with no crash (launch headless for ≤5 s only if camera permission already granted; otherwise skip and note it).
- Unit tests green (new ones included).
- Incident file schema documented in `docs/gesture/INCIDENTS.md`.
- No frame-by-frame disk writes when no incident occurs (verify by code review: writes only inside the three trigger paths).

### Verification commands
```bash
python3 -m unittest tools/test_eval_gestures.py -v
python3 tools/eval_gestures.py --incidents ~/Library/Application\ Support/GestureFlow/incidents   # prints "no incidents yet" gracefully if empty
```
Commit: `feat(telemetry): passive flight-recorder incidents with misfire/missed hotkeys`

`NEEDS-USER` (non-blocking, later): the user works normally for a few days and presses ⌃⌥⌘M on bad fires. Executor must not wait for this; continue.

---

## WP2 — `GestureTuning`, Safe/Balanced/Sensitive presets, sensitivity control

**Why**: instant improvement without data and a single knob instead of scattered magic numbers. Also a prerequisite for replay tuning.

### Specification
- New file `Tracking/GestureTuning.swift`:
```swift
struct GestureTuning: Codable, Equatable {
    var swipeMinDisplacement: CGFloat      // current 0.065
    var swipeMinVelocity: Double           // current 0.50
    var swipeAxisDominance: CGFloat        // current 1.30
    var openPalmDwellSeconds: Double       // NEW: open palm must be held this long (time-based, not frames) before swipes arm; current effective ≈ 3 frames
    var pinchCalmHandSpeed: Double         // current 0.42
    var postPinchSwipeGuardSeconds: Double // current 0.35
    var swipeCooldownSeconds: Double       // current 0.42 / 0.45
    var scrollFlickMinVelocity: Double     // read current value from ScrollEngine.swift, do not guess
    static let balanced: GestureTuning     // = EXACTLY the current behaviour (regression-safe)
    static let safe: GestureTuning
    static let sensitive: GestureTuning
    static func lerp(_ a: GestureTuning, _ b: GestureTuning, t: Double) -> GestureTuning
    static var current: GestureTuning { get set }   // thread-safe, persisted in UserDefaults key "gf.tuning.v1"
}
```
- **Initial preset guesses (to be tuned later with replay; mark clearly as guesses in code comments)**:

| Param | safe | balanced (= today) | sensitive |
|---|---|---|---|
| swipeMinDisplacement | 0.085 | 0.065 | 0.055 |
| swipeMinVelocity | 0.65 | 0.50 | 0.40 |
| swipeAxisDominance | 1.50 | 1.30 | 1.20 |
| openPalmDwellSeconds | 0.15 | ≈0.05 | 0.03 |
| pinchCalmHandSpeed | 0.32 | 0.42 | 0.50 |
| postPinchSwipeGuardSeconds | 0.50 | 0.35 | 0.25 |
| swipeCooldownSeconds | 0.55 | 0.45 | 0.38 |

- Replace the inline constants in `GestureEngine.swift` and `ScrollEngine.swift` by reads from `GestureTuning.current` (read once per `process()` call into a local `let tune = GestureTuning.current`). With `.balanced` the behaviour must be **identical** to before (verify by diff review; the replay golden in WP5 will later lock it).
- Add `openPalmDwellSeconds` logic: track `openPalmSince: TimeInterval?` (set when `isOpenFingers && !isPinching` becomes true, cleared otherwise); swipe eligible only when `now - openPalmSince >= dwell`. Keep `stableOpenFrames >= 3` as an additional floor.
- Menu bar: submenu "Độ nhạy cử chỉ" with items **An toàn / Cân bằng / Nhạy** (radio check) and persisted. Optional continuous slider is out of scope.
- HUD: when a swipe-like motion is rejected only because of dwell/velocity/displacement, nothing to show yet (UX handled in WP9).

### Acceptance
- Build clean; `GestureTuning.balanced` numerically equals old constants (add a doc comment listing old values).
- Switching presets at runtime changes behaviour without restart (code path reads `current` each frame).
- Unit test impossible in Swift here → document manual check in `docs/gesture/PROGRESS.md` as `NOT RUN (needs user)`.

Commit: `feat(gestures): central GestureTuning with safe/balanced/sensitive presets and open-palm dwell`

---

## WP3 — Direction-aware fired events

**Why**: current `firedIntent` only holds the domain (`swipe`, `air_scroll`, …). A left swipe firing as right is not detected.

### Steps
1. Add `firedAction: String` to `HandFrameRecord` (e.g. `swipe_left`, `swipe_right`, `swipe_up`, `swipe_down`, `scroll_down`, `scroll_up`, `pinch_dock_open`, `pinch_dock_commit`, `pinch_dock_cancel`, `zoom_begin`, `zoom_end`). Keep `firedIntent`.
2. Extend `IntentArbiter.commitAction(gesture:cooldown:now:)` with an optional `action: String = ""` parameter, store `lastCommittedAction`, expose `var lastCommittedActionName: String`. Update **every** call site in `GestureEngine.swift`, `ScrollEngine.swift`, `main.swift` to pass the concrete action name. Physical direction convention: name by the **physical hand motion** (a hand swiping physically left = `swipe_left`, even though it triggers "space right"), matching `GuidedSession` labels.
3. `main.swift` frame loop: record `firedAction` using the same commit-sequence diff.
4. `tools/eval_gestures.py`: when `firedAction` exists, event matching uses the fine label (`swipe_left` vs `swipe_right`), add a **direction confusion** table; fall back to macro class when absent. Add unit tests (left fired as right counts as `wrong`, not `hit`).

Acceptance: build clean; tests green incl. new direction tests; old recordings (without `firedAction`) still evaluate.
Commit: `feat(eval): direction-aware fired actions and direction confusion`

---

## WP4 — Research spike: pretrained hand-gesture models on macOS (report only, no integration)

**Goal**: decide if a pretrained recognizer can replace/augment hand-tuned posture thresholds.

Deliverable: `docs/gesture/RESEARCH_PRETRAINED.md` (≤ 2 pages) comparing, with sources/links and dates:
1. MediaPipe Gesture Recognizer (macOS support status, Swift options, license, model size, classes, latency).
2. Apple Create ML Hand Pose Classifier (works on `VNHumanHandPoseObservation` directly; training data needs).
3. Core ML conversion of an open hand-gesture model (e.g. via `coremltools`) — feasibility, license.
4. Plain MLP on our normalized landmarks (cheapest).

For each: integration effort (S/M/L), runtime cost on Apple Silicon, license constraints, what training data it needs, risks. End with a recommendation and a go/no-go criterion.
Rules: cite sources; do **not** download datasets > 1 GB; do **not** claim measured performance (R3) — cite published numbers as "reported by <source>".

Commit: `docs(research): pretrained gesture model options`

---

## WP5 — Replay harness (enables tuning without hands)

**Goal**: `GestureFlow --replay <file.jsonl> --out <result.jsonl>` runs the **real engines** on recorded landmarks headlessly, deterministically, in seconds, and prints the event-level report.

### 5.1 Extend recorded data (backward compatible)
Add optional fields to `HandFrameRecord`: per-landmark `confidence` (21 floats), `faceBBox` (x,y,w,h or null), `isInInteractionRange`, `handCentroid`, `tiltAngleDegrees`. Old files lacking them must still load (use defaults and mark "degraded replay" in output).

### 5.2 Make engines replayable
- Introduce `protocol Clock { var now: Date { get }; var uptime: TimeInterval { get } }` with `SystemClock` and `ReplayClock`. Inject into `GestureEngine`, `ScrollEngine`, and `IntentArbiter` (default = `SystemClock`, so production unchanged). Replace every `Date()` / `ProcessInfo.processInfo.systemUptime` inside those three files with the injected clock. Search with `grep -n "Date()\|systemUptime"`.
- `IntentArbiter.shared` stays as production singleton; add `IntentArbiter(clock:)` instance initializer for replay. The engines must take an arbiter instance in their initializer (default `.shared`).
- Pure feature path: add `HandFeatureExtractor.landmarks(from points: [CGPoint], confidences: [Float], face: CGRect?, …) -> HandLandmarks?` that reproduces what `HandTracker` computes **from raw points** (copy logic out of `HandTracker.swift`; make `HandTracker` call the extractor so there is a single implementation). If exact parity for some fields is impossible without Vision data, document which fields are approximated and flag in replay output.
- Side-effect isolation: `ActionDispatcher` calls (switch space, mission control, key synthesis, sounds, haptics) must be **no-ops during replay**. Introduce `protocol ActionSink` with `LiveActionSink` (current behaviour) and `RecordingActionSink` (appends action names to an array). Engines call the sink instead of `ActionDispatcher` statics directly. **Never** let replay send real key events.

### 5.3 CLI
- `--replay <path>` (+ optional `--tuning safe|balanced|sensitive|<json file>`, `--out <path>`): no window, no camera, exits when done with code 0.
- Output JSONL: one line per input frame with `firedAction` produced by the replayed engines, then reuse `tools/eval_gestures.py` (add `--replayed <out.jsonl>` which merges ground truth from input with fired events from output).
- `tools/sweep.py`: grid-sweep over tuning parameters by invoking the binary with `--tuning <json>`, writing a CSV of (params → recall, misfire, double-fire, false triggers/min). Stdlib only. Must refuse to run when the input dataset has fewer than 20 labelled gesture windows ("not enough real data").

### 5.4 Golden regression
- `tools/fixtures/` holds tiny **synthetic** landmark streams for logic regression only (e.g. a hand moving 0.2 units left in 120 ms; a stationary pinch). File names must start with `synthetic_`.
- `tools/test_replay.py`: runs the binary on each fixture and asserts the **exact** action sequence (e.g. `["swipe_left"]`). These are logic tests, not accuracy (R3).
- Save golden outputs under `tools/golden/` for each fixture; WP6 compares byte-for-byte.

### Acceptance
- `swift build` clean; `--replay` on a synthetic fixture prints expected action names; `python3 -m unittest tools/test_replay.py` green; production live path unchanged (review diff: only constructor defaults and the sink indirection).
- Determinism: running replay twice produces identical output (`diff` empty).
- Replay never calls `ActionDispatcher` live (assert by grep that engines no longer reference `ActionDispatcher.` directly).

Commit(s) (split into 3): `refactor(core): inject Clock and ActionSink`, `feat(replay): headless --replay mode`, `feat(tools): sweep and replay regression tests`.

---

## WP6 — Structural refactor (behaviour-preserving, R8)

**Goal**: cut build times and make files reviewable. **No behaviour change.**

Targets:
1. Split `main.swift` (~1070 lines) into: `App/AppState.swift`, `App/AppDelegate.swift`, `App/MenuBar.swift`, `App/KeyboardMonitors.swift`, `App/Pipeline.swift`, with a tiny `main.swift` that only starts `NSApplication`. Keep behaviour and access levels; move code verbatim.
2. Split `GestureEngine.process(_:)` (very long) into private helpers: `updateHandKinematics`, `evaluateSwipe`, `evaluatePinchDock`, `evaluateDockScrub`, `handleHandLost`. Early returns must keep identical ordering.
3. Break remaining boolean chains >4 terms.
4. Add `Tracking/` subfolders only if SwiftPM `path:` still resolves (it does recursively).

Verification (mandatory, R8): run replay on every fixture before and after; outputs must be byte-identical:
```bash
for f in tools/fixtures/synthetic_*.jsonl; do .build/arm64-apple-macosx/debug/GestureFlow --replay "$f" --out /tmp/after_$(basename $f); done
# compare to tools/golden/*
```
Also record clean-build time before/after in PROGRESS.md (just numbers, no claims about gesture quality).

Commit(s): one per file split; message `refactor(app): split main.swift (no behaviour change)` etc.

---

## WP7 — Training data tooling + posture classifier in **shadow mode** (learned model, zero risk)

**Prerequisite**: real labelled data. `NEEDS-USER` for volume (guided sessions and/or incident files). The executor builds everything that does not need new data and **stops at the data gate**.

### 7.1 Export & normalisation (`tools/export_features.py`)
- Input: recordings + incident files. Output: `features.npz`-free pure CSV/JSONL (stdlib) with per-frame **normalised** landmark vector: translate wrist→origin, scale by wrist→middleMCP distance, rotate so wrist→middleMCP points up; mirror left-hand samples to right-hand frame; 21×2 = 42 floats + engineered angles (finger curl angles, thumb-index distance / palm length).
- **Split by session/file, never by frame** (leakage!): `--split-by file` with fixed seed; write `split.json`.
- Label posture classes: `none, open_palm, pinch, two_fingers, fist` derived from ground-truth gesture labels via an explicit mapping table in the script (documented; idle frames → `none`).

### 7.2 Trainer (`tools/train_posture.py`)
- Preferred: scikit-learn `MLPClassifier` or small PyTorch MLP (2×64, dropout). If packages are missing, `pip install --user scikit-learn coremltools` is allowed; record versions in `docs/gesture/MODEL_CARD.md`.
- Report per-class precision/recall on the **held-out files only**, class balance, confusion matrix, and n of files/people/lighting conditions. If <3 distinct recording sessions → print a loud "INSUFFICIENT DIVERSITY" banner and refuse to export a model.
- Export Core ML via `coremltools` to `GestureFlowApp/Sources/GestureFlow/Resources/PostureClassifier.mlmodel` **only** when the gate passes.

### 7.3 Swift integration — **shadow mode only**
- `Tracking/PostureClassifier.swift`: loads the model if present, otherwise no-op. Temporal smoothing: majority vote over 5 frames + hysteresis (change state only when new class prob ≥ 0.7 for 3 frames).
- Run **in parallel** to the heuristics, never driving actions. Log `shadowPosture` and `shadowAgrees` in `HandFrameRecord` / incidents.
- Add `tools/eval_gestures.py --shadow` summarising disagreement rates (heuristic posture vs model) and which one the user's `misfire` marks sided with.
- Feature flag: `GestureTuning.useLearnedPosture` default `false`. **Do not flip it** in code; flipping requires the gate below and user approval.

### 7.4 Promotion gate (written down; executor must not bypass)
The learned posture may drive actions only if **on held-out real recordings** it improves the event-level report over the heuristics baseline: recall not worse by >2 points on any gesture, clash rate and false-trigger/min lower, and misfire rate from incidents not higher. The comparison table (real data, files named) goes in `docs/gesture/MODEL_CARD.md`. Then ask the user to approve.

### Acceptance (what the executor can finish without new data)
Scripts run on the existing recordings or fixtures without crashing; unit tests for normalisation (rotation/scale invariance on synthetic landmarks — logic test only); Swift builds with the classifier as a no-op when the model file is absent.

Commit(s): `feat(tools): feature export and posture trainer`, `feat(posture): shadow-mode classifier wrapper`.

---

## WP8 — Pretrained-model decision (follow-up to WP4)

Only if WP4 recommended it **and** WP7 shadow data exists: implement the chosen option behind the same shadow-mode interface. Otherwise write "skipped: <reason>" in PROGRESS.md.

---

## WP9 — UX and robustness

### 9.1 Why-not-recognised HUD (in `HUDView.swift`, small badge)
Expose from engines a `lastRejectReason: RejectReason?` (enum: `faceOverlap`, `edgeOnPalm`, `notStable`, `tooSlow`, `tooShort`, `axisAmbiguous`, `cooldown`, `arbiterBusy(owner)`, `pinchGuard`, `lowConfidence`) updated whenever a candidate motion is rejected. Show the reason for ~1 s in the HUD only when a hand is visible and moving fast enough to look like a gesture attempt. Extract the new badge into its own `@ViewBuilder` (see 2.3).

### 9.2 Undo / feedback loop
When the user presses ⌃⌥⌘M within 3 s of an auto-fire, perform the **inverse action** where one exists (swipe left ↔ right Space, Mission Control ↔ exit via Escape, Show Desktop ↔ repeat show-desktop toggle) and record it as `misfire` (WP1). Behind a menu toggle `Hoàn tác khi đánh dấu bắn sai` (default off).

### 9.3 Calibration onboarding (optional, behind menu "Hiệu chuẩn")
60-second wizard: measures typical palm size and natural swipe speed (median of 5 user swipes) and sets `GestureTuning` thresholds as a **fraction** of those. Implementation must store raw measurements, not just the derived thresholds. `NEEDS-USER` to run; executor only builds it.

### 9.4 Robustness matrix doc (`docs/gesture/ROBUSTNESS.md`)
A table of conditions to record with `--guided` (lighting low/normal/backlit, fps 30/60, left/right hand, distance, glasses, background clutter) and the exact command to evaluate each. Leave result cells as `not measured`. Never fill from imagination (R3).

### 9.5 Power/latency
Measure (not guess) frame-to-action latency inside replay: add `latencyMs` using frame timestamps; report p50/p95 from replay on real data only.

Commit(s): `feat(hud): show why a gesture was rejected`, `feat(feedback): undo on misfire mark`, `feat(calibration): onboarding wizard`, `docs(robustness): condition matrix`.

---

## WP10 — Release hygiene

1. `README.md` (repo root or `GestureFlowApp/README.md`): install/build, permissions (Camera, Accessibility, Input Monitoring), modes, hotkeys table (⌘1/2/3, ⌃⌥⌘M, ⌃⌥⌘N, digit labels while recording), privacy statement (no pixels stored), data locations, how to run evaluation.
2. `docs/gesture/CHANGELOG.md` summarising WPs with commit SHAs.
3. Final full pass: clean build from scratch (`rm -rf GestureFlowApp/.build` is allowed **only here** and only that folder), tests, replay goldens.
4. `git push origin revision/gestures` (**no force**). If auth fails, report and stop; do not try alternative remotes.
5. Do **not** open/merge a PR into `main` without the user's explicit instruction.

Commit: `docs: README, changelog, privacy statement`.

---

## 6. Definition of done for the whole plan

- [ ] All WPs DONE or explicitly BLOCKED with reason in `docs/gesture/PROGRESS.md`.
- [ ] `swift build` clean from scratch: 0 errors, 0 warnings.
- [ ] `python3 -m unittest discover -s tools -p "test_*.py"` green.
- [ ] Replay is deterministic and golden outputs match after refactor.
- [ ] No metric in any doc without a real-data source (R3).
- [ ] Pushed `revision/gestures` (no force).

## 7. Final report format (executor must output)

1. Table: WP → status → commit SHA.
2. **What is measured vs not measured** (explicit list).
3. Blocked items and exactly what the user must do (commands to copy-paste).
4. Real numbers, if any exist (from incidents/recordings), with file names.
5. Risks / surprises found.

---

## 8. Escalation: stop and ask the user when

- A decision changes user-visible behaviour beyond the WP spec (default sensitivity, enabling learned posture, enabling undo by default).
- A step requires camera/hands, a system permission prompt, or a destructive operation.
- The working tree contains changes you did not make.
- You are about to claim an improvement.

---

## 9. Quick command cheat-sheet

```bash
# Build (BypassSandbox:true)
cd /Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp && swift build

# Scorer tests
cd /Users/thundercock2/Documents/Github/Project-G1 && python3 -m unittest tools/test_eval_gestures.py -v

# Stage + commit (BypassSandbox:true)
git add GestureFlowApp/Sources tools docs && git commit -m "<message>"

# Real-data evaluation
python3 tools/eval_gestures.py --data ~/Library/Application\ Support/GestureFlow/recordings
python3 tools/eval_gestures.py --incidents ~/Library/Application\ Support/GestureFlow/incidents

# Data collection (NEEDS-USER)
.build/arm64-apple-macosx/debug/GestureFlow --guided
```

---

## 14. For the user: what to do after switching models

1. Switch the model, open this repo, and say: **"Execute `docs/gesture/EXECUTOR_PLAN.md` from WP0, following its rules."**
2. Use the Mac normally. Press **⌃⌥⌘M** when the app fires something wrong, **⌃⌥⌘N** when a gesture you tried did nothing (after WP1 is built).
3. Whenever you have 7 free minutes: `GestureFlow --guided` (unlocks WP7 and real tuning).
4. Read the final report; approve any "ask the user" items.
