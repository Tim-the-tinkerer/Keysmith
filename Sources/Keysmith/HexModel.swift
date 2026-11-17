import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class HexModel: ObservableObject {
    @Published var preset: SizePreset = .bits(256)
    @Published var namedUse: NamedUse?
    @Published var customBytes: Int = 32
    @Published var count: Int = 1
    @Published var format: HexFormat = .compact
    @Published var hexCase: HexCase = .upper
    @Published var clipboardClear: ClipboardClearDelay = .off
    @Published var clipboardSecondsRemaining: Int?
    @Published var keys: [GeneratedKey] = []
    @Published var selectedID: UUID?
    @Published var history: [GeneratedKey] = []
    @Published var scrambleBytes: [UInt8]?
    @Published var status: String?
    @Published var statusIsError = false
    @Published var copiedFlash = false
    @Published var isGenerating = false

    let clipboard: ClipboardSession
    private var scrambleTask: Task<Void, Never>?
    private var clearSink: AnyCancellable?
    private var remainingSink: AnyCancellable?
    private let defaults = UserDefaults.standard


    static let maxHistory = 40

    var byteCount: Int {
        switch preset {
        case .bits(let n): return max(1, n / 8)
        case .custom: return min(HexEngine.maxBytes, max(HexEngine.minBytes, customBytes))
        case .uuidV4: return 16
        }
    }

    var bitCount: Int { byteCount * 8 }

    var selected: GeneratedKey? {
        if let selectedID, let found = keys.first(where: { $0.id == selectedID }) {
            return found
        }
        return keys.first
    }

    var displayBytes: [UInt8] {
        scrambleBytes ?? selected?.bytes ?? []
    }

    var formattedSelected: String {
        guard let selected else { return "" }
        return selected.formatted(style: format, hexCase: hexCase)
    }

    var formattedAll: String {
        keys.map { $0.formatted(style: format, hexCase: hexCase) }.joined(separator: "\n")
    }

    init(clipboard: ClipboardSession) {
        self.clipboard = clipboard
        clipboardClear = clipboard.clear
        bindClipboard()
        loadPrefs()
    }

    private func bindClipboard() {
        clearSink = clipboard.$clear.dropFirst().sink { [weak self] delay in
            guard let self, self.clipboardClear != delay else { return }
            self.clipboardClear = delay
        }
        remainingSink = clipboard.$secondsRemaining.dropFirst().sink { [weak self] remaining in
            self?.clipboardSecondsRemaining = remaining
        }
    }

    private var didOpen = false

    func openIfNeeded() {
        guard !didOpen else { return }
        didOpen = true
        if keys.isEmpty {
            generate()
        }
    }

    func generate() {
        scrambleTask?.cancel()
        isGenerating = true
        status = nil
        statusIsError = false

        let n = count
        let bytesEach = byteCount
        let kind: KeyKind = {
            if case .uuidV4 = preset { return .uuidV4 }
            return .random
        }()

        do {
            var fresh: [GeneratedKey] = []
            fresh.reserveCapacity(n)
            for _ in 0..<n {
                let bytes: [UInt8]
                switch kind {
                case .uuidV4:
                    bytes = try HexEngine.uuidV4Bytes()
                case .random:
                    bytes = try HexEngine.randomBytes(count: bytesEach)
                }
                fresh.append(
                    GeneratedKey(
                        id: UUID(),
                        bytes: bytes,
                        created: Date(),
                        kind: kind
                    )
                )
            }

            let first = fresh[0].bytes
            scrambleTask = Task { @MainActor [weak self] in
                guard let self else { return }
                for _ in 0..<5 {
                    if Task.isCancelled { return }
                    self.scrambleBytes = (try? HexEngine.randomBytes(count: first.count))
                    try? await Task.sleep(nanoseconds: 28_000_000)
                }
                if Task.isCancelled { return }
                self.scrambleBytes = nil
                self.keys = fresh
                self.selectedID = fresh.first?.id
                self.history.insert(contentsOf: fresh, at: 0)
                if self.history.count > Self.maxHistory {
                    self.history = Array(self.history.prefix(Self.maxHistory))
                }
                self.isGenerating = false
                let label: String
                if let use = self.namedUse, n == 1 {
                    label = "\(use.title) key"
                } else if n == 1 {
                    label = "\(self.bitCount)-bit key"
                } else {
                    label = "\(n) × \(self.bitCount)-bit keys"
                }
                self.flash("Generated \(label)")
            }
        } catch HexEngineError.invalidLength {
            isGenerating = false
            fail("Length must be \(HexEngine.minBytes)–\(HexEngine.maxBytes) bytes")
        } catch HexEngineError.rngFailed(let status) {
            isGenerating = false
            fail("CSPRNG failed (status \(status))")
        } catch {
            isGenerating = false
            fail(error.localizedDescription)
        }
    }

    func selectPreset(_ preset: SizePreset) {
        namedUse = nil
        self.preset = preset
        if case .uuidV4 = preset, format == .compact {
            format = .uuid
        }
    }

    func selectNamedUse(_ use: NamedUse) {
        namedUse = use
        preset = .bits(use.bits)
    }

    func select(_ key: GeneratedKey) {
        selectedID = key.id
        if !keys.contains(where: { $0.id == key.id }) {
            keys = [key]
        }
    }

    func copySelected() {
        let text = formattedSelected
        guard !text.isEmpty else { return }
        clipboard.write(text)
        flash(copiedStatus(prefix: "Copied"))
        copiedFlash = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            copiedFlash = false
        }
    }

    func copyAll() {
        let text = formattedAll
        guard !text.isEmpty else { return }
        clipboard.write(text)
        flash(copiedStatus(prefix: "Copied \(keys.count) key\(keys.count == 1 ? "" : "s")"))
    }

    func setClipboardDelay(_ delay: ClipboardClearDelay) {
        clipboardClear = delay
        clipboard.setDelay(delay)
    }

    func clearClipboardNow() {
        clipboard.clearNow()
        flash("Clipboard cleared")
    }

    func flushClipboardIfPending() {
        if clipboard.flushIfPending() {
            flash("Clipboard cleared")
        }
    }

    func save() {
        saveHex()
    }

    func saveHex() {
        let text = keys.count > 1 ? formattedAll : formattedSelected
        guard !text.isEmpty else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.plainText, .utf8PlainText]
        let stamp = fileStamp()
        panel.nameFieldStringValue = "nybble-\(bitCount)bit-\(stamp).hex"
        panel.title = "Save hex key"
        panel.prompt = "Save"

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
        let data = HexEngine.binaryData(selected.bytes)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data, .data]
        let stamp = fileStamp()
        panel.nameFieldStringValue = "nybble-\(selected.bitCount)bit-\(stamp).bin"
        panel.title = "Save binary key"
        panel.prompt = "Save"

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
        scrambleBytes = nil
        keys = []
        selectedID = nil
        history = []
        isGenerating = false
        flash("Cleared")
    }

    func persistPrefs() {
        defaults.set(presetID, forKey: "hex.preset")
        defaults.set(customBytes, forKey: "hex.customBytes")
        defaults.set(count, forKey: "hex.count")
        defaults.set(format.rawValue, forKey: "hex.format")
        defaults.set(hexCase.rawValue, forKey: "hex.hexCase")
        if let namedUse {
            defaults.set(namedUse.rawValue, forKey: "hex.namedUse")
        } else {
            defaults.removeObject(forKey: "hex.namedUse")
        }
    }

    private var presetID: String {
        switch preset {
        case .bits(let n): return "bits-\(n)"
        case .custom: return "custom"
        case .uuidV4: return "uuid"
        }
    }

    private func loadPrefs() {
        if let raw = defaults.string(forKey: "hex.preset") {
            if raw == "custom" {
                preset = .custom
            } else if raw == "uuid" {
                preset = .uuidV4
            } else if raw.hasPrefix("bits-"), let n = Int(raw.dropFirst(5)), HexEngine.bitPresets.contains(n) {
                preset = .bits(n)
            }
        }
        let storedBytes = defaults.integer(forKey: "hex.customBytes")
        if storedBytes >= HexEngine.minBytes, storedBytes <= HexEngine.maxBytes {
            customBytes = storedBytes
        }
        let storedCount = defaults.integer(forKey: "hex.count")
        if storedCount >= 1, storedCount <= HexEngine.maxCount {
            count = storedCount
        }
        if let raw = defaults.string(forKey: "hex.format"), let parsed = HexFormat(rawValue: raw) {
            format = parsed
        }
        if let raw = defaults.string(forKey: "hex.hexCase"), let parsed = HexCase(rawValue: raw) {
            hexCase = parsed
        }
        if let raw = defaults.string(forKey: "hex.namedUse"), let parsed = NamedUse(rawValue: raw) {
            if case .bits(let n) = preset, n == parsed.bits {
                namedUse = parsed
            }
        }
    }

    private func copiedStatus(prefix: String) -> String {
        if clipboard.clear == .off {
            return prefix
        }
        return "\(prefix) · clears in \(clipboard.clear.seconds)s"
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
