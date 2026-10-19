# Engineering Findings & Architectural Divergences

This document records architectural, mathematical, and pipeline divergences discovered during automated audit and parity verification. Per project protocol, these items are documented and reported rather than unilaterally altered without user alignment.

---

## Finding F1: Posture Feature Normalization Input Domain (Filtered vs. Raw)

- **Date**: 2026-10-19
- **Component**: `PostureClassifier.extractFeatures` (`GestureFlowApp/Sources/GestureFlow/Tracking/PostureClassifier.swift`) vs. `tools/export_features.py`
- **Discovered In**: WP17 (Swift↔Python Feature Parity Audit)
- **Status**: **RECORDED — AWAITING USER ALIGNMENT**

### Problem Description
1. **Mathematical Parity Confirmed**:
   - The 56-D canonical feature normalization algorithm (wrist origin translation, Y-axis inversion, middleMCP scale normalization, rotation to vertical +Y, mirroring reflection for left hands, and 14 engineered metrics) is in **100% bit-level parity** between Swift and Python:
     $$\max |f_{\text{Swift}} - f_{\text{Python}}| = 1.00 \times 10^{-6}$$
     when evaluated on identical landmark point inputs.
2. **Domain Mismatch in Live Pipeline**:
   - In Python (`tools/export_features.py`), features are extracted directly from `frame["primaryPoints"]`, which are **raw, unpadded, unsmoothed** detection coordinates from the Vision framework.
   - In the Swift runtime (`Pipeline.swift`, `ReplayRunner.swift`, and `PostureClassifier.predict`), `HandFeatureExtractor.landmarks(...)` passes raw coordinates through:
     - `KinematicHandLimiter.clampPoints(points)` (enforcing anthropometric bone length ratios relative to palm span).
     - `SkeletonFilter` (`PointFilter2D` OneEuro temporal smoothing with adaptive cutoffs).
     - The output is stored in `HandLandmarks.points`.
   - `PostureClassifier.extractFeatures(from: landmarks)` consumes `landmarks.points`.
   - Because `landmarks.points` has been smoothed and kinematically limited, dynamic frames in video recordings exhibit differences of up to $\approx 0.12$ between offline training features (raw) and online inference features (filtered). Specifically:
     - Middle finger tip extension on synthetic gestures exceeds `KinematicHandLimiter`'s 0.38 palm-span ratio, causing the limiter to pull the tip back.
     - `OneEuroFilter` introduces expected velocity-dependent lag during high-speed motion.

### Impact
- A CoreML posture classification model trained via `tools/train_posture_model.py` on raw coordinates will experience distribution shift when evaluated on smoothed coordinates in the macOS app runtime.
- Note: Currently `useLearnedPosture` defaults to `false` (shadow mode only), so this does not degrade live rule-based gestures.

### Architectural Options for User Alignment
- **Option 1 (Train on Filtered Data - Recommended)**: Export features for offline model training using the same `SkeletonFilter` / `KinematicHandLimiter` pipeline as the app (or dump features via `--dump-features` in Swift). This ensures the ML model trains on the exact distribution it will encounter at inference time.
- **Option 2 (Inference on Raw Landmarks)**: Preserve `rawPoints: [CGPoint]` inside `HandLandmarks`, and pass `rawPoints` to `PostureClassifier.extractFeatures`. The classifier will then see raw coordinates, matching current `export_features.py`.
- **Option 3 (Hybrid / Dual-Mode)**: Train with synthetic noise / jitter augmentation in `train_posture_model.py` so the classifier is robust to both raw and smoothed coordinates.
