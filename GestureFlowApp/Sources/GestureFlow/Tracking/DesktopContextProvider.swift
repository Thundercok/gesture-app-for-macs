import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif
#if canImport(ApplicationServices)
import ApplicationServices
#endif

// MARK: - App Category
public enum AppCategory: String, Codable, CaseIterable {
    case browser
    case codeEditor = "code_editor"
    case fileManager = "file_manager"
    case communication
    case media
    case other
    case unknown

    public static func categorize(bundleID: String?) -> AppCategory {
        guard let bundleID = bundleID?.lowercased(), !bundleID.isEmpty else {
            return .unknown
        }

        // Web Browsers
        if bundleID.contains("safari") ||
           bundleID.contains("chrome") ||
           bundleID.contains("firefox") ||
           bundleID.contains("brave") ||
           bundleID.contains("edge") ||
           bundleID.contains("arc") ||
           bundleID.contains("opera") ||
           bundleID.contains("browser") {
            return .browser
        }

        // Code Editors & IDEs
        if bundleID.contains("vscode") ||
           bundleID.contains("xcode") ||
           bundleID.contains("sublime") ||
           bundleID.contains("jetbrains") ||
           bundleID.contains("cursor") ||
           bundleID.contains("intellij") ||
           bundleID.contains("pycharm") ||
           bundleID.contains("webstorm") ||
           bundleID.contains("neovim") ||
           bundleID.contains("atom") {
            return .codeEditor
        }

        // File Managers
        if bundleID.contains("finder") ||
           bundleID.contains("pathfinder") ||
           bundleID.contains("commander") {
            return .fileManager
        }

        // Communication
        if bundleID.contains("slack") ||
           bundleID.contains("teams") ||
           bundleID.contains("telegram") ||
           bundleID.contains("discord") ||
           bundleID.contains("messages") ||
           bundleID.contains("mail") ||
           bundleID.contains("zoom") ||
           bundleID.contains("signal") ||
           bundleID.contains("wechat") {
            return .communication
        }

        // Media
        if bundleID.contains("music") ||
           bundleID.contains("spotify") ||
           bundleID.contains("quicktime") ||
           bundleID.contains("vlc") ||
           bundleID.contains("iina") ||
           bundleID.contains("podcasts") ||
           bundleID.contains("tv") {
            return .media
        }

        return .other
    }
}

// MARK: - Desktop Context Availability
public struct DesktopContextAvailability: Codable, Equatable {
    public let activeApp: Bool
    public let focusedElement: Bool
    public let cursorPosition: Bool
    public let windowState: Bool

    enum CodingKeys: String, CodingKey {
        case activeApp = "active_app"
        case focusedElement = "focused_element"
        case cursorPosition = "cursor_position"
        case windowState = "window_state"
    }

    public init(activeApp: Bool, focusedElement: Bool, cursorPosition: Bool, windowState: Bool) {
        self.activeApp = activeApp
        self.focusedElement = focusedElement
        self.cursorPosition = cursorPosition
        self.windowState = windowState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeApp = (try? container.decode(Bool.self, forKey: .activeApp)) ?? false
        focusedElement = (try? container.decode(Bool.self, forKey: .focusedElement)) ?? false
        cursorPosition = (try? container.decode(Bool.self, forKey: .cursorPosition)) ?? false
        windowState = (try? container.decode(Bool.self, forKey: .windowState)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeApp, forKey: .activeApp)
        try container.encode(focusedElement, forKey: .focusedElement)
        try container.encode(cursorPosition, forKey: .cursorPosition)
        try container.encode(windowState, forKey: .windowState)
    }
}

// MARK: - Desktop Context Record
public struct DesktopContextRecord: Codable, Equatable {
    public let activeAppBundleID: String
    public let appCategory: String
    public let focusedElementRole: String?
    public let windowState: String
    public let cursorPosition: [Double]
    public let timestamp: Double
    public let availability: DesktopContextAvailability

    enum CodingKeys: String, CodingKey {
        case activeAppBundleID = "active_app_bundle_id"
        case appCategory = "app_category"
        case focusedElementRole = "focused_element_role"
        case windowState = "window_state"
        case cursorPosition = "cursor_position"
        case timestamp
        case availability
    }

    public init(
        activeAppBundleID: String = "unknown",
        appCategory: String = AppCategory.unknown.rawValue,
        focusedElementRole: String? = nil,
        windowState: String = "unknown",
        cursorPosition: [Double] = [0.0, 0.0],
        timestamp: Double = 0.0,
        availability: DesktopContextAvailability = DesktopContextAvailability(activeApp: false, focusedElement: false, cursorPosition: false, windowState: false)
    ) {
        self.activeAppBundleID = activeAppBundleID
        self.appCategory = appCategory
        self.focusedElementRole = focusedElementRole
        self.windowState = windowState
        self.cursorPosition = cursorPosition
        self.timestamp = timestamp
        self.availability = availability
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeAppBundleID = (try? container.decode(String.self, forKey: .activeAppBundleID)) ?? "unknown"
        appCategory = (try? container.decode(String.self, forKey: .appCategory)) ?? AppCategory.unknown.rawValue
        focusedElementRole = try? container.decodeIfPresent(String.self, forKey: .focusedElementRole)
        windowState = (try? container.decode(String.self, forKey: .windowState)) ?? "unknown"
        cursorPosition = (try? container.decode([Double].self, forKey: .cursorPosition)) ?? [0.0, 0.0]
        timestamp = (try? container.decode(Double.self, forKey: .timestamp)) ?? 0.0
        availability = (try? container.decode(DesktopContextAvailability.self, forKey: .availability)) ?? DesktopContextAvailability(activeApp: false, focusedElement: false, cursorPosition: false, windowState: false)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeAppBundleID, forKey: .activeAppBundleID)
        try container.encode(appCategory, forKey: .appCategory)
        try container.encodeIfPresent(focusedElementRole, forKey: .focusedElementRole)
        try container.encode(windowState, forKey: .windowState)
        try container.encode(cursorPosition, forKey: .cursorPosition)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(availability, forKey: .availability)
    }
}

// MARK: - Desktop Context Provider Protocol
public protocol DesktopContextProviderProtocol: AnyObject {
    func currentContext() -> DesktopContextRecord
}

// MARK: - Desktop Context Provider
public final class DesktopContextProvider: DesktopContextProviderProtocol {
    public static let shared = DesktopContextProvider()

    private let lock = NSLock()
    private var cachedRecord: DesktopContextRecord
    private var lastQueryTime: TimeInterval = 0
    private let queryThrottleSeconds: TimeInterval = 0.05 // 20Hz update rate max to never saturate main/accessibility IPC

    public init(initialRecord: DesktopContextRecord? = nil) {
        self.cachedRecord = initialRecord ?? DesktopContextRecord()
    }

    /// Retrieves current desktop context.
    /// Non-blocking: returns cached snapshot or refreshes lightweight properties when throttle window elapsed.
    public func currentContext() -> DesktopContextRecord {
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock()
        defer { lock.unlock() }

        if now - lastQueryTime >= queryThrottleSeconds {
            lastQueryTime = now
            cachedRecord = querySystemContext(timestamp: now)
        }

        return cachedRecord
    }

    /// Explicitly updates cached record (useful in test harnesses or simulated replays).
    public func updateSimulatedContext(_ record: DesktopContextRecord) {
        lock.lock()
        cachedRecord = record
        lastQueryTime = Date().timeIntervalSinceReferenceDate
        lock.unlock()
    }

    // MARK: - Internal System Query
    private func querySystemContext(timestamp: Double) -> DesktopContextRecord {
        var bundleID = "unknown"
        var category = AppCategory.unknown
        var hasActiveApp = false
        var windowState = "unknown"
        var hasWindowState = false
        var focusedRole: String? = nil
        var hasFocusedElement = false
        var normCursor = [0.0, 0.0]
        var hasCursor = false

        #if canImport(AppKit)
        // 1. Frontmost Application
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            if let bid = frontApp.bundleIdentifier, !bid.isEmpty {
                bundleID = bid
                category = AppCategory.categorize(bundleID: bid)
                hasActiveApp = true
            } else {
                let name = frontApp.localizedName ?? "unknown"
                bundleID = name
                category = AppCategory.categorize(bundleID: name)
                hasActiveApp = true
            }

            // Window / Active State
            if frontApp.isActive {
                windowState = "foreground"
                hasWindowState = true
            }
        }

        // 2. Cursor Position (Normalized [0.0 ... 1.0])
        let mouseLoc = NSEvent.mouseLocation
        if let mainScreen = NSScreen.main {
            let screenFrame = mainScreen.frame
            if screenFrame.width > 0 && screenFrame.height > 0 {
                let normX = max(0.0, min(1.0, Double(mouseLoc.x / screenFrame.width)))
                // In macOS AppKit, (0,0) is bottom-left; normalize with top-left as (0,0) to match Vision coordinates
                let normY = max(0.0, min(1.0, Double((screenFrame.height - mouseLoc.y) / screenFrame.height)))
                normCursor = [normX, normY]
                hasCursor = true
            }
        }
        #endif

        #if canImport(ApplicationServices)
        // 3. Focused Element Role (Strictly opt-in, non-blocking check, privacy-preserving)
        // Never reads text, values, or contents. Only reads kAXRoleAttribute.
        if AXIsProcessTrusted() {
            let systemWide = AXUIElementCreateSystemWide()
            var focusedAppRef: CFTypeRef?
            let appErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppRef)
            if appErr == .success, let focusedApp = focusedAppRef {
                let appElem = focusedApp as! AXUIElement
                var focusedElemRef: CFTypeRef?
                let elemErr = AXUIElementCopyAttributeValue(appElem, kAXFocusedUIElementAttribute as CFString, &focusedElemRef)
                if elemErr == .success, let focusedElem = focusedElemRef {
                    let elem = focusedElem as! AXUIElement
                    var roleRef: CFTypeRef?
                    let roleErr = AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
                    if roleErr == .success, let roleVal = roleRef as? String {
                        focusedRole = roleVal
                        hasFocusedElement = true
                    }
                }
            }
        }
        #endif

        let availability = DesktopContextAvailability(
            activeApp: hasActiveApp,
            focusedElement: hasFocusedElement,
            cursorPosition: hasCursor,
            windowState: hasWindowState
        )

        return DesktopContextRecord(
            activeAppBundleID: bundleID,
            appCategory: category.rawValue,
            focusedElementRole: focusedRole,
            windowState: windowState,
            cursorPosition: normCursor,
            timestamp: timestamp,
            availability: availability
        )
    }
}
