# Engineering Findings & Architectural Divergences

This document records architectural, mathematical, and pipeline divergences discovered during automated audit and parity verification. Per project protocol, these items are documented and reported rather than unilaterally altered without user alignment.

---

## Finding F1: Posture Feature Normalization Input Domain (Filtered vs. Raw)

- **Date**: 2026-10-19
- **Component**: `PostureClassifier.extractFeatures` (`GestureFlowApp/Sources/GestureFlow/Tracking/PostureClassifier.swift`) vs. `tools/export_features.py`
- **Discovered In**: WP17 (Swift↔Python Feature Parity Audit)
- **Status**: **RESOLVED — Option 1 Implemented (2026-10-19)**

### Problem Description
1. **Mathematical Parity Confirmed**:
   - The 56-D canonical feature normalization algorithm (wrist origin translation, Y-axis inversion, middleMCP scale normalization, rotation to vertical +Y, mirroring reflection for left hands, and 14 engineered metrics) is in **100% bit-level parity** between Swift and Python:
     $$\max |f_{\text{Swift}} - f_{\text{Python}}| = 1.00 \times 10^{-6}$$
     when evaluated on identical landmark point inputs.
2. **Domain Mismatch in Live Pipeline**:
   - In Python (`tools/export_features.py`), features were originally extracted directly from `frame["primaryPoints"]`, which are raw, unsmoothed detection coordinates from the Vision framework.
   - In the Swift runtime (`Pipeline.swift`, `ReplayRunner.swift`, and `PostureClassifier.predict`), `HandFeatureExtractor.landmarks(...)` passes raw coordinates through:
     - `KinematicHandLimiter.clampPoints(points)` (enforcing anthropometric bone length ratios relative to palm span).
     - `SkeletonFilter` (`PointFilter2D` OneEuro temporal smoothing with adaptive cutoffs).
     - The output is stored in `HandLandmarks.points`.
   - `PostureClassifier.extractFeatures(from: landmarks)` consumes `landmarks.points`.
   - Because `landmarks.points` has been smoothed and kinematically limited, dynamic frames in video recordings exhibited differences of up to $\approx 0.12$ between offline training features (raw) and online inference features (filtered).

### Resolution & Implementation (Option 1)
- **User Decision**: Selected **Option 1 (Train offline on filtered coordinates via Swift `--dump-features` to match runtime distribution)**.
- **Implementation**:
  - `GestureFlowApp` provides `--dump-features <input.jsonl> --out <features.csv>` in `FeatureDumper.swift` and `main.swift`, which runs the exact `KinematicHandLimiter` and `OneEuroFilter` pipeline as live inference.
  - `tools/export_features.py` was extended with `--use-swift-pipeline` (and `--swift-binary`), allowing multi-session dataset feature exports to automatically delegate extraction to the Swift binary.
  - Automated unit test `test_export_features_with_swift_pipeline` added to `tools/test_export_features.py`.
  - Offline model training data now identically matches online inference feature distributions with zero domain shift before promotion to live gating.
