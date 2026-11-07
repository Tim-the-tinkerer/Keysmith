import Foundation
import Security

enum PasswordEngineError: Error, Equatable {
    case invalidLength
    case emptyCharset
    case rngFailed(OSStatus)
}

enum SpecialKind: String, CaseIterable, Identifiable {
    case standard
    case extended
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .extended: return "Extended"
        case .custom: return "Custom"
        }
    }

    var help: String {
        switch self {
        case .standard: return "!@#$%^&*"
        case .extended: return "punctuation"
        case .custom: return "your set"
        }
    }

    static func parse(_ raw: String) -> SpecialKind? {
        switch raw.lowercased() {
        case "standard", "std", "basic": return .standard
        case "extended", "ext", "full": return .extended
        case "custom": return .custom
        default: return nil
        }
    }
}

enum CharClass: String, CaseIterable, Identifiable {
    case uppercase
    case lowercase
    case digits
    case specials

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uppercase: return "Uppercase"
        case .lowercase: return "Lowercase"
        case .digits: return "Numbers"
        case .specials: return "Specials"
        }
    }

    var sample: String {
        switch self {
        case .uppercase: return "A–Z"
        case .lowercase: return "a–z"
        case .digits: return "0–9"
        case .specials: return "#?!"
        }
    }
}

enum Strength: Equatable {
    case tooWeak
    case weak
    case fair
    case strong
    case excellent
    case paranoid

    var title: String {
        switch self {
        case .tooWeak: return "Too weak"
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .strong: return "Strong"
        case .excellent: return "Excellent"
        case .paranoid: return "Paranoid"
        }
    }

    static func from(bits: Double) -> Strength {
        switch bits {
        case ..<28: return .tooWeak
        case 28..<40: return .weak
        case 40..<60: return .fair
        case 60..<80: return .strong
        case 80..<128: return .excellent
        default: return .paranoid
        }
    }
}

struct PasswordOptions: Equatable {
    var length: Int = 24
    var uppercase: Bool = true
    var lowercase: Bool = true
    var digits: Bool = true
    var specials: Bool = true
    var excludeAmbiguous: Bool = false
    var specialKind: SpecialKind = .standard
    var customSpecials: String = "!@#$%^&*"

    var enabledClasses: [CharClass] {
        var classes: [CharClass] = []
        if uppercase { classes.append(.uppercase) }
        if lowercase { classes.append(.lowercase) }
        if digits { classes.append(.digits) }
        if specials { classes.append(.specials) }
        return classes
    }
}

struct GeneratedPassword: Identifiable, Equatable {
    let id: UUID
    let value: String
    let created: Date
    let options: PasswordOptions

    var length: Int { value.count }
}

enum PasswordEngine {
    static let minLength = 4
    static let passwordMinLength = 16
    static let maxLength = 128
    static let maxCount = 50
    static let lengthPresets = [16, 24, 32, 48, 64]

    static let uppercaseAll = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let lowercaseAll = Array("abcdefghijklmnopqrstuvwxyz")
    static let digitsAll = Array("0123456789")
    static let specialsStandard = Array("!@#$%^&*")
    static let specialsExtended = Array("!@#$%^&*()-_=+[]{}|;:,.<>?/~")
    /// Lookalikes that are easy to confuse in fonts: 0/O/o, 1/I/l, pipe.
    static let ambiguous: Set<Character> = Set("0OoIl1|")

    static func pool(for cls: CharClass, options: PasswordOptions) -> [Character] {
        let raw: [Character]
        switch cls {
        case .uppercase: raw = uppercaseAll
        case .lowercase: raw = lowercaseAll
        case .digits: raw = digitsAll
        case .specials: raw = specials(for: options)
        }
        if options.excludeAmbiguous {
            return raw.filter { !ambiguous.contains($0) }
        }
        return raw
    }

    static func specials(for options: PasswordOptions) -> [Character] {
        switch options.specialKind {
        case .standard:
            return specialsStandard
        case .extended:
            return specialsExtended
        case .custom:
            return uniqueSpecials(options.customSpecials)
        }
    }

    static func uniqueSpecials(_ raw: String) -> [Character] {
        var seen = Set<Character>()
        var out: [Character] = []
        for ch in raw where ch.isASCII && !ch.isWhitespace && !ch.isLetter && !ch.isNumber {
            if seen.insert(ch).inserted {
                out.append(ch)
            }
        }
        return out
    }

    static func combinedPool(options: PasswordOptions) -> [Character] {
        var seen = Set<Character>()
        var out: [Character] = []
        for cls in options.enabledClasses {
            for ch in pool(for: cls, options: options) where seen.insert(ch).inserted {
                out.append(ch)
            }
        }
        return out
    }

    static func classPools(options: PasswordOptions) -> [(CharClass, [Character])] {
        options.enabledClasses.compactMap { cls in
            let chars = pool(for: cls, options: options)
            return chars.isEmpty ? nil : (cls, chars)
        }
    }

    static func entropyBits(options: PasswordOptions) -> Double {
        let size = combinedPool(options: options).count
        let length = clampedLength(options.length)
        guard size > 1, length > 0 else { return 0 }
        return Double(length) * log2(Double(size))
    }

    static func strength(options: PasswordOptions) -> Strength {
        Strength.from(bits: entropyBits(options: options))
    }

    static func clampedLength(_ length: Int) -> Int {
        min(maxLength, max(minLength, length))
    }

    /// Password length used by the window. Pins and the engine floor can be shorter.
    static func clampedPasswordLength(_ length: Int) -> Int {
        min(maxLength, max(passwordMinLength, length))
    }

    static func classify(_ ch: Character) -> CharClass {
        if ch.isNumber { return .digits }
        if ch.isUppercase { return .uppercase }
        if ch.isLowercase { return .lowercase }
        return .specials
    }

    /// Raw UTF-8 bytes of the password. No trailing newline, so a saved key file is the secret itself.
    static func binaryData(_ password: String) -> Data {
        Data(password.utf8)
    }

    static func counts(in password: String) -> [CharClass: Int] {
        var result: [CharClass: Int] = [:]
        for ch in password {
            let cls = classify(ch)
            result[cls, default: 0] += 1
        }
        return result
    }

    static func generate(options: PasswordOptions) throws -> String {
        let length = options.length
        guard length >= minLength, length <= maxLength else {
            throw PasswordEngineError.invalidLength
        }

        let pools = classPools(options: options)
        guard !pools.isEmpty else {
            throw PasswordEngineError.emptyCharset
        }

        var combined: [Character] = []
        var seen = Set<Character>()
        for (_, chars) in pools {
            for ch in chars where seen.insert(ch).inserted {
                combined.append(ch)
            }
        }
        guard !combined.isEmpty else {
            throw PasswordEngineError.emptyCharset
        }

        var chars: [Character] = []
        chars.reserveCapacity(length)

        if length >= pools.count {
            for (_, pool) in pools {
                chars.append(try pick(from: pool))
            }
        }

        while chars.count < length {
            chars.append(try pick(from: combined))
        }

        try shuffle(&chars)
        return String(chars)
    }

    static func randomBytes(count: Int) throws -> [UInt8] {
        guard count > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        guard status == errSecSuccess else {
            throw PasswordEngineError.rngFailed(status)
        }
        return bytes
    }

    static func randomInt(upperBound: Int) throws -> Int {
        guard upperBound > 0 else {
            throw PasswordEngineError.emptyCharset
        }
        if upperBound == 1 { return 0 }

        if upperBound <= 256 {
            let limit = 256 - (256 % upperBound)
            while true {
                let bytes = try randomBytes(count: 1)
                let value = Int(bytes[0])
                if value < limit {
                    return value % upperBound
                }
            }
        }

        let bound = UInt32(upperBound)
        let limit = UInt32.max - (UInt32.max % bound)
        while true {
            let bytes = try randomBytes(count: 4)
            let value = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            if value < limit {
                return Int(value % bound)
            }
        }
    }

    private static func pick(from pool: [Character]) throws -> Character {
        pool[try randomInt(upperBound: pool.count)]
    }

    private static func shuffle(_ chars: inout [Character]) throws {
        guard chars.count > 1 else { return }
        for i in stride(from: chars.count - 1, through: 1, by: -1) {
            let j = try randomInt(upperBound: i + 1)
            chars.swapAt(i, j)
        }
    }
}
