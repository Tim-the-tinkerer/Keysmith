import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var options = PasswordOptions()
    @Published var count: Int = 1
    @Published var clipboardClear: ClipboardClearDelay = .thirty
    @Published var clipboardSecondsRemaining: Int?
    @Published var passwords: [GeneratedPassword] = []
    @Published var selectedID: UUID?
    @Published var history: [GeneratedPassword] = []
    @Published var scramble: String?
    @Published var status: String?
    @Published var statusIsError = false
    @Published var copiedFlash = false
    @Published var isGenerating = false

    private var scrambleTask: Task<Void, Never>?
    private var clipboardTask: Task<Void, Never>?
    private var clipboardToken: Int?
    private let defaults = UserDefaults.standard

    static let maxHistory = 40

    var selected: GeneratedPassword? {
        if let selectedID, let found = passwords.first(where: { $0.id == selectedID }) {
            return found
        }
        return passwords.first
    }

    var displayPassword: String {
        scramble ?? selected?.value ?? ""
    }

    var poolSize: Int {
        PasswordEngine.combinedPool(options: options).count
    }

    var entropyBits: Double {
        PasswordEngine.entropyBits(options: options)
    }

    var strength: Strength {
        PasswordEngine.strength(options: options)
    }

    var optionsDirty: Bool {
        guard let selected else { return false }
        return selected.options != options
    }

    init() {
        loadPrefs()
    }

    func generate() {
        scrambleTask?.cancel()
        isGenerating = true
        status = nil
        statusIsError = false

        let n = min(PasswordEngine.maxCount, max(1, count))
        var current = options
        current.length = PasswordEngine.clampedLength(current.length)
        options.length = current.length

        do {
            var fresh: [GeneratedPassword] = []
            fresh.reserveCapacity(n)
            for _ in 0..<n {
                let value = try PasswordEngine.generate(options: current)
                fresh.append(
                    GeneratedPassword(
                        id: UUID(),
                        value: value,
                        created: Date(),
                        options: current
                    )
                )
            }

            let length = current.length
            scrambleTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let pool = PasswordEngine.combinedPool(options: current)
                for _ in 0..<5 {
                    if Task.isCancelled { return }
                    if pool.isEmpty { break }
                    self.scramble = String((0..<length).compactMap { _ in pool.randomElement() })
                    try? await Task.sleep(nanoseconds: 28_000_000)
                }
                if Task.isCancelled { return }
                self.scramble = nil
                self.passwords = fresh
                self.selectedID = fresh.first?.id
                self.history.insert(contentsOf: fresh, at: 0)
                if self.history.count > Self.maxHistory {
                    self.history = Array(self.history.prefix(Self.maxHistory))
                }
                self.isGenerating = false
                let label: String
                if n == 1 {
                    label = "\(length)-character password"
                } else {
                    label = "\(n) × \(length)-character passwords"
                }
                self.flash("Generated \(label)")
            }
        } catch PasswordEngineError.invalidLength {
            isGenerating = false
            fail("Length must be \(PasswordEngine.minLength)–\(PasswordEngine.maxLength)")
        } catch PasswordEngineError.emptyCharset {
            isGenerating = false
            fail("Turn on at least one character class")
        } catch PasswordEngineError.rngFailed(let status) {
            isGenerating = false
            fail("CSPRNG failed (status \(status))")
        } catch {
            isGenerating = false
            fail(error.localizedDescription)
        }
    }

    func select(_ password: GeneratedPassword) {
        selectedID = password.id
        if !passwords.contains(where: { $0.id == password.id }) {
            passwords = [password]
        }
    }

    func setLength(_ length: Int) {
        options.length = PasswordEngine.clampedLength(length)
    }

    func toggle(_ cls: CharClass) {
        switch cls {
        case .uppercase: options.uppercase.toggle()
        case .lowercase: options.lowercase.toggle()
        case .digits: options.digits.toggle()
        case .specials: options.specials.toggle()
        }
        if options.enabledClasses.isEmpty {
            switch cls {
            case .uppercase: options.uppercase = true
            case .lowercase: options.lowercase = true
            case .digits: options.digits = true
            case .specials: options.specials = true
            }
        }
    }

    func isEnabled(_ cls: CharClass) -> Bool {
        switch cls {
        case .uppercase: return options.uppercase
        case .lowercase: return options.lowercase
        case .digits: return options.digits
        case .specials: return options.specials
        }
    }

    func copySelected() {
        let text = displayPassword
        guard !text.isEmpty, scramble == nil else { return }
        writePasteboard(text)
        flash(copiedStatus(prefix: "Copied"))
        copiedFlash = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            copiedFlash = false
        }
    }

    func copyAll() {
        let text = passwords.map(\.value).joined(separator: "\n")
        guard !text.isEmpty else { return }
        writePasteboard(text)
        flash(copiedStatus(prefix: "Copied \(passwords.count) password\(passwords.count == 1 ? "" : "s")"))
    }

    func setClipboardDelay(_ delay: ClipboardClearDelay) {
        clipboardClear = delay
        persistPrefs()
        if delay == .off {
            cancelClipboardTimer()
            ClipboardWatch.forget()
        }
    }

    func clearClipboardNow() {
        cancelClipboardTimer()
        ClipboardWatch.forget()
        NSPasteboard.general.clearContents()
        clipboardToken = nil
        flash("Clipboard cleared")
    }

    func flushClipboardIfPending() {
        cancelClipboardTimer()
        if ClipboardWatch.clearIfOwned() {
            clipboardToken = nil
            flash("Clipboard cleared")
        }
    }

    func save() {
        saveText()
    }

    func saveText() {
        let text = passwords.count > 1
            ? passwords.map(\.value).joined(separator: "\n")
            : (selected?.value ?? "")
        guard !text.isEmpty else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.plainText, .utf8PlainText]
        panel.nameFieldStringValue = "keysmith-\(options.length)ch.txt"
        panel.title = "Save passwords"
        panel.prompt = "Save"
        panel.message = "Passwords are secrets. Anyone with this file can read them."

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try (text + "\n").write(to: url, atomically: true, encoding: .utf8)
                Task { @MainActor in
                    self?.flash("Saved \(url.lastPathComponent)")
                }
            } catch {
                Task { @MainActor in
                    self?.fail(error.localizedDescription)
                }
            }
        }
    }

    func saveBinary() {
        guard let selected else { return }
        let data = PasswordEngine.binaryData(selected.value)
        guard !data.isEmpty else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data, .data]
        panel.nameFieldStringValue = "keysmith-\(selected.length)ch-\(fileStamp()).bin"
        panel.title = "Save binary key"
        panel.prompt = "Save"
        panel.message = "Raw bytes of the selected password, with no trailing newline. Anyone with this file has the password."

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                Task { @MainActor in
                    self?.flash("Saved \(url.lastPathComponent) · \(data.count) bytes")
                }
            } catch {
                Task { @MainActor in
                    self?.fail(error.localizedDescription)
                }
            }
        }
    }

    private func fileStamp() -> String {
        ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
    }

    func clear() {
        scrambleTask?.cancel()
        scramble = nil
        passwords = []
        selectedID = nil
        history = []
        isGenerating = false
        flash("Cleared")
    }

    func persistPrefs() {
        defaults.set(options.length, forKey: "length")
        defaults.set(options.uppercase, forKey: "uppercase")
        defaults.set(options.lowercase, forKey: "lowercase")
        defaults.set(options.digits, forKey: "digits")
        defaults.set(options.specials, forKey: "specials")
        defaults.set(options.excludeAmbiguous, forKey: "excludeAmbiguous")
        defaults.set(options.specialKind.rawValue, forKey: "specialKind")
        defaults.set(options.customSpecials, forKey: "customSpecials")
        defaults.set(count, forKey: "count")
        defaults.set(clipboardClear.rawValue, forKey: ClipboardClear.defaultsKey)
    }

    private func loadPrefs() {
        let storedLength = defaults.integer(forKey: "length")
        if storedLength >= PasswordEngine.minLength, storedLength <= PasswordEngine.maxLength {
            options.length = storedLength
        }
        if defaults.object(forKey: "uppercase") != nil {
            options.uppercase = defaults.bool(forKey: "uppercase")
        }
        if defaults.object(forKey: "lowercase") != nil {
            options.lowercase = defaults.bool(forKey: "lowercase")
        }
        if defaults.object(forKey: "digits") != nil {
            options.digits = defaults.bool(forKey: "digits")
        }
        if defaults.object(forKey: "specials") != nil {
            options.specials = defaults.bool(forKey: "specials")
        }
        if options.enabledClasses.isEmpty {
            options.uppercase = true
            options.lowercase = true
            options.digits = true
            options.specials = true
        }
        options.excludeAmbiguous = defaults.bool(forKey: "excludeAmbiguous")
        if let raw = defaults.string(forKey: "specialKind"), let parsed = SpecialKind(rawValue: raw) {
            options.specialKind = parsed
        }
        if let custom = defaults.string(forKey: "customSpecials"), !custom.isEmpty {
            options.customSpecials = custom
        }
        let storedCount = defaults.integer(forKey: "count")
        if storedCount >= 1, storedCount <= PasswordEngine.maxCount {
            count = storedCount
        }
        if defaults.object(forKey: ClipboardClear.defaultsKey) != nil {
            clipboardClear = ClipboardClearDelay.parse(
                seconds: defaults.integer(forKey: ClipboardClear.defaultsKey)
            )
        }
    }

    private func writePasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        clipboardToken = pb.changeCount
        if clipboardClear == .off {
            ClipboardWatch.forget()
        } else {
            ClipboardWatch.remember(changeCount: pb.changeCount)
        }
        scheduleClipboardClear()
    }

    private func copiedStatus(prefix: String) -> String {
        if clipboardClear == .off {
            return prefix
        }
        return "\(prefix) · clears in \(clipboardClear.seconds)s"
    }

    private func scheduleClipboardClear() {
        clipboardTask?.cancel()
        let seconds = clipboardClear.seconds
        guard seconds > 0, let token = clipboardToken else {
            clipboardSecondsRemaining = nil
            return
        }
        clipboardSecondsRemaining = seconds
        clipboardTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for remaining in stride(from: seconds, through: 1, by: -1) {
                if Task.isCancelled { return }
                self.clipboardSecondsRemaining = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if Task.isCancelled { return }
            self.clipboardSecondsRemaining = nil
            self.clearPasteboard(ifToken: token)
        }
    }

    private func cancelClipboardTimer() {
        clipboardTask?.cancel()
        clipboardTask = nil
        clipboardSecondsRemaining = nil
    }

    private func clearPasteboard(ifToken token: Int) {
        let pb = NSPasteboard.general
        guard ClipboardClear.shouldClear(
            copiedChangeCount: token,
            currentChangeCount: pb.changeCount
        ) else { return }
        pb.clearContents()
        if clipboardToken == token {
            clipboardToken = nil
        }
        ClipboardWatch.forget()
        flash("Clipboard cleared")
    }

    private func flash(_ message: String) {
        status = message
        statusIsError = false
    }

    private func fail(_ message: String) {
        status = message
        statusIsError = true
    }
}
