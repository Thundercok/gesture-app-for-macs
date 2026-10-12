# Research Spike: Pretrained & Custom Hand-Gesture Models on macOS

**Date**: October 2026  
**Context**: GestureFlow (macOS, Swift 6, Apple Silicon, Vision Framework)  
**Objective**: Evaluate whether pretrained or custom machine learning recognizers can replace or augment hand-tuned kinematic thresholds to eliminate cross-gesture clashes and false activations.

---

## 1. Options Evaluated

| Option | Architecture | Input Data | Integration Effort | Latency (Apple Silicon) | Model Size | License |
|---|---|---|---|---|---|---|
| **1. MediaPipe Gesture Recognizer** | Bundled Landmark + MLP Task | Raw `CVPixelBuffer` | **High (L)** | 10–18 ms (CPU/Metal) | 5–9 MB | Apache 2.0 |
| **2. Apple Create ML Hand Pose** | Spatial Graph / Gradient Boosted Tree | `VNHumanHandPoseObservation` | **Low (S)** | < 1.0 ms (ANE/Metal) | ~200 KB – 1 MB | Apple SDK |
| **3. CoreML Open Model (HaGRID/FreiHAND)** | MobileNetV3 / ResNet18 via `coremltools` | Cropped Hand Image `CVPixelBuffer` | **Medium (M)** | 2.5–6.0 ms (ANE) | 15–35 MB | CC BY-NC-SA 4.0 / Apache 2.0 |
| **4. Plain MLP on 21 Normalized Landmarks** | 2-Layer MLP ($42 \to 64 \to 32 \to C$) | 42 normalized coordinates | **Low (S)** | < 0.05 ms (SIMD / Accelerate) | ~25 KB | MIT / Project Native |

---

## 2. In-Depth Analysis

### 2.1 Option 1: Google MediaPipe Gesture Recognizer
* **Overview**: Google's unified hand landmark and gesture recognition pipeline ([Google AI Edge / MediaPipe](https://ai.google.dev/edge/mediapipe/solutions/vision/gesture_recognizer)).
* **Out-of-the-Box Classes**: 7 static postures (`Unrecognized`, `Closed_Fist`, `Open_Palm`, `Pointing_Up`, `Thumb_Down`, `Thumb_Up`, `Victory`, `ILoveYou`). Does *not* detect dynamic directional swipes or dock-scrubbing interactions.
* **macOS & Swift Support**:
  - MediaPipe Tasks Vision is distributed primarily for iOS (via CocoaPods) and Android.
  - Official Swift Package Manager (SPM) distribution on native macOS desktop (`x86_64` / `arm64`) is absent or requires complex C++ Bazel compilation / bridging headers.
* **Pros**: Highly robust against lighting variations; widely cited benchmark.
* **Cons & Risks**:
  - **Redundant Computation**: GestureFlow already extracts 21 hand landmarks at 60 FPS using Apple Vision `VNDetectHumanHandPoseRequest` on Apple Silicon Neural Engine. Running MediaPipe would double camera ingestion and power consumption.
  - **Packaging Friction**: Substantial friction integrating C++ dependencies into a clean SwiftPM project.

### 2.2 Option 2: Apple Create ML Hand Pose Classifier
* **Overview**: Apple's native framework for training hand pose classifiers from landmarks ([Apple Developer Documentation: Create ML Hand Pose](https://developer.apple.com/documentation/createml/creating-a-hand-pose-classifier-model)).
* **Input**: Directly consumes `VNHumanHandPoseObservation` emitted by Apple Vision.
* **macOS & Swift Support**: Native first-class support in macOS 14+ / Sonoma / Sequoia. Direct integration via `CreateML.framework` or loading `.mlmodel` / `.mlpackage` into `VNCoreMLRequest`.
* **Pros**:
  - Zero third-party runtime dependencies.
  - Runs with near-zero latency on the Apple Neural Engine (ANE).
  - Perfect architectural parity with our existing `HandTracker` output.
* **Cons & Risks**:
  - Classification is strictly static (posture per frame). It cannot determine swipe velocity, ballistic deceleration, or flick momentum without a temporal state machine.

### 2.3 Option 3: Core ML Conversion of Open Pretrained Models (HaGRID)
* **Overview**: Converting academic gesture datasets such as HaGRID (HAnd Gesture Recognition Image Dataset, ~500k images, 18 classes) using `coremltools` ([HaGRID GitHub Repository](https://github.com/hukenovs/hagrid)).
* **Input**: Cropped hand bounding box tensors ($224 \times 224$ RGB).
* **Pros**: Recognizes nuanced finger positions and challenging angles.
* **Cons & Risks**:
  - **License Restrictions**: HaGRID dataset is licensed under **CC BY-NC-SA 4.0** (Non-Commercial, Share-Alike), preventing unrestricted commercial distribution.
  - **Overhead**: Requires continuous cropping, scaling, and pixel buffer allocations for every frame, consuming significant memory bandwidth.

### 2.4 Option 4: Plain Lightweight MLP on 21 Normalized Landmarks
* **Overview**: A custom 2-hidden-layer MLP ($42 \to 64 \to 32 \to C$) trained directly on the 21 $(x, y)$ coordinate pairs extracted by `DatasetRecorder` and `IncidentRecorder`.
* **Input Normalization**:
  - Wrist landmark $P_0$ translated to $(0, 0)$.
  - Rotation normalized using wrist-to-MCP middle finger vector.
  - Scale normalized by palm diameter (distance from wrist to MCP middle).
* **Inference Options**:
  - Option A: Native Swift matrix multiplication using Apple's `Accelerate` / `vDSP` / SIMD primitives (zero framework overhead, < 50 µs).
  - Option B: Exported via `coremltools` to a `.mlpackage` (< 30 KB).
* **Pros**:
  - Microsecond latency; zero battery/thermal footprint.
  - Complete control over classes (`open_palm`, `pinch`, `two_fingers`, `fist`, `idle_casual`).
  - No external licensing or third-party binary dependencies.
* **Cons & Risks**:
  - Requires clean representative training data (collected via WP1 passive incidents and WP3 guided recordings).

---

## 3. Synthesis & Trade-Off Matrix

```
                      Integration  ANE / GPU  Dynamic Swipes  License   Dependency
Approach                 Effort     Latency      Support      Safety      Burden
----------------------------------------------------------------------------------
MediaPipe Tasks          High       12 ms          No         Apache2     Heavy (C++)
Apple Create ML          Low        < 1 ms         No         Native      Zero
HaGRID via CoreML        Medium     4 ms           No         NC-SA 4.0   Medium
Plain Landmark MLP       Low        < 0.1 ms       No         MIT         Zero
Kinematic Rules (Now)    Done       < 0.01 ms      Yes        Native      Zero
```

---

## 4. Final Recommendation & Go/No-Go Decision

### 4.1 Recommendation: **Hybrid Two-Tier Architecture**
1. **Tier 1 (Posture Classification)**: Use **Option 4 (Plain Landmark MLP)** or **Option 2 (Create ML Hand Pose)** exclusively as an **instantaneous posture validator**.
   - Output classes: `open_palm_flat`, `index_pinch`, `two_finger_extended`, `casual_noise`.
   - Replaces fragile heuristic thresholds (such as finger curl dot products and distance ratios) with a robust probability distribution.
2. **Tier 2 (Temporal Kinematics & Arbitration)**: Retain the existing **`GestureEngine` + `IntentArbiter` state machine**.
   - Kinematics (displacement, velocity dominance, coasting momentum, refractory cooldowns) are inherently temporal and deterministic; rule-based physics state machines handle these with zero latency and complete predictability.

### 4.2 Go / No-Go Decision Criteria
* **Pretrained Models (MediaPipe / HaGRID)**: **NO-GO**. Reject due to platform integration friction, duplicate landmark computation, licensing hurdles, and lack of dynamic swipe awareness.
* **Custom Landmark MLP / Create ML Model**: **GO for WP7 in Shadow Mode**.
  - Train the posture classifier only after collecting sufficient incident data (minimum 50 incidents across idle and active use).
  - Deploy strictly in **Shadow Mode** first: log model output alongside rule-based output without dispatching system actions, verifying false-trigger reduction before cutting over.
