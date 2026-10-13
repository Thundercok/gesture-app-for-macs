# GestureFlow Posture Classifier — Model Card & Promotion Gate

## 1. Model Overview

- **Model Name**: `PostureClassifier`
- **Task**: Static / per-frame hand posture classification for intentionality gating and cross-gesture disambiguation.
- **Target Classes (5)**:
  1. `none` (Idle, resting, face touching, non-gesture transit)
  2. `open_palm` (Extended fingers / open palm for trackpad swipes & charging)
  3. `pinch` (Thumb-index pinch for dock app switcher)
  4. `two_fingers` (Index + middle extended for Air Scroll clutch)
  5. `fist` (All fingers curled / closed fist brake)
- **Architecture**: Multi-Layer Perceptron (`56 -> 64 -> ReLU -> 64 -> ReLU -> 5 -> Softmax`)
- **Runtime Format**: Core ML NeuralNetwork (`PostureClassifier.mlmodel` / `.mlmodelc`)

---

## 2. Training Environment & Versions

| Package | Version | Purpose |
| :--- | :--- | :--- |
| Python | 3.12 / 3.14 | Training & evaluation runtime |
| `scikit-learn` | `1.9.0` | `MLPClassifier` training and held-out evaluation |
| `coremltools` | `9.0` | MIL builder to Core ML NeuralNetwork export |
| `numpy` | `2.5.1` | Feature matrix representation |

---

## 3. Input Features & Geometric Invariances (56D)

Input vectors are computed identically in Python (`tools/export_features.py`) and Swift (`PostureClassifier.extractFeatures(from:)`):

1. **Wrist Translation**: Translate all 21 landmarks so the wrist ($P_0$) sits at the origin $(0, 0)$, converting screen top-left Y to standard Cartesian $+Y$ upwards.
2. **Scale Normalization**: Divide coordinates by the Euclidean palm length $\|P_9 - P_0\|_2$ (wrist to middle MCP).
3. **In-Plane Rotation**: Rotate all points by $\Delta\theta = \frac{\pi}{2} - \text{atan2}(P_9.y, P_9.x)$ so the palm axis points vertically along $+Y$.
4. **Handedness Mirroring**: If Pinky MCP ($P_{17}.x$) lies to the left of Index MCP ($P_5.x$), reflect across the Y-axis ($x \leftarrow -x$) so left-hand poses map identically to the canonical right-hand frame.
5. **Engineered Features (14 floats)**:
   - Palm width ($\|P_5 - P_{17}\|_2$)
   - Thumb–Index distance ($\|P_4 - P_8\|_2$)
   - Thumb–Middle distance ($\|P_4 - P_{12}\|_2$)
   - Index–Middle distance ($\|P_8 - P_{12}\|_2$)
   - 5 normalized fingertip-to-wrist distances ($P_4, P_8, P_{12}, P_{16}, P_{20}$)
   - 5 finger curl cosine angles at the intermediate joints

---

## 4. Data Hygiene & Diversity Gate

- **Session-Level Splitting**: `tools/export_features.py` splits datasets strictly by **recording file/session** (`split.json`), never by individual frames, eliminating temporal adjacency data leakage between train and test sets.
- **Diversity Gate**: `tools/train_posture.py` requires **$\ge 3$ distinct recording sessions** before permitting Core ML model export. When fewer than 3 sessions exist, it prints an `INSUFFICIENT DIVERSITY` banner and halts export.

---

## 5. Shadow-Mode Integration & Temporal Smoothing

- **Wrapper**: `GestureFlowApp/Sources/GestureFlow/Tracking/PostureClassifier.swift`
- **No-Op Fallback**: When `PostureClassifier.mlmodel` is absent from bundle resources, `PostureClassifier.shared.isAvailable` is `false` and `evaluateShadow` acts as a zero-overhead pass-through.
- **Temporal Filter**:
  - 5-frame rolling majority vote over raw model predictions.
  - 3-frame hysteresis gate requiring class probability $\ge 0.70$ before transitioning state.
- **Shadow Logging**: Every frame in `DatasetRecorder` and `IncidentRecorder` logs `shadowPosture` and `shadowAgrees` without altering live actuation.
- **Feature Flag**: `GestureTuning.current.useLearnedPosture` defaults to `false`.

---

## 6. Promotion Gate (Mandatory Before Enabling Actuation)

The learned posture classifier may drive live gesture gating (`useLearnedPosture = true`) **only** when all of the following criteria are met on held-out real user recordings:

1. **Recall Parity**: Event-level recall is not worse by $> 2.0$ percentage points on any gesture class compared to the heuristic baseline.
2. **Clash & False Trigger Reduction**: Cross-gesture clash rate and idle false triggers per minute are strictly lower than the heuristic baseline.
3. **Incident Misfire Alignment**: Misfire rate from passive flight-recorder incidents is not higher than baseline.
4. **User Approval**: Explicit user review and sign-off on the comparison table below.

### Held-Out Real-Data Comparison Table

> **Status**: `BLOCKED (NEEDS-USER)` — Waiting for $\ge 3$ real guided recording sessions (`GestureFlow --guided`) and passive incident logs. Per Rule R3, no synthetic numbers are reported here.

| Metric | Heuristic Baseline (`useLearnedPosture=false`) | Learned Posture (`useLearnedPosture=true`) | Gate Requirement | Status |
| :--- | :--- | :--- | :--- | :--- |
| Held-out Sessions ($n$) | not measured | not measured | $\ge 3$ sessions | `NEEDS-USER` |
| Swipe Left/Right Recall | not measured | not measured | $\ge \text{Baseline} - 2\%$ | `NEEDS-USER` |
| Swipe Up/Down Recall | not measured | not measured | $\ge \text{Baseline} - 2\%$ | `NEEDS-USER` |
| Pinch Dock Recall | not measured | not measured | $\ge \text{Baseline} - 2\%$ | `NEEDS-USER` |
| Air Scroll Recall | not measured | not measured | $\ge \text{Baseline} - 2\%$ | `NEEDS-USER` |
| Cross-Gesture Clash Rate | not measured | not measured | $< \text{Baseline}$ | `NEEDS-USER` |
| Idle False Triggers / min | not measured | not measured | $< \text{Baseline}$ | `NEEDS-USER` |
| Incident Misfire Rate | not measured | not measured | $\le \text{Baseline}$ | `NEEDS-USER` |
