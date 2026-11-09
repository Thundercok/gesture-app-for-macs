import XCTest
@testable import GestureFlow

final class DesktopContextProviderTests: XCTestCase {

    func testAppCategoryClassification() {
        // Browsers
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.apple.Safari"), .browser)
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.google.Chrome"), .browser)
        XCTAssertEqual(AppCategory.categorize(bundleID: "org.mozilla.firefox"), .browser)
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.brave.Browser"), .browser)
        XCTAssertEqual(AppCategory.categorize(bundleID: "company.thebrowser.Browser"), .browser)

        // Code Editors & IDEs
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.microsoft.VSCode"), .codeEditor)
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.apple.dt.Xcode"), .codeEditor)
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.jetbrains.intellij"), .codeEditor)
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.sublimetext.4"), .codeEditor)

        // File Managers
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.apple.finder"), .fileManager)

        // Communication
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.tinyspeck.slackmacgap"), .communication)
        XCTAssertEqual(AppCategory.categorize(bundleID: "ru.keepcoder.Telegram"), .communication)
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.apple.mail"), .communication)

        // Media
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.spotify.client"), .media)
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.apple.Music"), .media)

        // Other & Unknown
        XCTAssertEqual(AppCategory.categorize(bundleID: "com.random.unrecognized.app"), .other)
        XCTAssertEqual(AppCategory.categorize(bundleID: nil), .unknown)
        XCTAssertEqual(AppCategory.categorize(bundleID: ""), .unknown)
    }

    func testDesktopContextRecordDefaultSerialization() throws {
        let record = DesktopContextRecord(
            activeAppBundleID: "com.apple.Safari",
            appCategory: AppCategory.browser.rawValue,
            focusedElementRole: "AXWebArea",
            windowState: "foreground",
            cursorPosition: [0.45, 0.60],
            timestamp: 1794211200.125,
            availability: DesktopContextAvailability(
                activeApp: true,
                focusedElement: true,
                cursorPosition: true,
                windowState: true
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DesktopContextRecord.self, from: data)

        XCTAssertEqual(decoded.activeAppBundleID, "com.apple.Safari")
        XCTAssertEqual(decoded.appCategory, "browser")
        XCTAssertEqual(decoded.focusedElementRole, "AXWebArea")
        XCTAssertEqual(decoded.windowState, "foreground")
        XCTAssertEqual(decoded.cursorPosition, [0.45, 0.60])
        XCTAssertEqual(decoded.timestamp, 1794211200.125, accuracy: 1e-4)
        XCTAssertTrue(decoded.availability.activeApp)
        XCTAssertTrue(decoded.availability.focusedElement)
        XCTAssertTrue(decoded.availability.cursorPosition)
        XCTAssertTrue(decoded.availability.windowState)
    }

    func testDesktopContextRecordPartialMissingDataDecoding() throws {
        // Missing focused element and cursor position
        let jsonStr = """
        {
            "active_app_bundle_id": "com.apple.Terminal",
            "app_category": "other",
            "window_state": "foreground",
            "timestamp": 12345.67,
            "availability": {
                "active_app": true,
                "focused_element": false,
                "cursor_position": false,
                "window_state": true
            }
        }
        """

        let data = jsonStr.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DesktopContextRecord.self, from: data)

        XCTAssertEqual(decoded.activeAppBundleID, "com.apple.Terminal")
        XCTAssertEqual(decoded.appCategory, "other")
        XCTAssertNil(decoded.focusedElementRole)
        XCTAssertEqual(decoded.cursorPosition, [0.0, 0.0])
        XCTAssertFalse(decoded.availability.focusedElement)
        XCTAssertFalse(decoded.availability.cursorPosition)
    }

    func testProviderSimulatedContextInjection() {
        let provider = DesktopContextProvider()
        let simRecord = DesktopContextRecord(
            activeAppBundleID: "com.microsoft.VSCode",
            appCategory: AppCategory.codeEditor.rawValue,
            focusedElementRole: "AXTextArea",
            windowState: "foreground",
            cursorPosition: [0.25, 0.75],
            timestamp: 100.0,
            availability: DesktopContextAvailability(activeApp: true, focusedElement: true, cursorPosition: true, windowState: true)
        )

        provider.updateSimulatedContext(simRecord)
        let retrieved = provider.currentContext()

        XCTAssertEqual(retrieved.activeAppBundleID, "com.microsoft.VSCode")
        XCTAssertEqual(retrieved.appCategory, "code_editor")
        XCTAssertEqual(retrieved.focusedElementRole, "AXTextArea")
        XCTAssertEqual(retrieved.cursorPosition, [0.25, 0.75])
    }

    func testResearchIntentBaselineMapping() {
        XCTAssertEqual(ResearchIntent.baselineMapping(forGestureLabel: "idle"), .idle)
        XCTAssertEqual(ResearchIntent.baselineMapping(forGestureLabel: "swipe_left"), .workspaceNavigate)
        XCTAssertEqual(ResearchIntent.baselineMapping(forGestureLabel: "swipe_right"), .workspaceNavigate)
        XCTAssertEqual(ResearchIntent.baselineMapping(forGestureLabel: "swipe_up"), .windowManipulate)
        XCTAssertEqual(ResearchIntent.baselineMapping(forGestureLabel: "swipe_down"), .windowManipulate)
        XCTAssertEqual(ResearchIntent.baselineMapping(forGestureLabel: "scroll_down"), .scroll)
        XCTAssertEqual(ResearchIntent.baselineMapping(forGestureLabel: "scroll_up"), .scroll)
        XCTAssertEqual(ResearchIntent.baselineMapping(forGestureLabel: "pinch_dock"), .select)
        XCTAssertNil(ResearchIntent.baselineMapping(forGestureLabel: "unrecognized_gesture"))
    }
}
