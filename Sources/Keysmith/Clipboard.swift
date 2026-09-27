import AppKit
import Foundation

enum ClipboardClearDelay: Int, CaseIterable, Identifiable {
    case off = 0
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }
    var seconds: Int { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .thirty: return "30s"
        case .sixty: return "60s"
        }
    }

    var menuTitle: String {
        switch self {
        case .off: return "Don't Clear"
        case .thirty: return "Clear After 30 Seconds"
        case .sixty: return "Clear After 60 Seconds"
        }
    }

    static func parse(seconds: Int) -> ClipboardClearDelay {
        ClipboardClearDelay(rawValue: seconds) ?? .off
    }
}

enum ClipboardClear {
    static let defaultsKey = "clipboardClearSeconds"

    /// Clear only if nothing else has been copied since Keysmith wrote the pasteboard.
    static func shouldClear(copiedChangeCount: Int, currentChangeCount: Int) -> Bool {
        copiedChangeCount == currentChangeCount
    }
}

enum ClipboardWatch {
    static var copiedChangeCount: Int?

    static func remember(changeCount: Int) {
        copiedChangeCount = changeCount
    }

    static func forget() {
        copiedChangeCount = nil
    }

    @discardableResult
    static func clearIfOwned() -> Bool {
        guard let token = copiedChangeCount else { return false }
        copiedChangeCount = nil
        let pb = NSPasteboard.general
        guard shouldClear(token: token, current: pb.changeCount) else { return false }
        pb.clearContents()
        return true
    }

    static func shouldClear(token: Int, current: Int) -> Bool {
        ClipboardClear.shouldClear(copiedChangeCount: token, currentChangeCount: current)
    }
}
