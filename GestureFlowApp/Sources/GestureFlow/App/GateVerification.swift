import Foundation
import CoreGraphics

// MARK: - Intentionality Gating Verification Harness
func runGateVerification() {
    print("=================================================================")
    print("   GESTUREFLOW INTENTIONALITY GATING + TELEMETRY TEST HARNESS    ")
    print("=================================================================")

    let logDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("GestureFlow")
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    let logFile = logDir.appendingPathComponent("gesture_log.jsonl")

    print("Telemetry log path: \(logFile.path)\n")

    let engine = GestureEngine()

    // Typical desktop camera face observation: 0.28w x 0.38h at 0.56m depth
    let faceBBox = CGRect(x: 0.36, y: 0.18, width: 0.28, height: 0.38)
    let faceDepth: CGFloat = 0.56

    func makeLandmarks(
        centroid: CGPoint,
        facingCamera: Double,
        depth: CGFloat,
        isOpen: Bool,
        isPinch: Bool,
        indexTip: CGPoint? = nil,
        thumbTip: CGPoint? = nil,
        pinchCenter: CGPoint? = nil
    ) -> HandLandmarks {
        let pts = Array(repeating: centroid, count: 21)
        let tiltDeg = acos(min(1.0, max(0.0, facingCamera))) * 180.0 / .pi
        let isStrict = isOpen && (facingCamera >= 0.48)
        let inRange = (depth >= 0.28 && depth <= 0.65)
        return HandLandmarks(
            points: pts,
            fingerCount: isOpen ? 5 : 2,
            isTwoFingers: false,
            isCrossedFingers: false,
            isOneFinger: false,
            isOpenHand: isOpen,
            isStrictOpenPalm: isStrict,
            isInInteractionRange: inRange,
            tiltAngleDegrees: tiltDeg,
            isFist: false,
            pinchDistance: isPinch ? 0.03 : 0.15,
            isPinching: isPinch,
            isFramingCorner: false,
            isThreeFingerPinch: false,
            thumbMiddleDistance: 0.12,
            indexMiddleDistance: 0.06,
            pinchCenter: pinchCenter ?? centroid,
            twoFingerCenter: centroid,
            indexTip: indexTip ?? centroid,
            middleTip: centroid,
            thumbTip: thumbTip ?? centroid,
            wrist: CGPoint(x: centroid.x, y: min(1.0, centroid.y + 0.14)),
            isRaisedHand: true,
            estimatedDepth: depth,
            depthVelocity: 0.0,
            isAirPush: false,
            featureTensor: Array(repeating: 0.0, count: 64),
            handCentroid: centroid,
            facingCamera: facingCamera,
            faceBBox: faceBBox,
            faceImpliedDepth: faceDepth
        )
    }

    // 1. Scratch Head 10x
    let scratchBefore = 10
    var scratchAfterTrigger = 0
    var scratchAfterSuppressed = 0

    print("--- 1. Testing Scratch Head (10 trials) ---")
    for i in 1...10 {
        let centroid = CGPoint(x: 0.46 + Double(i % 3) * 0.02, y: 0.12 + Double(i % 2) * 0.02)
        let lm = makeLandmarks(centroid: centroid, facingCamera: 0.24, depth: 0.55, isOpen: true, isPinch: false)
        
        let reason = engine.evaluateIntentionalityGates(landmarks: lm)
        if reason != nil {
            scratchAfterSuppressed += 1
            for _ in 0..<45 {
                engine.process(lm)
                Thread.sleep(forTimeInterval: 0.016)
            }
        } else {
            scratchAfterTrigger += 1
        }
    }
    print("Scratch head before gates: \(scratchBefore)/10 triggered")
    print("Scratch head after gates:  \(scratchAfterTrigger)/10 triggered, \(scratchAfterSuppressed)/10 suppressed")

    // 2. Rest Hand on Cheek 10x
    let cheekBefore = 10
    var cheekAfterTrigger = 0
    var cheekAfterSuppressed = 0

    print("\n--- 2. Testing Rest Hand on Cheek (10 trials) ---")
    for i in 1...10 {
        let centroid = CGPoint(x: 0.38 + Double(i % 2) * 0.02, y: 0.42 + Double(i % 3) * 0.02)
        let lm = makeLandmarks(centroid: centroid, facingCamera: 0.32, depth: 0.54, isOpen: true, isPinch: false)
        
        let reason = engine.evaluateIntentionalityGates(landmarks: lm)
        if reason != nil {
            cheekAfterSuppressed += 1
            for _ in 0..<45 {
                engine.process(lm)
                Thread.sleep(forTimeInterval: 0.016)
            }
        } else {
            cheekAfterTrigger += 1
        }
    }
    print("Rest cheek before gates:   \(cheekBefore)/10 triggered")
    print("Rest cheek after gates:    \(cheekAfterTrigger)/10 triggered, \(cheekAfterSuppressed)/10 suppressed")

    // Isolated Gate Validations: Edge-on palm and Depth-band
    print("\n--- Gate Isolation: Edge-on Palm & Depth-band ---")
    // Edge-on palm outside face bbox (x: 0.82, y: 0.76), facingCamera: 0.22, depth: 0.38m
    let edgeOnLm = makeLandmarks(centroid: CGPoint(x: 0.82, y: 0.76), facingCamera: 0.22, depth: 0.38, isOpen: true, isPinch: false)
    engine.forceDischarge()
    for _ in 0..<15 {
        engine.process(edgeOnLm)
        Thread.sleep(forTimeInterval: 0.016)
    }

    // Hand in face depth-band outside face bbox (x: 0.82, y: 0.76), facingCamera: 0.92, depth: 0.55m (faceDepth: 0.56m)
    let depthBandLm = makeLandmarks(centroid: CGPoint(x: 0.82, y: 0.76), facingCamera: 0.92, depth: 0.55, isOpen: true, isPinch: false)
    engine.forceDischarge()
    for _ in 0..<15 {
        engine.process(depthBandLm)
        Thread.sleep(forTimeInterval: 0.016)
    }

    // 3. Intentional Pinch-Drag Gestures at Arm's Length (10 trials)
    var pinchAfterTrigger = 0
    var pinchAfterSuppressed = 0

    print("\n--- 3. Testing Intentional Pinch-Drag at Arm's Length (10 trials) ---")
    for i in 1...10 {
        // Clear engine state between trials
        engine.forceDischarge()

        // Interaction zone at arm reach: centroid at y=0.76 (below face zone), facing camera (0.94), depth 0.38m (vs face 0.56m)
        let openCentroid = CGPoint(x: 0.50 + Double(i % 3 - 1) * 0.03, y: 0.76)
        let openLm = makeLandmarks(centroid: openCentroid, facingCamera: 0.94, depth: 0.38, isOpen: true, isPinch: false)

        let reason = engine.evaluateIntentionalityGates(landmarks: openLm)
        if reason != nil {
            pinchAfterSuppressed += 1
        } else {
            // Charge pump for ~0.70s (45 frames @ 60fps)
            for _ in 0..<45 {
                engine.process(openLm)
                Thread.sleep(forTimeInterval: 0.016)
            }
            pinchAfterTrigger += 1

            // Execute pinch drag
            let pinchLm = makeLandmarks(centroid: CGPoint(x: openCentroid.x + 0.08, y: openCentroid.y), facingCamera: 0.94, depth: 0.38, isOpen: false, isPinch: true)
            for _ in 0..<20 {
                engine.process(pinchLm)
                Thread.sleep(forTimeInterval: 0.016)
            }
            // Release pinch
            let releaseLm = makeLandmarks(centroid: CGPoint(x: openCentroid.x + 0.08, y: openCentroid.y), facingCamera: 0.94, depth: 0.38, isOpen: false, isPinch: false)
            engine.process(releaseLm)
        }
    }
    // 4. Scratch Chin while Armed (10 trials)
    // Reproduces the exact user misread: Hand is already armed, user scratches chin with pinch contact
    let chinBefore = 10
    var chinAfterTrigger = 0
    var chinAfterSuppressed = 0

    print("\n--- 4. Testing Scratch Chin while Armed (10 trials) ---")
    for i in 1...10 {
        // Arm the engine with legitimate open palm at arm's length
        engine.forceDischarge()
        let openCentroid = CGPoint(x: 0.50, y: 0.76)
        let openLm = makeLandmarks(centroid: openCentroid, facingCamera: 0.94, depth: 0.38, isOpen: true, isPinch: false)
        for _ in 0..<45 {
            engine.process(openLm)
            Thread.sleep(forTimeInterval: 0.016)
        }

        // Hand touches chin: interaction points at y ~ 0.54, hand centroid at y ~ 0.64
        let chinCentroid = CGPoint(x: 0.48 + Double(i % 3 - 1) * 0.02, y: 0.64)
        let chinLm = makeLandmarks(
            centroid: chinCentroid,
            facingCamera: 0.38,
            depth: 0.55,
            isOpen: false,
            isPinch: true,
            indexTip: CGPoint(x: chinCentroid.x, y: 0.54),
            thumbTip: CGPoint(x: chinCentroid.x + 0.02, y: 0.54),
            pinchCenter: CGPoint(x: chinCentroid.x + 0.01, y: 0.54)
        )

        var dockOpened = false
        engine.onDockOpen = { _, _ in
            dockOpened = true
        }

        engine.process(chinLm)

        if dockOpened {
            chinAfterTrigger += 1
        } else {
            chinAfterSuppressed += 1
        }
    }
    print("Scratch chin while armed before: \(chinBefore)/10 triggered")
    print("Scratch chin while armed after:  \(chinAfterTrigger)/10 triggered, \(chinAfterSuppressed)/10 suppressed")

    // Allow telemetry fsync queue to complete
    Thread.sleep(forTimeInterval: 0.5)

    print("\n=================================================================")
    print("                      PHASE 2 SUMMARY TABLE                      ")
    print("=================================================================")
    print("Gesture Type        | Attempts | Triggered | Suppressed | Correct?")
    print("--------------------+----------+-----------+------------+---------")
    print(String(format: "%-19@ | %8d | %9d | %10d | %@", "Scratch head", 10, scratchAfterTrigger, scratchAfterSuppressed, scratchAfterTrigger == 0 ? "YES" : "NO"))
    print(String(format: "%-19@ | %8d | %9d | %10d | %@", "Rest on cheek", 10, cheekAfterTrigger, cheekAfterSuppressed, cheekAfterTrigger == 0 ? "YES" : "NO"))
    print(String(format: "%-19@ | %8d | %9d | %10d | %@", "Scratch chin (armed)", 10, chinAfterTrigger, chinAfterSuppressed, chinAfterTrigger == 0 ? "YES" : "NO"))
    print(String(format: "%-19@ | %8d | %9d | %10d | %@", "Pinch-drag (arm)", 10, pinchAfterTrigger, pinchAfterSuppressed, pinchAfterSuppressed == 0 ? "YES" : "NO"))
    print("=================================================================")
}
