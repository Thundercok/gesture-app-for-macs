import XCTest
@testable import GestureFlow

final class DatasetRecorderTests: XCTestCase {

    func testDecodeHistoricalJSONLFrameWithoutDesktopContext() throws {
        // Verbatim historical JSON line without desktop_context or research_intent
        let legacyJSON = """
        {"confidence":[1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0,1.0],"estimatedDepth":0.4285,"faceBBox":{"height":0.2,"width":0.15,"x":0.4,"y":0.1},"facingCamera":0.985,"fingerCount":5,"firedAction":"","firedIntent":"","frameIndex":42,"groundTruth":"idle","handCentroid":{"x":0.51,"y":0.62},"handDetected":true,"isInInteractionRange":true,"isPinching":false,"isRaisedHand":true,"isTwoFingers":false,"predictedIntent":"idle","primaryPoints":[{"x":0.5,"y":0.7},{"x":0.52,"y":0.65}],"shadowAgrees":true,"shadowPosture":"open_palm","tiltAngleDegrees":5.2,"timestamp":1794200000.123}
        """

        let data = legacyJSON.data(using: .utf8)!
        let record = try JSONDecoder().decode(HandFrameRecord.self, from: data)

        XCTAssertEqual(record.frameIndex, 42)
        XCTAssertEqual(record.groundTruth, "idle")
        XCTAssertEqual(record.primaryPoints.count, 2)
        XCTAssertEqual(record.shadowPosture, "open_palm")
        XCTAssertNil(record.desktopContext, "Historical records without desktop_context must decode cleanly with nil")
        XCTAssertNil(record.researchIntent, "Historical records without research_intent must decode cleanly with nil")
    }

    func testDecodeNewJSONLFrameWithDesktopContextAndResearchIntent() throws {
        let modernJSON = """
        {
            "timestamp": 1794211200.5,
            "frameIndex": 100,
            "groundTruth": "swipe_left",
            "research_intent": "WORKSPACE_NAVIGATE",
            "predictedIntent": "macNavigation",
            "firedIntent": "macNavigation",
            "firedAction": "swipe_left",
            "handDetected": true,
            "fingerCount": 5,
            "isPinching": false,
            "isTwoFingers": false,
            "isRaisedHand": true,
            "estimatedDepth": 0.45,
            "facingCamera": 0.99,
            "primaryPoints": [{"x": 0.5, "y": 0.5}],
            "desktop_context": {
                "active_app_bundle_id": "com.apple.Safari",
                "app_category": "browser",
                "focused_element_role": "AXWebArea",
                "window_state": "foreground",
                "cursor_position": [0.35, 0.40],
                "timestamp": 1794211200.495,
                "availability": {
                    "active_app": true,
                    "focused_element": true,
                    "cursor_position": true,
                    "window_state": true
                }
            }
        }
        """

        let data = modernJSON.data(using: .utf8)!
        let record = try JSONDecoder().decode(HandFrameRecord.self, from: data)

        XCTAssertEqual(record.frameIndex, 100)
        XCTAssertEqual(record.groundTruth, "swipe_left")
        XCTAssertEqual(record.researchIntent, "WORKSPACE_NAVIGATE")
        XCTAssertNotNil(record.desktopContext)
        XCTAssertEqual(record.desktopContext?.activeAppBundleID, "com.apple.Safari")
        XCTAssertEqual(record.desktopContext?.appCategory, "browser")
        XCTAssertEqual(record.desktopContext?.focusedElementRole, "AXWebArea")
        XCTAssertEqual(record.desktopContext?.cursorPosition, [0.35, 0.40])
        XCTAssertTrue(record.desktopContext?.availability.activeApp ?? false)
    }

    func testRecorderStartStopLifecycleAndFileIntegrity() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session_001.jsonl")
        let recorder = DatasetRecorder()

        // Mock context provider
        let mockProvider = DesktopContextProvider()
        mockProvider.updateSimulatedContext(
            DesktopContextRecord(
                activeAppBundleID: "com.apple.Safari",
                appCategory: "browser",
                focusedElementRole: "AXWebArea",
                windowState: "foreground",
                cursorPosition: [0.5, 0.5],
                timestamp: 1000.0,
                availability: DesktopContextAvailability(activeApp: true, focusedElement: true, cursorPosition: true, windowState: true)
            )
        )
        recorder.setContextProvider(mockProvider)

        XCTAssertFalse(recorder.isRecording)
        let started = recorder.startRecording(toPath: fileURL.path)
        XCTAssertTrue(started)
        XCTAssertTrue(recorder.isRecording)

        recorder.setGroundTruthLabel("swipe_left", researchIntent: .workspaceNavigate)
        XCTAssertEqual(recorder.currentLabel, "swipe_left")
        XCTAssertEqual(recorder.currentResearchIntent, ResearchIntent.workspaceNavigate.rawValue)

        // Record 10 sample frames
        for i in 0..<10 {
            recorder.recordFrame(
                frameIndex: i,
                timestamp: Double(i) * 0.016,
                primary: nil,
                secondary: nil,
                predictedIntent: "idle"
            )
        }

        recorder.stopRecording()
        XCTAssertFalse(recorder.isRecording)

        // Read file contents back and verify each line
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertEqual(lines.count, 10, "All 10 queued frames must be written before stopRecording returns")

        let firstRecord = try JSONDecoder().decode(HandFrameRecord.self, from: lines[0].data(using: .utf8)!)
        XCTAssertEqual(firstRecord.frameIndex, 0)
        XCTAssertEqual(firstRecord.groundTruth, "swipe_left")
        XCTAssertEqual(firstRecord.researchIntent, "WORKSPACE_NAVIGATE")
        XCTAssertEqual(firstRecord.desktopContext?.activeAppBundleID, "com.apple.Safari")
        XCTAssertEqual(firstRecord.desktopContext?.appCategory, "browser")
    }

    func testConcurrentRecordingThreadSafetyStressTest() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("concurrent_test.jsonl")
        let recorder = DatasetRecorder()

        XCTAssertTrue(recorder.startRecording(toPath: fileURL.path))

        let totalFramesPerThread = 50
        let threadCount = 4
        let group = DispatchGroup()

        for t in 0..<threadCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<totalFramesPerThread {
                    let frameIdx = t * 1000 + i
                    if i % 10 == 0 {
                        recorder.setGroundTruthLabel("label_\(t)", researchIntent: .scroll)
                    }
                    recorder.recordFrame(
                        frameIndex: frameIdx,
                        timestamp: Double(frameIdx) * 0.016,
                        primary: nil,
                        secondary: nil,
                        predictedIntent: "idle"
                    )
                }
                group.leave()
            }
        }

        group.wait()
        recorder.stopRecording()

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertEqual(lines.count, threadCount * totalFramesPerThread, "All concurrent frames must be written without dropping or crashing")
    }
}
