import AppKit
import SwiftUI

enum Theme {
    static let bg = Color(red: 0.070, green: 0.062, blue: 0.050)
    static let panel = Color(red: 0.100, green: 0.090, blue: 0.074)
    static let elevated = Color(red: 0.155, green: 0.132, blue: 0.098)
    static let tile = Color(red: 0.118, green: 0.105, blue: 0.084)
    static let border = Color(red: 0.46, green: 0.36, blue: 0.20)
    static let brass = Color(red: 0.93, green: 0.75, blue: 0.34)
    static let brassDim = Color(red: 0.72, green: 0.56, blue: 0.22)
    static let brassGlow = Color(red: 0.99, green: 0.88, blue: 0.52)
    static let text = Color(red: 0.95, green: 0.93, blue: 0.86)
    static let muted = Color(red: 0.58, green: 0.53, blue: 0.43)
    static let danger = Color(red: 0.86, green: 0.40, blue: 0.40)
    static let upper = Color(red: 0.93, green: 0.75, blue: 0.34)
    static let lower = Color(red: 0.86, green: 0.84, blue: 0.74)
    static let digit = Color(red: 0.58, green: 0.80, blue: 0.94)
    static let special = Color(red: 0.94, green: 0.54, blue: 0.38)

    static let windowNS = NSColor(red: 0.070, green: 0.062, blue: 0.050, alpha: 1)

    static func color(for cls: CharClass) -> Color {
        switch cls {
        case .uppercase: return upper
        case .lowercase: return lower
        case .digits: return digit
        case .specials: return special
        }
    }

    static func strengthColor(_ strength: Strength) -> Color {
        switch strength {
        case .tooWeak: return danger
        case .weak: return Color(red: 0.90, green: 0.48, blue: 0.28)
        case .fair: return Color(red: 0.90, green: 0.68, blue: 0.28)
        case .strong: return brass
        case .excellent: return Color(red: 0.55, green: 0.82, blue: 0.48)
        case .paranoid: return Color(red: 0.42, green: 0.90, blue: 0.68)
        }
    }
}

struct KeysmithButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(stroke, lineWidth: 1)
            )
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.bg
        case .secondary, .ghost: return Theme.text
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Theme.brass
        case .secondary: return Theme.elevated
        case .ghost: return Color.clear
        }
    }

    private var stroke: Color {
        switch kind {
        case .primary: return Theme.brassGlow
        case .secondary: return Theme.border
        case .ghost: return Theme.border.opacity(0.6)
        }
    }
}

extension Notification.Name {
    static let keysmithGenerate = Notification.Name("keysmith.generate")
    static let keysmithCopy = Notification.Name("keysmith.copy")
    static let keysmithCopyAll = Notification.Name("keysmith.copyAll")
    static let keysmithSave = Notification.Name("keysmith.save")
    static let keysmithSaveBinary = Notification.Name("keysmith.saveBinary")
    static let keysmithClear = Notification.Name("keysmith.clear")
    static let keysmithClipboardDelay = Notification.Name("keysmith.clipboardDelay")
    static let keysmithClearClipboard = Notification.Name("keysmith.clearClipboard")
    static let keysmithWillTerminate = Notification.Name("keysmith.willTerminate")
}
