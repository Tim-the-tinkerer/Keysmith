import Foundation
import Security

enum HexEngineError: Error, Equatable {
    case invalidLength
    case rngFailed(OSStatus)
}

enum HexFormat: String, CaseIterable, Identifiable {
    case compact
    case spaced
    case colon
    case dashed
    case prefixed
    case cArray
    case swiftArray
    case uuid
    case base64

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .spaced: return "Spaced"
        case .colon: return "Colon"
        case .dashed: return "Dashed"
        case .prefixed: return "0x prefix"
        case .cArray: return "C array"
        case .swiftArray: return "Swift array"
        case .uuid: return "UUID"
        case .base64: return "Base64"
        }
    }

    var help: String {
        switch self {
        case .compact: return "A1B2C3D4"
        case .spaced: return "A1 B2 C3 D4"
        case .colon: return "A1:B2:C3:D4"
        case .dashed: return "A1B2-C3D4"
        case .prefixed: return "0xA1B2C3D4"
        case .cArray: return "{ 0xA1, 0xB2 }"
        case .swiftArray: return "[0xA1, 0xB2]"
        case .uuid: return "8-4-4-4-12"
        case .base64: return "RFC 4648"
        }
    }

    static func parse(_ raw: String) -> HexFormat? {
        switch raw.lowercased() {
        case "compact", "hex", "raw": return .compact
        case "spaced", "space", "bytes": return .spaced
        case "colon", "mac": return .colon
        case "dashed", "dash", "groups": return .dashed
        case "prefixed", "0x", "prefix": return .prefixed
        case "c", "carray", "c-array": return .cArray
        case "swift", "swiftarray", "swift-array": return .swiftArray
        case "uuid": return .uuid
        case "base64", "b64": return .base64
        default: return nil
        }
    }
}

enum HexCase: String, CaseIterable, Identifiable {
    case upper
    case mixed
    case lower

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upper: return "UPPER"
        case .mixed: return "Mixed"
        case .lower: return "lower"
        }
    }

    static func parse(_ raw: String) -> HexCase? {
        switch raw.lowercased() {
        case "upper", "uppercase", "upper-case": return .upper
        case "lower", "lowercase", "lower-case": return .lower
        case "mixed", "mix", "random": return .mixed
        default: return nil
        }
    }
}

enum HexEngine {
    static let minBytes = 1
    static let maxBytes = 1024
    static let maxCount = 50

    static let bitPresets: [Int] = [64, 128, 192, 256, 384, 512]

    static func randomBytes(count: Int) throws -> [UInt8] {
        guard count >= minBytes, count <= maxBytes else {
            throw HexEngineError.invalidLength
        }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        guard status == errSecSuccess else {
            throw HexEngineError.rngFailed(status)
        }
        return bytes
    }

    /// RFC 4122 UUID version 4 (random) as 16 bytes.
    static func uuidV4Bytes() throws -> [UInt8] {
        var bytes = try randomBytes(count: 16)
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes
    }

    static func hex(_ bytes: [UInt8], hexCase: HexCase, separator: String = "") -> String {
        let compact: String
        switch hexCase {
        case .upper:
            compact = bytes.map { String(format: "%02X", $0) }.joined()
        case .lower:
            compact = bytes.map { String(format: "%02x", $0) }.joined()
        case .mixed:
            compact = mixedHex(bytes)
        }
        if separator.isEmpty { return compact }
        return grouped(compact, every: 2, separator: separator)
    }

    static func format(_ bytes: [UInt8], style: HexFormat, hexCase: HexCase) -> String {
        let compact = hex(bytes, hexCase: hexCase)
        switch style {
        case .compact:
            return compact
        case .spaced:
            return grouped(compact, every: 2, separator: " ")
        case .colon:
            return grouped(compact, every: 2, separator: ":")
        case .dashed:
            return grouped(compact, every: 4, separator: "-")
        case .prefixed:
            return "0x" + compact
        case .cArray:
            return "{ " + byteTokens(compact, prefix: "0x").joined(separator: ", ") + " }"
        case .swiftArray:
            return "[" + byteTokens(compact, prefix: "0x").joined(separator: ", ") + "]"
        case .uuid:
            return uuidString(from: compact)
        case .base64:
            return Data(bytes).base64EncodedString()
        }
    }

    /// Groups of 4 hex digits (2 bytes) joined with dashes: A1B2-C3D4-…
    static func dashed(_ bytes: [UInt8], hexCase: HexCase) -> String {
        format(bytes, style: .dashed, hexCase: hexCase)
    }

    /// 8-4-4-4-12 grouping. Extra bytes continue as hyphenated 4-digit groups.
    static func uuidString(_ bytes: [UInt8], hexCase: HexCase) -> String {
        format(bytes, style: .uuid, hexCase: hexCase)
    }

    /// Mixed case is derived from the bytes so a given key always shows the same mix.
    static func mixedHex(_ bytes: [UInt8]) -> String {
        var rng = SplitMix64(seed: mixSeed(from: bytes))
        var out = ""
        out.reserveCapacity(bytes.count * 2)
        for b in bytes {
            for ch in String(format: "%02x", b) {
                if ch >= "a" && ch <= "f" {
                    out += rng.nextBit() ? String(ch).uppercased() : String(ch)
                } else {
                    out.append(ch)
                }
            }
        }
        return out
    }

    static func mixSeed(from bytes: [UInt8]) -> UInt64 {
        var h: UInt64 = 0xA0761D6478BD642F
        for b in bytes {
            h ^= UInt64(b)
            h &*= 0xE7037ED1A0B428DB
            h ^= h >> 32
        }
        return h == 0 ? 0x9E3779B97F4A7C15 : h
    }

    private static func grouped(_ compact: String, every n: Int, separator: String) -> String {
        guard !compact.isEmpty, n > 0 else { return compact }
        var parts: [String] = []
        var i = compact.startIndex
        while i < compact.endIndex {
            let end = compact.index(i, offsetBy: n, limitedBy: compact.endIndex) ?? compact.endIndex
            parts.append(String(compact[i..<end]))
            i = end
        }
        return parts.joined(separator: separator)
    }

    private static func byteTokens(_ compact: String, prefix: String) -> [String] {
        var tokens: [String] = []
        var i = compact.startIndex
        while i < compact.endIndex {
            let end = compact.index(i, offsetBy: 2, limitedBy: compact.endIndex) ?? compact.endIndex
            tokens.append(prefix + String(compact[i..<end]))
            i = end
        }
        return tokens
    }

    private static func uuidString(from compact: String) -> String {
        if compact.count == 32 {
            let s = compact
            let i8 = s.index(s.startIndex, offsetBy: 8)
            let i12 = s.index(s.startIndex, offsetBy: 12)
            let i16 = s.index(s.startIndex, offsetBy: 16)
            let i20 = s.index(s.startIndex, offsetBy: 20)
            return "\(s[s.startIndex..<i8])-\(s[i8..<i12])-\(s[i12..<i16])-\(s[i16..<i20])-\(s[i20..<s.endIndex])"
        }
        return grouped(compact, every: 4, separator: "-")
    }

    private struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func nextBit() -> Bool {
            next() & 1 == 1
        }
    }

    /// Accepts compact, spaced, colon, dashed, 0x-prefixed, C/Swift arrays.
    static func parseHex(_ string: String) -> [UInt8]? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("{") && s.hasSuffix("}") {
            s = String(s.dropFirst().dropLast())
        }
        if s.hasPrefix("[") && s.hasSuffix("]") {
            s = String(s.dropFirst().dropLast())
        }
        s = s.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "0X", with: "")
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let cleaned = s.unicodeScalars.filter { allowed.contains($0) }.map { Character($0) }
        let hexOnly = String(cleaned)
        guard hexOnly.count >= 2, hexOnly.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexOnly.count / 2)
        var i = hexOnly.startIndex
        while i < hexOnly.endIndex {
            let next = hexOnly.index(i, offsetBy: 2)
            let pair = hexOnly[i..<next]
            guard let value = UInt8(pair, radix: 16) else { return nil }
            bytes.append(value)
            i = next
        }
        return bytes
    }

    static func isUUIDV4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        let version = (bytes[6] & 0xF0) >> 4
        let variant = (bytes[8] & 0xC0) >> 6
        return version == 4 && variant == 2
    }

    static func asciiPreview(_ bytes: [UInt8]) -> String {
        String(bytes.map { b in
            (b >= 32 && b <= 126) ? Character(UnicodeScalar(b)) : "."
        })
    }

    static func binaryData(_ bytes: [UInt8]) -> Data {
        Data(bytes)
    }
}

struct GeneratedKey: Identifiable, Equatable {
    let id: UUID
    let bytes: [UInt8]
    let created: Date
    let kind: KeyKind

    var bitCount: Int { bytes.count * 8 }
    var nybbleCount: Int { bytes.count * 2 }

    func formatted(style: HexFormat, hexCase: HexCase) -> String {
        HexEngine.format(bytes, style: style, hexCase: hexCase)
    }
}

enum KeyKind: String, Equatable {
    case random
    case uuidV4

    var title: String {
        switch self {
        case .random: return "Random"
        case .uuidV4: return "UUID v4"
        }
    }
}

enum SizePreset: Hashable, Identifiable {
    case bits(Int)
    case custom
    case uuidV4

    var id: String {
        switch self {
        case .bits(let n): return "bits-\(n)"
        case .custom: return "custom"
        case .uuidV4: return "uuid"
        }
    }

    var title: String {
        switch self {
        case .bits(let n): return "\(n)"
        case .custom: return "Custom"
        case .uuidV4: return "UUID"
        }
    }

    var subtitle: String {
        switch self {
        case .bits(let n): return "\(n / 8) B"
        case .custom: return "bytes"
        case .uuidV4: return "v4"
        }
    }
}

/// Labels for common key lengths. They only set size; generation is still CSPRNG bytes.
enum NamedUse: String, CaseIterable, Identifiable {
    case aes128
    case aes192
    case aes256
    case chacha20

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aes128: return "AES-128"
        case .aes192: return "AES-192"
        case .aes256: return "AES-256"
        case .chacha20: return "ChaCha20"
        }
    }

    var bits: Int {
        switch self {
        case .aes128: return 128
        case .aes192: return 192
        case .aes256, .chacha20: return 256
        }
    }

    var help: String {
        switch self {
        case .aes128: return "128-bit length · AES-128. Same CSPRNG as any 128-bit key."
        case .aes192: return "192-bit length · AES-192. Same CSPRNG as any 192-bit key."
        case .aes256: return "256-bit length · AES-256. Same CSPRNG as any 256-bit key."
        case .chacha20: return "256-bit length · ChaCha20. Same CSPRNG as any 256-bit key."
        }
    }

    static func parse(_ raw: String) -> NamedUse? {
        switch raw.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "aes-128", "aes128": return .aes128
        case "aes-192", "aes192": return .aes192
        case "aes-256", "aes256": return .aes256
        case "chacha20", "chacha", "chacha20-poly1305", "xchacha20": return .chacha20
        default: return nil
        }
    }
}
