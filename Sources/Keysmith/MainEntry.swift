import AppKit
import SwiftUI

@main
struct MainEntry {
    static func main() {
        let args = CommandLine.arguments

        if args.contains("--self-test") {
            if let err = SelfTest.run() {
                fputs("SELF-TEST FAILED: \(err)\n", stderr)
                exit(1)
            }
            print("SELF-TEST OK")
            exit(0)
        }

        if args.contains("--help") || args.contains("-h") {
            print(helpText)
            exit(0)
        }

        if args.contains("--version") {
            print("Keysmith \(AppVersion.short) (\(AppVersion.build))")
            exit(0)
        }

        if wantsCLI(args) {
            if cliConflict(args) {
                fputs("error: password flags and hex flags cannot be combined\n", stderr)
                exit(1)
            }
            if wantsHexCLI(args) {
                runHexCLI(args)
            } else {
                runCLI(args)
            }
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private static let helpText = """
    Keysmith — passwords and hex keys

    Usage:
      Keysmith                         Launch the app
      Keysmith --self-test             Password and hex checks
      Keysmith --version               Print version and exit

    Passwords (default when no hex flag is given):
      Keysmith --length N              Password length (4–128, default 24)
      Keysmith --count N               How many (1–50), one per line
      Keysmith --pin N                 Digits only, length N
      --no-upper / --no-lower / --no-digits / --no-special
      --digits-only                    Numbers only
      --exclude-ambiguous              Drop 0 O o I l 1 |
      --specials standard|extended|custom
      --custom-specials SET            Used with --specials custom

    Hex keys:
      Keysmith --bits N                N-bit key (multiple of 8)
      Keysmith --bytes N               N-byte key (1–1024)
      Keysmith --use NAME              aes-128|aes-192|aes-256|chacha20
      Keysmith --uuid                  UUID version 4
      --format compact|spaced|colon|dashed|prefixed|c|swift|uuid|base64
      --case upper|mixed|lower         Hex digit case (default upper)
      --lower / --mixed                Same as --case lower / --case mixed

    Either kind:
      --binary                         Raw bytes of one secret (requires --out)
      --out PATH                       Write to a file instead of stdout

    Examples:
      Keysmith --length 32
      Keysmith --length 32 --binary --out secret.key
      Keysmith --pin 6 --count 5
      Keysmith --specials custom --custom-specials '_-+='
      Keysmith --bits 256
      Keysmith --use aes-256 --binary --out aes.key
      Keysmith --bytes 32 --format colon --count 3
      Keysmith --uuid --lower
    """

    private static let passwordFlags: Set<String> = [
        "--length", "--pin",
        "--no-upper", "--no-lower", "--no-digits", "--no-special",
        "--digits-only", "--exclude-ambiguous",
        "--specials", "--custom-specials",
    ]

    private static let hexFlags: Set<String> = [
        "--bits", "--bytes", "--uuid", "--format",
        "--case", "--lower", "--mixed", "--use",
    ]

    private static let sharedFlags: Set<String> = [
        "--count", "--out", "-o", "--binary",
    ]

    private static func wantsCLI(_ args: [String]) -> Bool {
        args.contains { passwordFlags.contains($0) || hexFlags.contains($0) || sharedFlags.contains($0) }
    }

    private static func wantsHexCLI(_ args: [String]) -> Bool {
        args.contains { hexFlags.contains($0) }
    }

    private static func cliConflict(_ args: [String]) -> Bool {
        args.contains { passwordFlags.contains($0) } && wantsHexCLI(args)
    }

    private static func runCLI(_ args: [String]) {
        var options = PasswordOptions()

        if let pin = intValue(after: "--pin", in: args) {
            options.uppercase = false
            options.lowercase = false
            options.digits = true
            options.specials = false
            options.length = pin
        }

        if args.contains("--digits-only") {
            options.uppercase = false
            options.lowercase = false
            options.digits = true
            options.specials = false
        }

        if args.contains("--no-upper") { options.uppercase = false }
        if args.contains("--no-lower") { options.lowercase = false }
        if args.contains("--no-digits") { options.digits = false }
        if args.contains("--no-special") { options.specials = false }
        options.excludeAmbiguous = args.contains("--exclude-ambiguous")

        if let raw = value(after: "--specials", in: args) {
            guard let parsed = SpecialKind.parse(raw) else {
                fputs("error: unknown --specials \(raw) (standard|extended|custom)\n", stderr)
                exit(1)
            }
            options.specialKind = parsed
        }

        if let custom = value(after: "--custom-specials", in: args) {
            options.customSpecials = custom
            if !args.contains("--specials") {
                options.specialKind = .custom
            }
        }

        if let length = intValue(after: "--length", in: args) {
            options.length = length
        }

        if options.length < PasswordEngine.minLength || options.length > PasswordEngine.maxLength {
            fputs("error: --length must be \(PasswordEngine.minLength)–\(PasswordEngine.maxLength)\n", stderr)
            exit(1)
        }

        let count = intValue(after: "--count", in: args) ?? 1
        if count < 1 || count > PasswordEngine.maxCount {
            fputs("error: --count must be 1–\(PasswordEngine.maxCount)\n", stderr)
            exit(1)
        }

        let binary = args.contains("--binary")
        let outPath = value(after: "--out", in: args) ?? value(after: "-o", in: args)
        if binary {
            if count != 1 {
                fputs("error: binary export writes one password; omit --count\n", stderr)
                exit(1)
            }
            if outPath == nil {
                fputs("error: binary export requires --out\n", stderr)
                exit(1)
            }
        }

        var lines: [String] = []
        do {
            for _ in 0..<count {
                lines.append(try PasswordEngine.generate(options: options))
            }
        } catch PasswordEngineError.emptyCharset {
            fputs("error: turn on at least one character class\n", stderr)
            exit(1)
        } catch PasswordEngineError.invalidLength {
            fputs("error: length must be \(PasswordEngine.minLength)–\(PasswordEngine.maxLength)\n", stderr)
            exit(1)
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }

        if binary {
            guard let outPath else {
                fputs("error: binary export requires --out\n", stderr)
                exit(1)
            }
            do {
                let password = lines[0]
                let data = PasswordEngine.binaryData(password)
                try data.write(to: URL(fileURLWithPath: outPath), options: .atomic)
                fputs("wrote \(data.count) bytes → \(outPath)\n", stderr)
            } catch {
                fputs("error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }

        let payload = lines.joined(separator: "\n") + "\n"
        if let outPath {
            do {
                try payload.write(to: URL(fileURLWithPath: outPath), atomically: true, encoding: .utf8)
                fputs("wrote \(count) password\(count == 1 ? "" : "s") → \(outPath)\n", stderr)
            } catch {
                fputs("error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        } else {
            print(payload, terminator: "")
        }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func intValue(after flag: String, in args: [String]) -> Int? {
        guard let raw = value(after: flag, in: args) else { return nil }
        return Int(raw)
    }

    private static func runHexCLI(_ args: [String]) {
        let count = intValue(after: "--count", in: args) ?? 1
        if count < 1 || count > HexEngine.maxCount {
            fputs("error: --count must be 1–\(HexEngine.maxCount)\n", stderr)
            exit(1)
        }

        let formatRaw = value(after: "--format", in: args)
        let binary = args.contains("--binary") || formatRaw?.lowercased() == "binary"
        if binary, let formatRaw, formatRaw.lowercased() != "binary" {
            fputs("error: --binary cannot be combined with --format \(formatRaw)\n", stderr)
            exit(1)
        }

        var format = HexFormat.compact
        if !binary, let raw = formatRaw {
            guard let parsed = HexFormat.parse(raw) else {
                fputs("error: unknown --format \(raw)\n", stderr)
                exit(1)
            }
            format = parsed
        }

        let hexCase = parseHexCase(args)
        let uuidMode = args.contains("--uuid")
        let namedUse = parseUse(args)
        if uuidMode, namedUse != nil {
            fputs("error: --uuid cannot be combined with --use\n", stderr)
            exit(1)
        }

        let byteCount: Int
        if uuidMode {
            byteCount = 16
            if !binary, format == .compact, formatRaw == nil {
                format = .uuid
            }
        } else {
            byteCount = resolveByteCount(args, namedUse: namedUse)
        }

        let outPath = value(after: "--out", in: args) ?? value(after: "-o", in: args)

        if binary {
            if count != 1 {
                fputs("error: binary export writes one key; omit --count\n", stderr)
                exit(1)
            }
            guard let outPath else {
                fputs("error: binary export requires --out\n", stderr)
                exit(1)
            }
            do {
                let bytes = uuidMode ? try HexEngine.uuidV4Bytes() : try HexEngine.randomBytes(count: byteCount)
                let data = HexEngine.binaryData(bytes)
                try data.write(to: URL(fileURLWithPath: outPath), options: .atomic)
                fputs("wrote \(data.count) bytes → \(outPath)\n", stderr)
            } catch {
                fputs("error: \(error)\n", stderr)
                exit(1)
            }
            return
        }

        var lines: [String] = []
        do {
            for _ in 0..<count {
                let bytes = uuidMode ? try HexEngine.uuidV4Bytes() : try HexEngine.randomBytes(count: byteCount)
                lines.append(HexEngine.format(bytes, style: format, hexCase: hexCase))
            }
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }

        let payload = lines.joined(separator: "\n") + "\n"
        if let outPath {
            do {
                try payload.write(to: URL(fileURLWithPath: outPath), atomically: true, encoding: .utf8)
                fputs("wrote \(count) key\(count == 1 ? "" : "s") → \(outPath)\n", stderr)
            } catch {
                fputs("error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        } else {
            print(payload, terminator: "")
        }
    }

    private static func parseUse(_ args: [String]) -> NamedUse? {
        guard let raw = value(after: "--use", in: args) else { return nil }
        guard let parsed = NamedUse.parse(raw) else {
            fputs("error: unknown --use \(raw) (aes-128|aes-192|aes-256|chacha20)\n", stderr)
            exit(1)
        }
        return parsed
    }

    private static func resolveByteCount(_ args: [String], namedUse: NamedUse?) -> Int {
        let useBits = namedUse?.bits
        if let bits = intValue(after: "--bits", in: args) {
            if bits < 8 || bits % 8 != 0 || bits / 8 > HexEngine.maxBytes {
                fputs("error: --bits must be a multiple of 8 between 8 and \(HexEngine.maxBytes * 8)\n", stderr)
                exit(1)
            }
            if let useBits, useBits != bits {
                fputs("error: --use \(namedUse?.title ?? "name") is \(useBits)-bit, not \(bits)\n", stderr)
                exit(1)
            }
            return bits / 8
        }
        if let bytes = intValue(after: "--bytes", in: args) {
            if bytes < HexEngine.minBytes || bytes > HexEngine.maxBytes {
                fputs("error: --bytes must be \(HexEngine.minBytes)–\(HexEngine.maxBytes)\n", stderr)
                exit(1)
            }
            if let useBits, useBits / 8 != bytes {
                fputs("error: --use \(namedUse?.title ?? "name") is \(useBits / 8) bytes, not \(bytes)\n", stderr)
                exit(1)
            }
            return bytes
        }
        if let useBits {
            return useBits / 8
        }
        return 32
    }

    private static func parseHexCase(_ args: [String]) -> HexCase {
        let hasLower = args.contains("--lower")
        let hasMixed = args.contains("--mixed")
        let hasCase = args.contains("--case")
        if [hasLower, hasMixed, hasCase].filter({ $0 }).count > 1 {
            fputs("error: use only one of --case, --lower, --mixed\n", stderr)
            exit(1)
        }
        if let raw = value(after: "--case", in: args) {
            guard let parsed = HexCase.parse(raw) else {
                fputs("error: unknown --case \(raw) (upper|mixed|lower)\n", stderr)
                exit(1)
            }
            return parsed
        }
        if hasMixed { return .mixed }
        if hasLower { return .lower }
        return .upper
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        let rootView = ContentView()
        let hosting = NSHostingView(rootView: rootView)

        let mode = savedWorkspace()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = mode == .hex ? "Keysmith — Hex" : "Keysmith"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = mode == .hex ? HexTheme.windowNS : PasswordTheme.windowNS
        window.contentView = hosting
        window.minSize = NSSize(width: 860, height: 600)
        window.center()
        window.setFrameAutosaveName("KeysmithMainWindow")
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardWatch.clearIfOwned()
        NotificationCenter.default.post(name: .keysmithWillTerminate, object: nil)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc private func showPassword(_ sender: Any?) {
        NotificationCenter.default.post(name: .keysmithWorkspace, object: Workspace.password.rawValue)
    }

    @objc private func showHex(_ sender: Any?) {
        NotificationCenter.default.post(name: .keysmithWorkspace, object: Workspace.hex.rawValue)
    }

    @objc private func generate(_ sender: Any?) {
        NotificationCenter.default.post(name: .keysmithGenerate, object: nil)
    }

    @objc private func copyPassword(_ sender: Any?) {
        NotificationCenter.default.post(name: .keysmithCopy, object: nil)
    }

    @objc private func copyAll(_ sender: Any?) {
        NotificationCenter.default.post(name: .keysmithCopyAll, object: nil)
    }

    @objc private func savePasswords(_ sender: Any?) {
        NotificationCenter.default.post(name: .keysmithSave, object: nil)
    }

    @objc private func saveBinary(_ sender: Any?) {
        NotificationCenter.default.post(name: .keysmithSaveBinary, object: nil)
    }

    @objc private func clearPasswords(_ sender: Any?) {
        NotificationCenter.default.post(name: .keysmithClear, object: nil)
    }

    @objc private func clearClipboardNow(_ sender: Any?) {
        NotificationCenter.default.post(name: .keysmithClearClipboard, object: nil)
    }

    @objc private func setClipboardDelay(_ sender: NSMenuItem) {
        NotificationCenter.default.post(name: .keysmithClipboardDelay, object: sender.tag)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let mode = savedWorkspace()
        if menuItem.action == #selector(showPassword(_:)) {
            menuItem.state = mode == .password ? .on : .off
            return true
        }
        if menuItem.action == #selector(showHex(_:)) {
            menuItem.state = mode == .hex ? .on : .off
            return true
        }
        if menuItem.action == #selector(copyPassword(_:)) {
            menuItem.title = mode == .hex ? "Copy Key" : "Copy Password"
        }
        if menuItem.action == #selector(copyAll(_:)) {
            menuItem.title = mode == .hex ? "Copy All Keys" : "Copy All Passwords"
        }
        if menuItem.action == #selector(savePasswords(_:)) {
            menuItem.title = mode == .hex ? "Save Hex…" : "Save Text…"
        }
        if menuItem.action == #selector(setClipboardDelay(_:)) {
            let current = UserDefaults.standard.integer(forKey: ClipboardClear.defaultsKey)
            let effective = UserDefaults.standard.object(forKey: ClipboardClear.defaultsKey) == nil ? 30 : current
            menuItem.state = menuItem.tag == effective ? .on : .off
            return true
        }
        if menuItem.action == #selector(clearClipboardNow(_:)) {
            return NSPasteboard.general.string(forType: .string) != nil
        }
        return true
    }

    private func savedWorkspace() -> Workspace {
        if let raw = UserDefaults.standard.string(forKey: WorkspaceStore.key),
           let mode = Workspace(rawValue: raw) {
            return mode
        }
        return .password
    }

    @objc private func showAbout(_ sender: Any?) {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? AppVersion.short
        let build = info?["CFBundleVersion"] as? String ?? AppVersion.build
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Keysmith",
            .version: version,
            .applicationVersion: "Version \(version) (\(build))",
            .credits: NSAttributedString(
                string: """
                Cryptographically random passwords and hex keys.

                Password and Hex share one window. Entropy comes from \
                SecRandomCopyBytes. Secrets stay in memory for this \
                session and are not written to disk unless you copy \
                or save them.
                """,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ),
        ]
        if let icon = NSApp.applicationIconImage {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let about = appMenu.addItem(withTitle: "About Keysmith", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Keysmith", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Keysmith", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        let save = fileMenu.addItem(withTitle: "Save Text…", action: #selector(savePasswords(_:)), keyEquivalent: "s")
        save.target = self
        let saveBinary = fileMenu.addItem(withTitle: "Save Binary…", action: #selector(saveBinary(_:)), keyEquivalent: "s")
        saveBinary.keyEquivalentModifierMask = [.command, .shift]
        saveBinary.target = self
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        let copyPassword = editMenu.addItem(withTitle: "Copy Password", action: #selector(copyPassword(_:)), keyEquivalent: "c")
        copyPassword.keyEquivalentModifierMask = [.command, .shift]
        copyPassword.target = self
        let copyAll = editMenu.addItem(withTitle: "Copy All Passwords", action: #selector(copyAll(_:)), keyEquivalent: "")
        copyAll.target = self
        let clearClipboard = editMenu.addItem(
            withTitle: "Clear Clipboard",
            action: #selector(clearClipboardNow(_:)),
            keyEquivalent: ""
        )
        clearClipboard.target = self
        editMenu.addItem(NSMenuItem.separator())
        let clear = editMenu.addItem(withTitle: "Clear Session", action: #selector(clearPasswords(_:)), keyEquivalent: "k")
        clear.target = self

        let clipboardMenuItem = NSMenuItem(title: "Clear Clipboard After", action: nil, keyEquivalent: "")
        let clipboardMenu = NSMenu(title: "Clear Clipboard After")
        clipboardMenuItem.submenu = clipboardMenu
        for delay in ClipboardClearDelay.allCases {
            let item = clipboardMenu.addItem(
                withTitle: delay.menuTitle,
                action: #selector(setClipboardDelay(_:)),
                keyEquivalent: ""
            )
            item.tag = delay.rawValue
            item.target = self
        }
        editMenu.addItem(clipboardMenuItem)

        let keyMenuItem = NSMenuItem()
        mainMenu.addItem(keyMenuItem)
        let keyMenu = NSMenu(title: "Key")
        keyMenuItem.submenu = keyMenu
        let passwordItem = keyMenu.addItem(withTitle: "Password", action: #selector(showPassword(_:)), keyEquivalent: "1")
        passwordItem.target = self
        let hexItem = keyMenu.addItem(withTitle: "Hex", action: #selector(showHex(_:)), keyEquivalent: "2")
        hexItem.target = self
        keyMenu.addItem(NSMenuItem.separator())
        let generate = keyMenu.addItem(withTitle: "Generate", action: #selector(generate(_:)), keyEquivalent: "r")
        generate.target = self

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
