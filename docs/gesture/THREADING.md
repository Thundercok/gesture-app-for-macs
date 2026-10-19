# GestureFlow Threading & Concurrency Audit (B4)

## Overview & Architecture

GestureFlow operates across four primary concurrency contexts:

1. **Main Thread (`DispatchQueue.main`)**:
   - SwiftUI View rendering (`HUDView`, `ApplicationSwitcherView`, `HolographicSkeletonView`).
   - AppKit NSMenu and NSStatusItem interactions (`MenuBar.swift`).
   - `AppState` updates via `@Published` properties observed by SwiftUI.
   - NSPanel presentation and positioning (`dockPanel`).
   - Calibration wizard timer ticks and UI callbacks.

2. **Camera Processing Queue (`com.gestureflow.camera`, QoS `.userInteractive`)**:
   - `AVCaptureVideoDataOutputSampleBufferDelegate.captureOutput` delivery.
   - CoreVideo pixel buffer extraction.
   - Apple Vision multi-hand landmark detection (`HandTracker.processMultiHand`).
   - Feature calculation (`HandFeatureExtractor.landmarks`).
   - Kinematic evaluation in `GestureEngine.process` and `ScrollEngine.process`.
   - Ring-buffer ingestion in `IncidentRecorder.shared.ingest`.
   - Dataset frame recording in `DatasetRecorder.shared.recordFrame`.

3. **Incident Disk I/O Queue (`com.gestureflow.incidents`, QoS `.utility`)**:
   - Async serialization of `IncidentHeader` and `HandFrameRecord` snapshots to JSONL on disk.

4. **Global Event Monitor Queue (macOS WindowServer / `NSEvent`)**:
   - Delivery of global keydown events for incident tagging (⌃⌥⌘M / ⌃⌥⌘N) and dataset labeling (`0`–`8`).

---

## Detailed Closure & Callback Audit Table

| Source Location | Callback / Closure | Calling Thread | Target Thread | Shared State Read / Written | Synchronization Mechanism |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `Pipeline.swift:5` | `tracker.onClapDetected` | `com.gestureflow.camera` | `com.gestureflow.camera` | None (`_ = self`, detector disabled) | Disabled |
| `Pipeline.swift:11` | `scrollEngine.onAction` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.latestAction` (W) | Dispatched to Main via `AppState.setAction` |
| `Pipeline.swift:15` | `scrollEngine.onScrollStatus` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.isAirScrollActive`, `airScrollClutch`, `airScrollVelocity` (W) | `DispatchQueue.main.async` |
| `Pipeline.swift:23` | `scrollEngine.onScrollDelta` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.airScrollDeltaY`, `airScrollVelocity` (W) | `DispatchQueue.main.async` |
| `Pipeline.swift:30` | `scrollEngine.onSuppressStatus` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.activeSuppressReason` (W) | `DispatchQueue.main.async` |
| `Pipeline.swift:36` | `engine.onAction` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.latestAction` (W) | Dispatched to Main via `AppState.setAction` |
| `Pipeline.swift:40` | `engine.onScanProgress` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.scanProgress` (W) | `DispatchQueue.main.async` |
| `Pipeline.swift:47` | `engine.onArmedStatus` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.isArmed` (W) | `DispatchQueue.main.async` |
| `Pipeline.swift:53` | `engine.onDockOpen` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.dockApps`, `selectedDockIndex`, `dragDelta`, `isDockOpen` (W); `dockPanel` (W) | `DispatchQueue.main.async` |
| `Pipeline.swift:65` | `engine.onSuppressStatus` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.activeSuppressReason` (W) | `DispatchQueue.main.async` |
| `Pipeline.swift:71` | `engine.onRejectReason` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.lastRejectReason` (W) | Dispatched to Main via `AppState.setRejectReason` |
| `Pipeline.swift:75` | `engine.onDockSelectIndex` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.selectedDockIndex` (R/W), `dragDelta` (W) | `DispatchQueue.main.async` |
| `Pipeline.swift:88` | `engine.onDockCommit` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.selectedDockIndex`, `dockApps` (R); `isDockOpen` (W); `dockPanel` (W) | `DispatchQueue.main.async` |
| `Pipeline.swift:103` | `engine.onDockCancel` | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.isDockOpen` (W); `dockPanel` (W) | `DispatchQueue.main.async` |
| `Pipeline.swift:111` | `cameraManager.onFrame` | `com.gestureflow.camera` | `com.gestureflow.camera` | `self.frameCount`, `fpsTimer`, `previousBimanualSpan`, `cumulativeBimanualScale`, `lastRecordedCommitSequence`, `lastHandSeenTime` (R/W) | Confined to camera serial queue |
| `Pipeline.swift:122` | `cameraManager.onFrame` (FPS tick) | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.fps`, `isAccessibilityTrusted` (W) | `DispatchQueue.main.async` |
| `Pipeline.swift:137,144,147,158` | Mode Routing Check | `com.gestureflow.camera` | `com.gestureflow.camera` | `AppState.currentMode` (R) | **Audit Finding B4**: Cross-thread read of `@Published` property without lock. Resolved via `CurrentModeBox`. |
| `Pipeline.swift:246` | UI Landmark Broadcast | `com.gestureflow.camera` | Main (`DispatchQueue.main`) | `AppState.currentFrame`, `currentLandmarks`, `handDetected`, `fingerCount`, `estimatedDepth`, `facingCamera`, etc. (W) | `DispatchQueue.main.async` |
| `KeyboardMonitors.swift:6` | `NSEvent.addGlobalMonitorForEvents` | WindowServer event thread | Main (`DispatchQueue.main`) | `DatasetRecorder.shared.isRecording`, `currentLabel` (R/W); `AppState.datasetLabel` (W) | `DispatchQueue.main.async` |
| `KeyboardMonitors.swift:39` | `NSEvent.addLocalMonitorForEvents` | Main Thread | Main Thread | `DatasetRecorder.shared.isRecording`, `currentLabel` (R/W); `AppState.datasetLabel` (W) | Dispatched on Main Thread |
| `CalibrationWizard.swift:58` | `ingest(landmarks:timestamp:)` | `com.gestureflow.camera` | `com.gestureflow.camera` | `peakVelocityTracker`, `peakDisplacementTracker` (W) | Protected by `NSLock` |
| `CalibrationWizard.swift:123` | `onTimerTick()` | Main (Timer run loop) | Main Thread | `stepCountdown`, `currentStep`, `previousTuningBeforeCalibration` (R/W) | Protected by `NSLock`, UI callbacks on Main |
| `IncidentRecorder.swift:59` | `ingest(frame:)` | `com.gestureflow.camera` | `com.gestureflow.camera` | `frameBuffer`, `pendingAutoFires`, `lastQuietTime` (R/W) | Protected by `NSLock` |
| `IncidentRecorder.swift:118` | `dumpFrames(...)` | Caller thread | `com.gestureflow.incidents` | Disk file I/O | Dispatched asynchronously to private serial queue |
| `ScrollEngine.swift:87` | `actionSink.onMomentumProgress` | DisplayLink thread / Main | `com.gestureflow.camera` / Main | `liveMomentumVelocity` (W); `onScrollStatus`, `onScrollDelta` (invoked) | Confined to ActionSink lifecycle |
| `ScrollEngine.swift:94` | `actionSink.onMomentumEnded` | DisplayLink thread / Main | `com.gestureflow.camera` / Main | `liveMomentumVelocity = 0.0` (W); `onScrollStatus`, `onScrollDelta` (invoked) | Confined to ActionSink lifecycle |

---

## Resolved Vulnerabilities & Mitigations

### 1. Cross-thread read of `AppState.currentMode` (B4)
- **Problem**: In `Pipeline.swift` lines 137, 144, 147, and 158, the camera processing thread (`com.gestureflow.camera`) directly read `self.appState.currentMode`. `AppState` is an `ObservableObject` published on the Main thread. Reading an `@Published` property across threads without memory barriers or synchronization violates thread-safety and causes race conditions with mode hotkeys (`Cmd+1/2/3`).
- **Mitigation**: Added `CurrentModeBox`:
  ```swift
  final class CurrentModeBox: @unchecked Sendable {
      private let lock = NSLock()
      private var _mode: SystemMode = .airScroll

      var mode: SystemMode {
          get { lock.lock(); defer { lock.unlock() }; return _mode }
          set { lock.lock(); _mode = newValue; lock.unlock() }
      }
  }
  ```
  `AppState.currentModeBox` is updated inside `AppState.currentMode.didSet` on the Main thread, and safely read via lock synchronization on the camera thread in `Pipeline.swift`.
