import AppKit

extension AppDelegate {
    func setupPipeline() {
        tracker.onClapDetected = { [weak self] in
            // Disabled: Clap detector was causing accidental mode switches whenever hands entered/left the camera frame.
            // Modes must be chosen explicitly via Cmd+1/Cmd+2/Cmd+3 or the Menu Bar.
            _ = self
        }

        scrollEngine.onAction = { [weak self] actionTitle in
            self?.appState.setAction(actionTitle)
        }

        scrollEngine.onScrollStatus = { [weak self] isScrolling, clutch, velocityY in
            DispatchQueue.main.async {
                self?.appState.isAirScrollActive = isScrolling
                self?.appState.airScrollClutch = clutch?.rawValue
                self?.appState.airScrollVelocity = velocityY
            }
        }

        scrollEngine.onScrollDelta = { [weak self] deltaY, velocityY in
            DispatchQueue.main.async {
                self?.appState.airScrollDeltaY = deltaY
                self?.appState.airScrollVelocity = velocityY
            }
        }

        scrollEngine.onSuppressStatus = { [weak self] reason in
            DispatchQueue.main.async {
                self?.appState.activeSuppressReason = reason?.rawValue
            }
        }

        engine.onAction = { [weak self] actionTitle in
            self?.appState.setAction(actionTitle)
        }

        engine.onScanProgress = { [weak self] progress in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.appState.scanProgress = progress
            }
        }

        engine.onArmedStatus = { [weak self] isArmed in
            DispatchQueue.main.async {
                self?.appState.isArmed = isArmed
            }
        }

        engine.onDockOpen = { [weak self] apps, initialIndex in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.appState.dockApps = apps
                self.appState.selectedDockIndex = min(initialIndex, max(0, apps.count - 1))
                self.appState.dragDelta = .zero
                self.appState.isDockOpen = true
                self.dockPanel?.ignoresMouseEvents = false
                self.dockPanel?.orderFrontRegardless()
            }
        }

        engine.onSuppressStatus = { [weak self] reason in
            DispatchQueue.main.async {
                self?.appState.activeSuppressReason = reason?.rawValue
            }
        }

        engine.onRejectReason = { [weak self] reason in
            self?.appState.setRejectReason(reason)
        }

        engine.onDockSelectIndex = { [weak self] index, delta in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if self.appState.selectedDockIndex != index {
                    // Tactile Force Touch Haptic Detent on app snap
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    ActionDispatcher.playFeedback(named: "Tink")
                }
                self.appState.selectedDockIndex = index
                self.appState.dragDelta = delta
            }
        }

        engine.onDockCommit = { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let idx = self.appState.selectedDockIndex
                let apps = self.appState.dockApps
                self.dockPanel?.ignoresMouseEvents = true
                self.dockPanel?.orderOut(nil)
                self.appState.isDockOpen = false
                if idx >= 0 && idx < apps.count {
                    let target = apps[idx]
                    ActionDispatcher.activate(app: target)
                }
            }
        }

        engine.onDockCancel = { [weak self] in
            DispatchQueue.main.async {
                self?.appState.isDockOpen = false
                self?.dockPanel?.ignoresMouseEvents = true
                self?.dockPanel?.orderOut(nil)
            }
        }

        cameraManager.onFrame = { [weak self] pixelBuffer, image, aspectRatio, pts in
            guard let self = self else { return }

            self.frameCount += 1
            let now = Date()
            if self.frameCount >= 20 {
                let dt = now.timeIntervalSince(self.fpsTimer)
                let currentFPS = Int(Double(self.frameCount) / max(0.001, dt))
                self.frameCount = 0
                self.fpsTimer = now
                let trusted = AXIsProcessTrusted()
                DispatchQueue.main.async {
                    self.appState.fps = currentFPS
                    self.appState.isAccessibilityTrusted = trusted
                }
            }

            let multiHand = self.tracker.processMultiHand(pixelBuffer, pts: pts)
            let landmarks = multiHand?.primary
            let secondaryLandmarks = multiHand?.secondary

            if CalibrationWizard.shared.isRunning {
                CalibrationWizard.shared.ingest(landmarks: landmarks, timestamp: pts.seconds)
            }

            // Route to active system mode engine:
            if self.appState.currentMode == .airScroll {
                self.engine.forceDischarge()
                if secondaryLandmarks != nil {
                    self.scrollEngine.forceDischarge()
                } else {
                    self.scrollEngine.process(landmarks)
                }
            } else if self.appState.currentMode == .macNavigation {
                self.scrollEngine.forceDischarge()
                self.engine.process(landmarks)
            } else if self.appState.currentMode == .spatialZoom {
                self.scrollEngine.forceDischarge()
                self.engine.forceDischarge()
            }

            // Bimanual Spatial Zoom Engine (Active in Spatial Zoom Mode)
            var bimanualSpan: CGFloat = 0.0
            var bimanualZoom: Int = 100
            var isBimanual = false
            var isClutched = false

            if self.appState.currentMode == .spatialZoom, let p = landmarks, let s = secondaryLandmarks {
                let dx = p.handCentroid.x - s.handCentroid.x
                let dy = p.handCentroid.y - s.handCentroid.y
                let normSpan = hypot(dx, dy)
                let avgZ = (p.estimatedDepth + s.estimatedDepth) / 2.0
                let metricDist = normSpan * avgZ * (1.0 / MonocularDepthEstimator.normalizedFocalLength)

                // Natural Two-Hand Zoom: Hands must be separated (> 8cm).
                let canZoom = IntentArbiter.shared.canBegin(intent: .spatialZoom)
                if metricDist > 0.08 && p.isRaisedHand && s.isRaisedHand && canZoom {
                    IntentArbiter.shared.claim(intent: .spatialZoom)
                    bimanualSpan = metricDist
                    isBimanual = true
                    isClutched = true

                    if self.previousBimanualSpan > 0.08 {
                        let spanDelta = metricDist - self.previousBimanualSpan
                        // Proportional magnification: 10cm motion ≈ 28% magnification
                        let magDelta = spanDelta * 2.8
                        if abs(magDelta) > 0.0020 {
                            ActionDispatcher.magnify(delta: magDelta)
                        }

                        self.cumulativeBimanualScale = max(0.25, min(4.0, self.cumulativeBimanualScale + magDelta))
                        bimanualZoom = Int((self.cumulativeBimanualScale * 100.0).rounded())
                    } else {
                        // Clutch just engaged: anchor span without jump
                        bimanualZoom = Int((self.cumulativeBimanualScale * 100.0).rounded())
                    }
                    self.previousBimanualSpan = metricDist
                } else {
                    IntentArbiter.shared.release(intent: .spatialZoom)
                    self.previousBimanualSpan = 0.0
                }
            } else {
                IntentArbiter.shared.release(intent: .spatialZoom)
                self.previousBimanualSpan = 0.0
            }

            let seq = IntentArbiter.shared.commitSequence
            let fired: String = (seq != self.lastRecordedCommitSequence) ? IntentArbiter.shared.lastCommitted.rawValue : ""
            let firedAction: String = (seq != self.lastRecordedCommitSequence) ? IntentArbiter.shared.lastCommittedActionName : ""
            if seq != self.lastRecordedCommitSequence {
                self.lastRecordedCommitSequence = seq
                IncidentRecorder.shared.markAutoFire(intent: fired)
            }

            let heuristicPosture = PostureClassifier.deriveHeuristicPosture(from: landmarks)
            let (shadowPosture, shadowAgrees) = PostureClassifier.shared.evaluateShadow(landmarks: landmarks, heuristicPosture: heuristicPosture)

            let frameRec = makeFrameRecord(
                frameIndex: self.frameCount,
                timestamp: pts.seconds,
                primary: landmarks,
                secondary: secondaryLandmarks,
                predictedIntent: IntentArbiter.shared.currentIntent.rawValue,
                firedIntent: fired,
                firedAction: firedAction,
                groundTruth: DatasetRecorder.shared.currentLabel,
                shadowPosture: shadowPosture,
                shadowAgrees: shadowAgrees
            )

            if DatasetRecorder.shared.isRecording {
                DatasetRecorder.shared.recordFrame(
                    frameIndex: self.frameCount,
                    timestamp: pts.seconds,
                    primary: landmarks,
                    secondary: secondaryLandmarks,
                    predictedIntent: IntentArbiter.shared.currentIntent.rawValue,
                    firedIntent: fired,
                    firedAction: firedAction
                )
            }

            IncidentRecorder.shared.ingest(frame: frameRec)

            // Smart Power Management: 15 FPS when idle (>2.0s without hand), 60 FPS instant wake-up
            if landmarks != nil {
                self.lastHandSeenTime = now
                if self.cameraManager.isThrottled {
                    self.cameraManager.isThrottled = false // Instant 1-frame wake-up
                }
            } else if now.timeIntervalSince(self.lastHandSeenTime) > 2.0 && !self.cameraManager.isThrottled {
                self.cameraManager.isThrottled = true // Throttle to 15 FPS
            }

            DispatchQueue.main.async {
                self.appState.currentFrame = image
                self.appState.cameraAspectRatio = aspectRatio
                self.appState.currentLandmarks = landmarks
                self.appState.secondaryLandmarks = secondaryLandmarks
                self.appState.bimanualSpanMeters = bimanualSpan
                self.appState.bimanualZoomPercent = bimanualZoom
                self.appState.isBimanualActive = isBimanual
                self.appState.isDualPinchClutched = isClutched
                self.appState.isFramingZoomActive = isClutched
                self.appState.handDetected = (landmarks != nil)
                self.appState.fingerCount = landmarks?.fingerCount ?? 0
                self.appState.isTwoFingers = landmarks?.isTwoFingers ?? false
                self.appState.isCrossed = landmarks?.isCrossedFingers ?? false
                self.appState.isPinching = landmarks?.isPinching ?? false
                self.appState.estimatedDepth = landmarks?.estimatedDepth ?? 0.0
                self.appState.facingCamera = landmarks?.facingCamera ?? 1.0
                if let lm = landmarks {
                    if self.appState.currentMode == .airScroll {
                        self.appState.gesturePoint = lm.isTwoFingers ? lm.twoFingerCenter : (lm.isPinching ? lm.pinchCenter : CGPoint(x: 1.0 - lm.indexTip.x, y: lm.indexTip.y))
                    } else if self.appState.currentMode == .macNavigation {
                        self.appState.gesturePoint = lm.isPinching ? lm.pinchCenter : CGPoint(x: 1.0 - lm.indexTip.x, y: lm.indexTip.y)
                    } else {
                        self.appState.gesturePoint = lm.pinchCenter
                    }
                }

                // Strict deliberate gesture gating:
                // Overlay ONLY appears when hand is intentionally held in flat palm pose, pinching, or mode in range,
                // or during active charging/armed/switcher dock open/mode transition banner/bimanual active/air scroll active.
                // It NEVER pops up intrusively while resting arm on desk watching videos!
                let isDeliberateGesture = (landmarks != nil && (landmarks!.isStrictOpenPalm || landmarks!.isPinching || (self.appState.currentMode == .airScroll && landmarks!.isTwoFingers) || self.appState.scanProgress > 0.0) && landmarks!.isInInteractionRange)
                let shouldShowOverlay = isDeliberateGesture || self.appState.scanProgress > 0.0 || self.appState.isArmed || self.appState.isDockOpen || self.appState.isModeBannerVisible || isBimanual || self.appState.isAirScrollActive

                if shouldShowOverlay {
                    self.dockPanel?.ignoresMouseEvents = !self.appState.isDockOpen
                    if self.dockPanel?.isVisible == false {
                        self.dockPanel?.orderFrontRegardless()
                    }
                } else {
                    if self.dockPanel?.isVisible == true {
                        self.dockPanel?.orderOut(nil)
                    }
                }
            }
        }

        cameraManager.start()
    }
}
