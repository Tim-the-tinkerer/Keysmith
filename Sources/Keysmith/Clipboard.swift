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

@MainActor
final class ClipboardSession: ObservableObject {
    @Published private(set) var clear: ClipboardClearDelay = .thirty
    @Published private(set) var secondsRemaining: Int?

    private var task: Task<Void, Never>?
    private var token: Int?
    private let defaults = UserDefaults.standard

    init() {
        if defaults.object(forKey: ClipboardClear.defaultsKey) != nil {
            clear = ClipboardClearDelay.parse(
                seconds: defaults.integer(forKey: ClipboardClear.defaultsKey)
            )
        }
    }

    func setDelay(_ delay: ClipboardClearDelay) {
        clear = delay
        defaults.set(delay.rawValue, forKey: ClipboardClear.defaultsKey)
        if delay == .off {
            cancel()
            ClipboardWatch.forget()
        }
    }

    func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        token = pb.changeCount
        if clear == .off {
            ClipboardWatch.forget()
            cancel()
            return
        }
        ClipboardWatch.remember(changeCount: pb.changeCount)
        schedule()
    }

    func clearNow() {
        cancel()
        ClipboardWatch.forget()
        NSPasteboard.general.clearContents()
        token = nil
    }

    @discardableResult
    func flushIfPending() -> Bool {
        cancel()
        if ClipboardWatch.clearIfOwned() {
            token = nil
            return true
        }
        return false
    }

    private func schedule() {
        task?.cancel()
        let seconds = clear.seconds
        guard seconds > 0, let token else {
            secondsRemaining = nil
            return
        }
        secondsRemaining = seconds
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            for remaining in stride(from: seconds, through: 1, by: -1) {
                if Task.isCancelled { return }
                self.secondsRemaining = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if Task.isCancelled { return }
            self.secondsRemaining = nil
            self.clearPasteboard(ifToken: token)
        }
    }

    private func cancel() {
        task?.cancel()
        task = nil
        secondsRemaining = nil
    }

    private func clearPasteboard(ifToken token: Int) {
        let pb = NSPasteboard.general
        guard ClipboardClear.shouldClear(
            copiedChangeCount: token,
            currentChangeCount: pb.changeCount
        ) else { return }
        pb.clearContents()
        if self.token == token {
            self.token = nil
        }
        ClipboardWatch.forget()
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
