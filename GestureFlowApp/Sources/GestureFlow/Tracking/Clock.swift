import Foundation

protocol Clock: AnyObject {
    var now: Date { get }
    var uptime: TimeInterval { get }
}

final class SystemClock: Clock {
    static let shared = SystemClock()
    init() {}

    var now: Date {
        Date()
    }

    var uptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

final class ReplayClock: Clock {
    var currentTime: TimeInterval

    init(initialTime: TimeInterval = 0.0) {
        self.currentTime = initialTime
    }

    var now: Date {
        Date(timeIntervalSinceReferenceDate: currentTime)
    }

    var uptime: TimeInterval {
        currentTime
    }

    func advance(to time: TimeInterval) {
        self.currentTime = time
    }
}
