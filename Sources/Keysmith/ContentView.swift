import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var shell: ShellModel
    @StateObject private var clipboard: ClipboardSession
    @StateObject private var passwords: PasswordModel
    @StateObject private var hex: HexModel

    init() {
        let clip = ClipboardSession()
        _clipboard = StateObject(wrappedValue: clip)
        _shell = StateObject(wrappedValue: ShellModel())
        _passwords = StateObject(wrappedValue: PasswordModel(clipboard: clip))
        _hex = StateObject(wrappedValue: HexModel(clipboard: clip))
    }

    var body: some View {
        Group {
            switch shell.mode {
            case .password:
                PasswordWorkspace(model: passwords, shell: shell)
            case .hex:
                HexWorkspace(model: hex, shell: shell)
            }
        }
        .onAppear { applyChrome(shell.mode) }
        .onChange(of: shell.mode) { mode in
            UserDefaults.standard.set(mode.rawValue, forKey: WorkspaceStore.key)
            applyChrome(mode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .keysmithWorkspace)) { note in
            guard let raw = note.object as? String, let mode = Workspace(rawValue: raw) else { return }
            shell.mode = mode
        }
    }

    private func applyChrome(_ mode: Workspace) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) else { return }
        switch mode {
        case .password:
            window.title = "Keysmith"
            window.backgroundColor = PasswordTheme.windowNS
        case .hex:
            window.title = "Keysmith — Hex"
            window.backgroundColor = HexTheme.windowNS
        }
    }
}
