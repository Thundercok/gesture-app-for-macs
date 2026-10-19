# GestureFlow Data Schema Specification: `HandFrameRecord`

This document specifies the exact JSON serialization schema for `HandFrameRecord`, the standard recording unit streamed line-by-line (`.jsonl`) by `DatasetRecorder`, ingested by `IncidentRecorder`, and consumed by `ReplayRunner`, `eval_gestures.py`, `export_features.py`, and `report.py`.

---

## 1. Field Specification Table

Every field below is defined in `GestureFlowApp/Sources/GestureFlow/Tracking/DatasetRecorder.swift` under `struct HandFrameRecord` and its custom `CodingKeys` / `init(from decoder:)`:

| JSON Key | Swift Type | Requirement | Added In | Description |
| :--- | :--- | :---: | :---: | :--- |
| `timestamp` | `Double` | **Required** | WP0 | Monotonic frame capture timestamp in seconds (derived from unified reference clock). |
| `frameIndex` | `Int` | **Required** | WP0 | Zero-based continuous sequential frame index for the session. |
| `groundTruth` | `String` | **Required** | WP0 | Ground-truth gesture label set by voice-guided session schedule or keyboard hotkeys (`0`–`8`). |
| `predictedIntent` | `String` | **Required** | WP0 | Active continuous intent state from the kinematic arbiter (`idle`, `pinch_dock`, `swipe`, `air_scroll`, `spatial_zoom`, `cooldown`). |
| `firedIntent` | `String` | **Required`*` | WP0 | Macro-intent name committed on this exact frame (rising-edge trigger event). Empty string `""` on non-firing frames. |
| `firedAction` | `String` | **Required`*` | WP4 | Concrete directional action name committed on this exact frame (`swipe_left`, `swipe_right`, `swipe_up`, `swipe_down`, `scroll_down`, `scroll_up`, `pinch_dock`). Empty string `""` on non-firing frames. |
| `handDetected` | `Bool` | **Required** | WP0 | Boolean flag indicating whether Apple Vision detected at least one hand in the frame. |
| `fingerCount` | `Int` | **Required** | WP0 | Number of fully extended fingers on primary hand ($0$ to $5$). |
| `isPinching` | `Bool` | **Required** | WP0 | Boolean flag indicating thumb-index tip contact ($< 4.2\text{cm}$). |
| `isTwoFingers` | `Bool` | **Required** | WP0 | Boolean flag indicating index + middle extended with ring + pinky curled (Air Scroll clutch). |
| `isRaisedHand` | `Bool` | **Required** | WP0 | Boolean flag indicating hand raised into the active interaction volume above desk resting level. |
| `estimatedDepth` | `Double` | **Required** | WP0 | Metric distance $Z$ from camera optical center in meters (PnP hand span triangulation). |
| `facingCamera` | `Double` | **Required** | WP0 | Fused 3D normal vector dot product and planar triangle fullness metric ($\in [0.0, 1.0]$). |
| `primaryPoints` | `[{"x": Double, "y": Double}]` | **Required** | WP0 | 21 normalized 2D coordinates in $[0.0, 1.0]$ representing primary hand joints ($P_0$ to $P_{20}$). |
| `secondaryPoints` | `[{"x": Double, "y": Double}]?` | Optional | WP0 | 21 normalized 2D coordinates for secondary hand when two hands are simultaneously in view. |
| `confidence` | `[Float]?` | Optional | WP6 | Array of 21 joint confidence scalars in $[0.0, 1.0]$ emitted by `VNRecognizedPoint`. (Decodes `confidence` or legacy `confidences`). |
| `faceBBox` | `{"x": Double, "y": Double, "width": Double, "height": Double}?` | Optional | WP6 | Normalized bounding box of detected face for face-proximity suppression gating. |
| `isInInteractionRange` | `Bool?` | Optional | WP6 | Boolean flag indicating whether metric depth is within interaction bounds ($[0.35\text{m}, 0.70\text{m}]$). |
| `handCentroid` | `{"x": Double, "y": Double}?` | Optional | WP6 | Normalized 2D coordinate of palm center (midpoint of wrist $P_0$ and middle MCP $P_9$). |
| `tiltAngleDegrees` | `Double?` | Optional | WP6 | Hand in-plane tilt angle in degrees relative to camera horizon. |
| `shadowPosture` | `String?` | Optional | WP7 | Static hand posture predicted by Core ML `PostureClassifier` in shadow mode (`none`, `open_palm`, `pinch`, `two_fingers`, `fist`). |
| `shadowAgrees` | `Bool?` | Optional | WP7 | Boolean flag indicating whether `shadowPosture` matched heuristic kinematic classification. |

`*` Note: In JSON encoding, empty strings `""` are used for non-firing frames to guarantee zero decoding ambiguity across Swift and Python decoders.

---

## 2. Canonical Landmark Point Ordering (21 Points)

Points in `primaryPoints` and `secondaryPoints` strictly follow the Apple Vision `VNHumanHandPoseRequest` kinematic joint hierarchy:

| Index | Joint Identifier | Kinematic Group |
| :---: | :--- | :--- |
| `0` | `wrist` | Base / Origin |
| `1`–`4` | `thumbCMC`, `thumbMP`, `thumbIP`, `thumbTip` | Thumb ($P_4$ = tip) |
| `5`–`8` | `indexMCP`, `indexPIP`, `indexDIP`, `indexTip` | Index ($P_8$ = tip) |
| `9`–`12` | `middleMCP`, `middlePIP`, `middleDIP`, `middleTip` | Middle ($P_{12}$ = tip) |
| `13`–`16` | `ringMCP`, `ringPIP`, `ringDIP`, `ringTip` | Ring ($P_{16}$ = tip) |
| `17`–`20` | `littleMCP`, `littlePIP`, `littleDIP`, `littleTip` | Pinky ($P_{20}$ = tip) |

---

## 3. Real Example JSON Line (Copied Verbatim from Fixture)

The following JSON string is copied verbatim from `tools/fixtures/synthetic_face_proximity.jsonl` (line 1), illustrating full field population including `primaryPoints`, 21-element `confidence`, and `faceBBox`:

```json
{"timestamp": 1.0, "frameIndex": 0, "groundTruth": "idle", "predictedIntent": "idle", "firedIntent": "", "firedAction": "", "handDetected": true, "fingerCount": 4, "isPinching": false, "isTwoFingers": false, "isRaisedHand": true, "estimatedDepth": 0.45, "facingCamera": 0.95, "primaryPoints": [{"x": 0.4, "y": 0.3}, {"x": 0.36, "y": 0.35}, {"x": 0.33, "y": 0.38}, {"x": 0.31, "y": 0.41}, {"x": 0.29, "y": 0.43}, {"x": 0.36, "y": 0.4}, {"x": 0.36, "y": 0.45}, {"x": 0.36, "y": 0.49}, {"x": 0.36, "y": 0.53}, {"x": 0.4, "y": 0.4}, {"x": 0.4, "y": 0.46}, {"x": 0.4, "y": 0.5}, {"x": 0.4, "y": 0.55}, {"x": 0.44, "y": 0.4}, {"x": 0.44, "y": 0.45}, {"x": 0.44, "y": 0.49}, {"x": 0.44, "y": 0.53}, {"x": 0.47, "y": 0.38}, {"x": 0.47, "y": 0.43}, {"x": 0.47, "y": 0.46}, {"x": 0.47, "y": 0.49}], "confidence": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0], "faceBBox": {"x": 0.2, "y": 0.2, "width": 0.6, "height": 0.6}}
```
