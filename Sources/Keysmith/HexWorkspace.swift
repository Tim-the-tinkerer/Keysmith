import AppKit
import SwiftUI

private typealias Theme = HexTheme

struct HexWorkspace: View {
    @ObservedObject var model: HexModel
    @ObservedObject var shell: ShellModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)
            Rectangle()
                .fill(Theme.border.opacity(0.7))
                .frame(width: 1)
            mainPane
        }
        .background(Theme.bg)
        .tint(Theme.phosphor)
        .preferredColorScheme(.dark)
        .onChange(of: model.preset) { _ in model.persistPrefs() }
        .onChange(of: model.customBytes) { _ in model.persistPrefs() }
        .onChange(of: model.count) { _ in model.persistPrefs() }
        .onChange(of: model.format) { _ in model.persistPrefs() }
        .onChange(of: model.hexCase) { _ in model.persistPrefs() }
        .onChange(of: model.namedUse) { _ in model.persistPrefs() }
        .onChange(of: model.clipboardClear) { delay in
            model.setClipboardDelay(delay)
        }
        .onAppear {
            model.openIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithGenerate)) { _ in model.generate() }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithCopy)) { _ in model.copySelected() }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithCopyAll)) { _ in model.copyAll() }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithSave)) { _ in model.saveHex() }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithSaveBinary)) { _ in model.saveBinary() }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithClear)) { _ in model.clear() }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithClearClipboard)) { _ in
            model.clearClipboardNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithWillTerminate)) { _ in
            model.flushClipboardIfPending()
        }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithClipboardDelay)) { note in
            if let seconds = note.object as? Int {
                model.setClipboardDelay(ClipboardClearDelay.parse(seconds: seconds))
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                modePicker
                brand
                sizeSection
                useSection
                if case .custom = model.preset {
                    customBytesRow
                }
                countRow
                formatSection
                caseRow
                clipboardRow
                actionRow
                entropyCard
            }
            .padding(16)
        }
        .background(Theme.panel)
    }

    private var modePicker: some View {
        Picker("Workspace", selection: $shell.mode) {
            ForEach(Workspace.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.top, 4)
        .help("Password is ⌘1. Hex is ⌘2.")
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NYBBLE")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(2.6)
                .foregroundStyle(Theme.phosphor)
            Text("Hex key generator")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 4)
    }

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupLabel("SIZE")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(HexEngine.bitPresets, id: \.self) { bits in
                    presetButton(.bits(bits))
                }
                presetButton(.uuidV4)
                presetButton(.custom)
            }
        }
    }

    private func presetButton(_ preset: SizePreset) -> some View {
        let selected = model.preset == preset
        return Button {
            model.selectPreset(preset)
        } label: {
            VStack(spacing: 2) {
                Text(preset.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(preset.subtitle)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(selected ? Theme.bg.opacity(0.75) : Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Theme.bg : Theme.text)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.phosphor : Theme.elevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? Theme.phosphorGlow : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(presetHelp(preset))
    }

    private func presetHelp(_ preset: SizePreset) -> String {
        switch preset {
        case .bits(64): return "64-bit · 8 bytes · 16 hex digits"
        case .bits(128): return "128-bit · AES-128 / UUID length"
        case .bits(192): return "192-bit · AES-192"
        case .bits(256): return "256-bit · AES-256 / SHA-256"
        case .bits(384): return "384-bit · SHA-384"
        case .bits(512): return "512-bit · SHA-512"
        case .custom: return "Custom length, 1–1024 bytes"
        case .uuidV4: return "RFC 4122 UUID version 4"
        default: return preset.title
        }
    }

    private var useSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupLabel("USE")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(NamedUse.allCases) { use in
                    let selected = model.namedUse == use
                    Button {
                        model.selectNamedUse(use)
                    } label: {
                        VStack(spacing: 2) {
                            Text(use.title)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Text("\(use.bits)-bit")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(selected ? Theme.bg.opacity(0.75) : Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(selected ? Theme.bg : Theme.text)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Theme.phosphor : Theme.elevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selected ? Theme.phosphorGlow : Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(use.help)
                }
            }
            Text("Names a length. Generation is unchanged.")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
    }

    private var customBytesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            groupLabel("BYTES")
            HStack(spacing: 8) {
                Stepper(value: $model.customBytes, in: HexEngine.minBytes...HexEngine.maxBytes) {
                    Text("\(model.customBytes)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.phosphor)
                        .frame(minWidth: 44, alignment: .leading)
                }
                Text("\(model.customBytes * 8) bits")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var countRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            groupLabel("BATCH")
            HStack(spacing: 8) {
                Stepper(value: $model.count, in: 1...HexEngine.maxCount) {
                    Text("\(model.count)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .frame(minWidth: 28, alignment: .leading)
                }
                Text(model.count == 1 ? "key" : "keys")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupLabel("FORMAT")
            VStack(spacing: 4) {
                ForEach(HexFormat.allCases) { style in
                    Button {
                        model.format = style
                    } label: {
                        HStack {
                            Text(style.title)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(style.help)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(model.format == style ? Theme.bg.opacity(0.7) : Theme.muted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(model.format == style ? Theme.bg : Theme.text)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(model.format == style ? Theme.phosphor : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var caseRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupLabel("CASE")
            Picker("Case", selection: $model.hexCase) {
                ForEach(HexCase.allCases) { hexCase in
                    Text(hexCase.title).tag(hexCase)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.format == .base64)
            .help("Uppercase, mixed, or lowercase hex digits. Mixed is stable for a given key.")
        }
    }

    private var clipboardRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupLabel("CLIPBOARD")
            Picker("Clear after", selection: $model.clipboardClear) {
                ForEach(ClipboardClearDelay.allCases) { delay in
                    Text(delay.title).tag(delay)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Clear the pasteboard after a delay if it still holds the key Keysmith copied.")
        }
    }

    private var actionRow: some View {
        VStack(spacing: 8) {
            Button {
                model.generate()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(model.isGenerating ? "Generating…" : "Generate")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NybbleButtonStyle(kind: .primary))
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(model.isGenerating)

            HStack(spacing: 6) {
                Button("Copy") { model.copySelected() }
                    .buttonStyle(NybbleButtonStyle(kind: .secondary))
                    .disabled(model.selected == nil)
                Button("Copy all") { model.copyAll() }
                    .buttonStyle(NybbleButtonStyle(kind: .secondary))
                    .disabled(model.keys.isEmpty)
            }
            HStack(spacing: 6) {
                Button("Save hex…") { model.saveHex() }
                    .buttonStyle(NybbleButtonStyle(kind: .ghost))
                    .disabled(model.selected == nil)
                    .help("Save the key as text (current format).")
                Button("Save binary…") { model.saveBinary() }
                    .buttonStyle(NybbleButtonStyle(kind: .ghost))
                    .disabled(model.selected == nil)
                    .help("Save the selected key as raw bytes.")
            }
        }
    }

    private var entropyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            groupLabel("ENTROPY")
            VStack(alignment: .leading, spacing: 4) {
                labeled("Bits", "\(model.bitCount)")
                labeled("Bytes", "\(model.byteCount)")
                labeled("Nybbles", "\(model.byteCount * 2)")
                if let use = model.namedUse {
                    labeled("Use", use.title)
                }
                labeled("Source", "SecRandomCopyBytes")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.elevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.border.opacity(0.7), lineWidth: 1)
            )
        }
    }

    private func labeled(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(v)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.text)
        }
    }

    // MARK: Main

    private var mainPane: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border.opacity(0.7))
            fingerprint
            Divider().overlay(Theme.border.opacity(0.7))
            keyDisplay
            if model.keys.count > 1 {
                Divider().overlay(Theme.border.opacity(0.7))
                batchList
                    .frame(height: 120)
            }
            if !model.history.isEmpty {
                Divider().overlay(Theme.border.opacity(0.7))
                historyStrip
                    .frame(height: 96)
            }
            Divider().overlay(Theme.border.opacity(0.7))
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if model.copiedFlash {
                Text("Copied")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.phosphor)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.15), value: model.copiedFlash)
    }

    private var headerTitle: String {
        if case .uuidV4 = model.preset {
            return "UUID version 4"
        }
        if let use = model.namedUse {
            return "\(use.title) · \(model.bitCount)-bit key"
        }
        return "\(model.bitCount)-bit hex key"
    }

    private var headerSubtitle: String {
        let src = model.selected?.kind == .uuidV4 ? "RFC 4122 · random" : "CSPRNG"
        return "\(model.byteCount) bytes · \(model.byteCount * 2) hex digits · \(src)"
    }

    private var fingerprint: some View {
        FingerprintBar(bytes: model.displayBytes)
            .frame(height: 18)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
    }

    private var keyDisplay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                formattedBlock
                if !model.displayBytes.isEmpty {
                    HexDumpView(bytes: model.displayBytes, hexCase: model.hexCase)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg)
    }

    private var formattedBlock: some View {
        let text = model.scrambleBytes != nil
            ? HexEngine.format(model.displayBytes, style: model.format, hexCase: model.hexCase)
            : model.formattedSelected
        return VStack(alignment: .leading, spacing: 8) {
            groupLabel("KEY")
            Text(text.isEmpty ? "Generate a key" : text)
                .font(.system(size: formattedFontSize(text), weight: .medium, design: .monospaced))
                .foregroundStyle(text.isEmpty ? Theme.muted : Theme.phosphor)
                .textSelection(.enabled)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.tile)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .shadow(color: Theme.phosphor.opacity(0.08), radius: 12, y: 0)
        }
    }

    private func formattedFontSize(_ text: String) -> CGFloat {
        if text.count > 180 { return 12 }
        if text.count > 80 { return 14 }
        return 16
    }

    private var batchList: some View {
        VStack(alignment: .leading, spacing: 6) {
            groupLabel("BATCH")
                .padding(.horizontal, 18)
                .padding(.top, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(model.keys.enumerated()), id: \.element.id) { index, key in
                        Button {
                            model.select(key)
                        } label: {
                            HStack(spacing: 8) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 22, alignment: .trailing)
                                Text(key.formatted(style: compactStyle(for: key), hexCase: model.hexCase))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(model.selectedID == key.id ? Theme.phosphor : Theme.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(model.selectedID == key.id ? Theme.elevated : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(Theme.panel.opacity(0.5))
    }

    private func compactStyle(for key: GeneratedKey) -> HexFormat {
        if key.kind == .uuidV4 { return .uuid }
        return .compact
    }

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                groupLabel("SESSION")
                Spacer()
                Text("Not written to disk")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.history) { key in
                        Button {
                            model.select(key)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                FingerprintBar(bytes: key.bytes)
                                    .frame(width: 88, height: 8)
                                Text("\(key.bitCount) bit")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(model.selectedID == key.id ? Theme.phosphor : Theme.muted)
                                Text(String(HexEngine.hex(key.bytes, hexCase: model.hexCase).prefix(8)) + "…")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.text)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(model.selectedID == key.id ? Theme.elevated : Theme.tile)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(model.selectedID == key.id ? Theme.phosphor.opacity(0.5) : Theme.border.opacity(0.5), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }
        }
        .background(Theme.panel.opacity(0.35))
    }

    private var footer: some View {
        HStack {
            Text(footerStatus)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(model.statusIsError ? Theme.danger : Theme.muted)
                .lineLimit(1)
            Spacer()
            if let remaining = model.clipboardSecondsRemaining {
                Text("clears in \(remaining)s")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.amber)
            } else {
                Text("⌘R generate  ·  ⌘⇧C copy")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted.opacity(0.8))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var footerStatus: String {
        model.status ?? "Keys stay in this session until you copy or save them."
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
    }
}

struct FingerprintBar: View {
    let bytes: [UInt8]

    var body: some View {
        GeometryReader { geo in
            let n = max(bytes.count, 1)
            HStack(spacing: 0) {
                ForEach(Array(bytes.enumerated()), id: \.offset) { _, b in
                    Rectangle()
                        .fill(Theme.byteColor(b))
                        .frame(width: max(1, geo.size.width / CGFloat(n)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .opacity(bytes.isEmpty ? 0.15 : 1)
        }
    }
}

struct HexDumpView: View {
    let bytes: [UInt8]
    var hexCase: HexCase = .upper
    var columns: Int = 16

    private var compact: String {
        HexEngine.hex(bytes, hexCase: hexCase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DUMP")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(Theme.muted)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(rows, id: \.offset) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(String(format: "%04X", row.offset))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.amberDim)
                            .frame(width: 44, alignment: .trailing)

                        HStack(spacing: 3) {
                            ForEach(0..<columns, id: \.self) { col in
                                if col < row.chunk.count {
                                    Text(hexByte(at: row.offset + col))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Theme.phosphorDim)
                                        .frame(width: 22)
                                } else {
                                    Text("  ")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .frame(width: 22)
                                }
                                if col == 7 {
                                    Color.clear.frame(width: 6)
                                }
                            }
                        }

                        Text(HexEngine.asciiPreview(row.chunk))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.tile.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.border.opacity(0.6), lineWidth: 1)
            )
        }
    }

    private var rows: [(offset: Int, chunk: [UInt8])] {
        stride(from: 0, to: bytes.count, by: columns).map { start in
            let end = min(start + columns, bytes.count)
            return (start, Array(bytes[start..<end]))
        }
    }

    private func hexByte(at byteIndex: Int) -> String {
        let start = compact.index(compact.startIndex, offsetBy: byteIndex * 2)
        let end = compact.index(start, offsetBy: 2, limitedBy: compact.endIndex) ?? compact.endIndex
        return String(compact[start..<end])
    }
}
