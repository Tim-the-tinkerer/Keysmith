import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

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
        .tint(Theme.brass)
        .preferredColorScheme(.dark)
        .onChange(of: model.options) { _ in model.persistPrefs() }
        .onChange(of: model.count) { _ in model.persistPrefs() }
        .onChange(of: model.clipboardClear) { delay in
            model.setClipboardDelay(delay)
        }
        .onAppear {
            if model.passwords.isEmpty {
                model.generate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithGenerate)) { _ in model.generate() }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithCopy)) { _ in model.copySelected() }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithCopyAll)) { _ in model.copyAll() }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithSave)) { _ in model.saveText() }
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
                brand
                lengthSection
                classSection
                if model.options.specials {
                    specialsSection
                }
                optionsRow
                clipboardRow
                batchRow
                actionRow
                entropyCard
            }
            .padding(16)
        }
        .background(Theme.panel)
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("KEYSMITH")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(2.6)
                .foregroundStyle(Theme.brass)
            Text("Password generator")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 4)
    }

    private var lengthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                groupLabel("LENGTH")
                Spacer()
                Text("\(model.options.length)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.brass)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(PasswordEngine.lengthPresets, id: \.self) { length in
                    lengthChip(length)
                }
            }
            Slider(
                value: Binding(
                    get: { Double(model.options.length) },
                    set: { model.setLength(Int($0.rounded())) }
                ),
                in: Double(PasswordEngine.minLength)...Double(PasswordEngine.maxLength),
                step: 1
            )
            .tint(Theme.brass)
            HStack {
                Text("\(PasswordEngine.minLength)")
                Spacer()
                Text("\(PasswordEngine.maxLength)")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.muted)
        }
    }

    private func lengthChip(_ length: Int) -> some View {
        let selected = model.options.length == length
        return Button {
            model.setLength(length)
        } label: {
            Text("\(length)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Theme.bg : Theme.text)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Theme.brass : Theme.elevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? Theme.brassGlow : Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var classSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupLabel("CHARACTERS")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(CharClass.allCases) { cls in
                    classChip(cls)
                }
            }
        }
    }

    private func classChip(_ cls: CharClass) -> some View {
        let on = model.isEnabled(cls)
        return Button {
            model.toggle(cls)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(cls.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text(cls.sample)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(on ? Theme.bg.opacity(0.75) : Theme.color(for: cls).opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(on ? Theme.bg : Theme.text)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? Theme.color(for: cls) : Theme.elevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(on ? Theme.color(for: cls).opacity(0.9) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Include \(cls.title.lowercased()) characters")
    }

    private var specialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupLabel("SPECIALS")
            HStack(spacing: 6) {
                ForEach(SpecialKind.allCases) { kind in
                    let selected = model.options.specialKind == kind
                    Button {
                        model.options.specialKind = kind
                    } label: {
                        Text(kind.title)
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected ? Theme.bg : Theme.text)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(selected ? Theme.brass : Theme.elevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(selected ? Theme.brassGlow : Theme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(kind.help)
                }
            }
            if model.options.specialKind == .custom {
                TextField("!@#$%^&*", text: $model.options.customSpecials)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.tile)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            } else {
                Text(String(PasswordEngine.specials(for: model.options)))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.special)
                    .lineLimit(2)
            }
        }
    }

    private var optionsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupLabel("OPTIONS")
            Button {
                model.options.excludeAmbiguous.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.options.excludeAmbiguous ? "checkmark.square.fill" : "square")
                        .foregroundStyle(model.options.excludeAmbiguous ? Theme.brass : Theme.muted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Exclude lookalikes")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text("0 O o I l 1 |")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.elevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.border.opacity(0.7), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
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
            .help("Clear the pasteboard after a delay if it still holds the password Keysmith copied.")
        }
    }

    private var batchRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            groupLabel("BATCH")
            HStack(spacing: 8) {
                Stepper(value: $model.count, in: 1...PasswordEngine.maxCount) {
                    Text("\(model.count)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .frame(minWidth: 28, alignment: .leading)
                }
                Text(model.count == 1 ? "password" : "passwords")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
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
            .buttonStyle(KeysmithButtonStyle(kind: .primary))
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(model.isGenerating)

            HStack(spacing: 6) {
                Button("Copy") { model.copySelected() }
                    .buttonStyle(KeysmithButtonStyle(kind: .secondary))
                    .disabled(model.selected == nil || model.scramble != nil)
                Button("Copy all") { model.copyAll() }
                    .buttonStyle(KeysmithButtonStyle(kind: .secondary))
                    .disabled(model.passwords.isEmpty)
            }
            HStack(spacing: 6) {
                Button("Save text…") { model.saveText() }
                    .buttonStyle(KeysmithButtonStyle(kind: .ghost))
                    .disabled(model.selected == nil)
                    .help("Save passwords as text. Treat the file as a secret.")
                Button("Save binary…") { model.saveBinary() }
                    .buttonStyle(KeysmithButtonStyle(kind: .ghost))
                    .disabled(model.selected == nil)
                    .help("Save the selected password as raw bytes, with no trailing newline.")
            }
        }
    }

    private var entropyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            groupLabel("ENTROPY")
            VStack(alignment: .leading, spacing: 4) {
                labeled("Strength", model.strength.title)
                labeled("Bits", String(format: "%.0f", model.entropyBits))
                labeled("Pool", "\(model.poolSize) chars")
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
                .foregroundStyle(k == "Strength" ? Theme.strengthColor(model.strength) : Theme.text)
        }
    }

    // MARK: Main

    private var mainPane: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border.opacity(0.7))
            strengthBar
            Divider().overlay(Theme.border.opacity(0.7))
            passwordDisplay
            compositionRow
            if model.passwords.count > 1 {
                Divider().overlay(Theme.border.opacity(0.7))
                batchList
                    .frame(height: 120)
            }
            if !model.history.isEmpty {
                Divider().overlay(Theme.border.opacity(0.7))
                historyStrip
                    .frame(height: 108)
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
                    .foregroundStyle(Theme.brass)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.15), value: model.copiedFlash)
    }

    private var headerTitle: String {
        "\(model.options.length)-character password"
    }

    private var headerSubtitle: String {
        let classes = model.options.enabledClasses.map { $0.title.lowercased() }
        if classes.isEmpty { return "No character classes selected" }
        return classes.joined(separator: " · ")
    }

    private var strengthBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.strength.title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Theme.strengthColor(model.strength))
                Spacer()
                Text("\(Int(model.entropyBits.rounded())) bits")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            GeometryReader { geo in
                let fraction = min(1, max(0, model.entropyBits / 128.0))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.elevated)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.strengthColor(model.strength))
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var passwordDisplay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                groupLabel("PASSWORD")
                Button {
                    model.copySelected()
                } label: {
                    Text(attributedPassword)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.tile)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                        .shadow(color: Theme.brass.opacity(0.08), radius: 12, y: 0)
                }
                .buttonStyle(.plain)
                .disabled(model.displayPassword.isEmpty || model.scramble != nil)
                .help("Click to copy")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg)
    }

    private var attributedPassword: AttributedString {
        let raw = model.displayPassword
        if raw.isEmpty {
            var empty = AttributedString("Generate a password")
            empty.foregroundColor = Theme.muted
            empty.font = .system(size: 16, weight: .medium)
            return empty
        }
        var result = AttributedString()
        let size: CGFloat = raw.count > 64 ? 15 : (raw.count > 36 ? 18 : 22)
        for ch in raw {
            var piece = AttributedString(String(ch))
            piece.foregroundColor = Theme.color(for: PasswordEngine.classify(ch))
            piece.font = .system(size: size, weight: .medium, design: .monospaced)
            result.append(piece)
        }
        return result
    }

    private var compositionRow: some View {
        let counts = PasswordEngine.counts(in: model.displayPassword)
        return HStack(spacing: 14) {
            ForEach(CharClass.allCases) { cls in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.color(for: cls))
                        .frame(width: 7, height: 7)
                    Text("\(counts[cls, default: 0])")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                    Text(cls.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .opacity(model.displayPassword.isEmpty ? 0.35 : 1)
    }

    private var batchList: some View {
        VStack(alignment: .leading, spacing: 6) {
            groupLabel("BATCH")
                .padding(.horizontal, 18)
                .padding(.top, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(model.passwords.enumerated()), id: \.element.id) { index, password in
                        Button {
                            model.select(password)
                        } label: {
                            HStack(spacing: 8) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 22, alignment: .trailing)
                                Text(password.value)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(model.selectedID == password.id ? Theme.brass : Theme.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(model.selectedID == password.id ? Theme.elevated : Color.clear)
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
                    ForEach(model.history) { password in
                        Button {
                            model.select(password)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(password.length) ch")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(model.selectedID == password.id ? Theme.brass : Theme.muted)
                                Text(preview(password.value))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.text)
                            }
                            .padding(8)
                            .frame(width: 132, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(model.selectedID == password.id ? Theme.elevated : Theme.tile)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        model.selectedID == password.id ? Theme.brass.opacity(0.5) : Theme.border.opacity(0.5),
                                        lineWidth: 1
                                    )
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

    private func preview(_ value: String) -> String {
        if value.count <= 10 { return value }
        return String(value.prefix(8)) + "…"
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
                    .foregroundStyle(Theme.brass)
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
        if let status = model.status { return status }
        if model.optionsDirty {
            return "Options changed — generate to apply."
        }
        return "Passwords stay in this session until you copy or save them."
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
    }
}
