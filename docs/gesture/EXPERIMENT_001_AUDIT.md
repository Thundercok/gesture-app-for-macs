# GestureFlow Experiment 001 — Pre-Implementation Audit Report
**Topic**: Context-Conditioned Human Intent Inference for Hands-Free Desktop Interaction  
**Date**: 2026-11-09  
**Status**: AUDIT COMPLETE (Ready for Implementation)

---

## 1. Feature Representations & Dimensions (Discrepancy Analysis)

### A. 64D `featureTensor`
- **Definition**: [`HandTracker.swift:34`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/Tracking/HandTracker.swift#L34) (`let featureTensor: [Float]`).
- **Generator**: [`MonocularDepthEstimator.swift:177-205`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/Tracking/MonocularDepthEstimator.swift#L177-L205) (`generateAIFeatureVector(landmarks:depth:pinchDist:)`).
- **Coordinate Space & Semantics**:
  - **3D Wrist-Relative (Unrotated)**:
    - 21 joints $\times$ 3 $(X, Y, Z)$ normalized by palm scale (`wrist` to `middleMCP` length):
      - $X = (p.x - w.x) / \text{palmScale}$
      - $Y = (p.y - w.y) / \text{palmScale}$
      - $Z = 0.2 \times \text{depth}$ for fingertips (indices 4, 8, 12, 16, 20), $0.0$ for all other joints.
    - Feature at index 63 (64th dimension): scale-invariant pinch proximity scalar $\min(1.0, \text{pinchDist} / (\text{palmScale} \times 0.6))$.
- **Consumers**:
  - Stored inside `HandLandmarks.featureTensor`.
  - Initialized with 64 zeros in [`GateVerification.swift:63`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/App/GateVerification.swift#L63).
  - **Not** written to JSONL in `DatasetRecorder` or `IncidentRecorder`.
  - **Not** consumed by `PostureClassifier` or `FeatureDumper`.

### B. 56D Vector (`PostureClassifier.extractFeatures`)
- **Definition**: [`PostureClassifier.swift:87-169`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/Tracking/PostureClassifier.swift#L87-L169).
- **Coordinate Space & Semantics**:
  - **2D Canonicalized (Wrist-Centered, Rotated, Scale-Normalized, Mirror-Invariant)**:
    - Origin translated to wrist (`w`). Screen Y inverted to Cartesian (`w.y - y`).
    - Scaled by distance from wrist to Middle MCP (joint 9).
    - Rotated such that the wrist-to-Middle MCP vector points along $+Y$ ($\pi/2$).
    - Mirrored along $X$ if pinky MCP $x <$ index MCP $x$ (left/right hand invariance).
    - 42 normalized coordinates ($21 \times 2$: $x_i, y_i$).
    - 4 planar geometric distances: palm width ($5 \leftrightarrow 17$), thumb-index ($4 \leftrightarrow 8$), thumb-middle ($4 \leftrightarrow 12$), index-middle ($8 \leftrightarrow 12$).
    - 5 fingertip-to-wrist distances: thumb, index, middle, ring, pinky.
    - 5 joint cosine curls: thumb (1,2,4), index (5,6,8), middle (9,10,12), ring (13,14,16), pinky (17,18,20).
    - Total: $42 + 4 + 5 + 5 = 56$ floats.
- **Consumers**:
  - [`PostureClassifier.shared.evaluateShadow`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/Tracking/PostureClassifier.swift#L173): CoreML inference (`PostureClassifier.mlmodel` / `palm_depth_mlp.json`).
  - [`FeatureDumper.swift:81`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/Tracking/FeatureDumper.swift#L81): CSV export (`--dump-features`).
  - Python training & parity pipeline [`tools/export_features.py:80`](file:///Users/thundercock2/Documents/Github/Project-G1/tools/export_features.py#L80) & [`tools/test_feature_parity.py`](file:///Users/thundercock2/Documents/Github/Project-G1/tools/test_feature_parity.py).

> **Architectural Decision**: 64D is an unrotated 3D coordinate tensor for temporal intent modeling; 56D is a 2D canonicalized posture descriptor. They must remain completely distinct representations.

---

## 2. Dataset Recording & Replay Pipeline Audit

- **`HandFrameRecord` Schema** ([`DatasetRecorder.swift:20-176`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/Tracking/DatasetRecorder.swift#L20-L176)):
  - Serializes `timestamp`, `frameIndex`, `groundTruth`, `predictedIntent`, `firedIntent`, `firedAction`, `handDetected`, `fingerCount`, `isPinching`, `isTwoFingers`, `isRaisedHand`, `estimatedDepth`, `facingCamera`, `primaryPoints`, `secondaryPoints`, `confidence`, `faceBBox`, `isInInteractionRange`, `handCentroid`, `tiltAngleDegrees`, `shadowPosture`, `shadowAgrees`.
- **Runtime Call Sites of `recordFrame`**:
  - Exactly **one** call site in the application: [`Pipeline.swift:234-242`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/App/Pipeline.swift#L234-L242), executing inside `cameraManager.onFrame` on the serial camera queue `com.gestureflow.camera`.
- **Ground-Truth Label Assignment**:
  - Maintained as `DatasetRecorder.shared.currentLabel: String`.
  - Manual mode: updated by global/local keyboard monitors (`0`–`8`) in [`KeyboardMonitors.swift`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/App/KeyboardMonitors.swift).
  - Automated mode: voice/UI schedule driver in [`GuidedSession.swift:45-127`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/Tracking/GuidedSession.swift#L45-L127) locks manual keys and cycles through idle blocks and balanced gesture repetitions with transition cushions (`"ignore"`).
- **Replay Compatibility** ([`ReplayRunner.swift:130-220`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/Tracking/ReplayRunner.swift#L130-L220)):
  - Reads line-by-line using `JSONDecoder().decode(HandFrameRecord.self, from: data)`.
  - All extended properties in `HandFrameRecord` must be optional (`decodeIfPresent`) to guarantee zero regression on historical recordings.

---

## 3. Concurrency & Thread-Safety Audit

Inspecting [`DatasetRecorder.swift:280-358`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/Tracking/DatasetRecorder.swift#L280-L358) and [`docs/gesture/THREADING.md`](file:///Users/thundercock2/Documents/Github/Project-G1/docs/gesture/THREADING.md):

1. **Cross-Queue Mutable State**:
   - `isRecording`, `fileHandle`, and `currentLabel` are written on Main / WindowServer threads (`startRecording`, `setGroundTruthLabel`, `setLabelFromKey`), but read on `com.gestureflow.camera` (`recordFrame`) without lock protection.
2. **Data Race on `recordedFrameCount`**:
   - Incremented asynchronously on `com.gestureflow.recorder` background queue while exposed via `public private(set) var recordedFrameCount: Int` to caller threads.
3. **Descriptor Invalidation Race**:
   - `recordFrame` checks `guard let handle = fileHandle`, then dispatches `queue.async`. If `stopRecording()` executes `queue.sync` in between, it closes `fileHandle` and sets it to `nil`, risking inflight writes to a closed descriptor.
4. **Queue Unbounded Memory**:
   - In the event of slow disk I/O, `queue.async` queues blocks at 60 FPS without backpressure.

### Required Concurrency Fix:
- Introduce an `NSLock` or isolate mutable state to ensure:
  - `startRecording`, `stopRecording`, and `setGroundTruthLabel` synchronize access to `fileHandle`, `isRecording`, `currentLabel`, and `recordedFrameCount`.
  - `stopRecording()` flushes and drains pending writes before closing `fileHandle`.

---

## 4. Implementation Specification: `DesktopContextProvider`

A standalone, non-blocking module [`DesktopContextProvider.swift`](file:///Users/thundercock2/Documents/Github/Project-G1/GestureFlowApp/Sources/GestureFlow/Tracking/DesktopContextProvider.swift):

### Fields to Collect:
| Field | Type | Acquisition Method | Availability Fallback |
|---|---|---|---|
| `activeAppBundleID` | `String?` | `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` | Explicit `nil` / unavailable |
| `appCategory` | `String` | Pattern map: Browser, Code Editor, File Manager, Communication, Media, Other | `"unknown"` if unmapped/unavailable |
| `focusedElementRole` | `String?` | Accessibility API (`kAXFocusedUIElementAttribute`, `kAXRoleAttribute`) if `AXIsProcessTrusted()` | `nil` (never fabricated) |
| `windowState` | `String` | Foreground status of frontmost application window | `"foreground"`, `"hidden"`, `"unknown"` |
| `cursorPosition` | `[Double]?` | `NSEvent.mouseLocation` normalized across primary screen | `nil` if mouse query fails |
| `timestamp` | `Double` | Sampling timestamp (`Date().timeIntervalSinceReferenceDate`) | Exact time of observation |
| `availability` | `[String: Bool]` | Explicit boolean map of successfully queried dimensions | Complete transparency on missing fields |

### Privacy & Performance Guarantees:
- **Zero Sensitive Data**: Zero window titles, zero document contents, zero URLs, zero keystrokes, zero screenshots.
- **Non-blocking**: Throttled / cached sampling (e.g. 10–20 Hz) or fast asynchronous read to never block the 60 FPS camera capture queue.

---

## 5. Verification Baseline & Test Results
- **Swift Test Suite**: 10 suites, 43 tests passing in `0.47s` (`swift test --package-path GestureFlowApp`).
  - Added `DesktopContextProviderTests.swift` (5 tests): category classification, serialization, partial missing data, mock injection, intent mapping.
  - Added `DatasetRecorderTests.swift` (4 tests): historical JSONL backward compatibility, modern JSONL decoding, lifecycle integrity, concurrent multi-threaded stress test (200 frames across 4 threads).
- **Python Parity Suite**: 47 tests passing in `5.05s` (`python3 -m unittest discover -s tools -p "test_*.py" -v`).
- **Golden References**: 0 byte differences (`git diff tools/golden` clean).

