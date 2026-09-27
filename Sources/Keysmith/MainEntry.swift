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
            runCLI(args)
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private static let helpText = """
    Keysmith — cryptographically random passwords

    Usage:
      Keysmith                         Launch the app
      Keysmith --self-test             RNG / charset checks
      Keysmith --version               Print version and exit
      Keysmith --length N              Password length (4–128, default 24)
      Keysmith --count N               How many passwords (1–50), one per line
      Keysmith --pin N                 Digits only, length N

    Character classes (all on by default):
      --no-upper                       Omit A–Z
      --no-lower                       Omit a–z
      --no-digits                      Omit 0–9
      --no-special                     Omit punctuation
      --digits-only                    Numbers only

    Options:
      --exclude-ambiguous              Drop 0 O o I l 1 |
      --specials standard|extended|custom
      --custom-specials SET            Used with --specials custom
      --binary                         Raw bytes of one password (requires --out)
      --out PATH                       Write to a file instead of stdout

    Examples:
      Keysmith --length 32
      Keysmith --length 32 --binary --out secret.key
      Keysmith --length 16 --no-special
      Keysmith --pin 6 --count 5
      Keysmith --exclude-ambiguous --length 24
      Keysmith --specials custom --custom-specials '_-+='
    """

    private static func wantsCLI(_ args: [String]) -> Bool {
        let flags: Set<String> = [
            "--length", "--count", "--pin", "--out", "-o",
            "--no-upper", "--no-lower", "--no-digits", "--no-special",
            "--digits-only", "--exclude-ambiguous",
            "--specials", "--custom-specials", "--binary",
        ]
        return args.contains(where: { flags.contains($0) })
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
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        let rootView = ContentView()
        let hosting = NSHostingView(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Keysmith"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.windowNS
        window.contentView = hosting
        window.minSize = NSSize(width: 760, height: 520)
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
                Cryptographically random passwords.

                Entropy comes from SecRandomCopyBytes. Passwords stay in \
                memory for this session and are not written to disk \
                unless you copy or save them.
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

        let passwordMenuItem = NSMenuItem()
        mainMenu.addItem(passwordMenuItem)
        let passwordMenu = NSMenu(title: "Password")
        passwordMenuItem.submenu = passwordMenu
        let generate = passwordMenu.addItem(withTitle: "Generate", action: #selector(generate(_:)), keyEquivalent: "r")
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
