import Foundation

enum HexSelfTest {
    static func run() -> String? {
        if let err = rngLength() { return err }
        if let err = rngDistinct() { return err }
        if let err = hexCase() { return err }
        if let err = mixedCase() { return err }
        if let err = formats() { return err }
        if let err = parseRoundTrip() { return err }
        if let err = uuidV4() { return err }
        if let err = uuidFormat() { return err }
        if let err = bounds() { return err }
        if let err = asciiPreview() { return err }
        if let err = dashedGroups() { return err }
        if let err = clipboardClear() { return err }
        if let err = versionStamp() { return err }
        if let err = namedUses() { return err }
        if let err = binaryExport() { return err }
        return nil
    }

    private static func rngLength() -> String? {
        do {
            let b = try HexEngine.randomBytes(count: 32)
            if b.count != 32 { return "randomBytes(32) returned \(b.count)" }
            let one = try HexEngine.randomBytes(count: 1)
            if one.count != 1 { return "randomBytes(1) returned \(one.count)" }
        } catch {
            return "randomBytes failed: \(error)"
        }
        return nil
    }

    private static func rngDistinct() -> String? {
        do {
            let a = try HexEngine.randomBytes(count: 32)
            let b = try HexEngine.randomBytes(count: 32)
            if a == b { return "two 256-bit draws were identical (astronomically unlikely — RNG broken?)" }
        } catch {
            return "distinct draw failed: \(error)"
        }
        return nil
    }

    private static func hexCase() -> String? {
        let bytes: [UInt8] = [0x0A, 0xFF, 0x00, 0xB1]
        let upper = HexEngine.hex(bytes, hexCase: .upper)
        let lower = HexEngine.hex(bytes, hexCase: .lower)
        if upper != "0AFF00B1" { return "upper hex was \(upper)" }
        if lower != "0aff00b1" { return "lower hex was \(lower)" }
        return nil
    }

    private static func mixedCase() -> String? {
        let digitsOnly: [UInt8] = [0x00, 0x11, 0x22, 0x99]
        let mixedDigits = HexEngine.hex(digitsOnly, hexCase: .mixed)
        if mixedDigits != "00112299" { return "mixed digits-only was \(mixedDigits)" }

        let letters: [UInt8] = Array(repeating: 0xAB, count: 16)
        let a = HexEngine.hex(letters, hexCase: .mixed)
        let b = HexEngine.hex(letters, hexCase: .mixed)
        if a != b { return "mixed case is not stable: \(a) vs \(b)" }
        if a == HexEngine.hex(letters, hexCase: .upper) { return "mixed equaled uppercase" }
        if a == HexEngine.hex(letters, hexCase: .lower) { return "mixed equaled lowercase" }
        let hasUpper = a.contains { ("A"..."F").contains($0) }
        let hasLower = a.contains { ("a"..."f").contains($0) }
        if !hasUpper || !hasLower { return "mixed lacked both cases: \(a)" }
        if HexEngine.parseHex(a) != letters { return "mixed parse mismatch" }

        let colon = HexEngine.format(letters, style: .colon, hexCase: .mixed)
        let stripped = colon.replacingOccurrences(of: ":", with: "")
        if stripped != a { return "colon mixed did not match compact" }

        let swift = HexEngine.format([0xAB, 0xCD], style: .swiftArray, hexCase: .mixed)
        if !swift.hasPrefix("[0x") { return "swift mixed lost 0x prefix: \(swift)" }
        if HexEngine.parseHex(swift) != [0xAB, 0xCD] { return "swift mixed parse failed: \(swift)" }
        return nil
    }

    private static func formats() -> String? {
        let bytes: [UInt8] = [0xA1, 0xB2, 0xC3, 0xD4]
        let cases: [(HexFormat, String)] = [
            (.compact, "A1B2C3D4"),
            (.spaced, "A1 B2 C3 D4"),
            (.colon, "A1:B2:C3:D4"),
            (.dashed, "A1B2-C3D4"),
            (.prefixed, "0xA1B2C3D4"),
            (.cArray, "{ 0xA1, 0xB2, 0xC3, 0xD4 }"),
            (.swiftArray, "[0xA1, 0xB2, 0xC3, 0xD4]"),
        ]
        for (style, expected) in cases {
            let got = HexEngine.format(bytes, style: style, hexCase: .upper)
            if got != expected { return "\(style.title) was \(got), expected \(expected)" }
        }
        let b64 = HexEngine.format(bytes, style: .base64, hexCase: .upper)
        if Data(bytes).base64EncodedString() != b64 {
            return "Base64 mismatch: \(b64)"
        }
        let lowerC = HexEngine.format(bytes, style: .cArray, hexCase: .lower)
        if lowerC != "{ 0xa1, 0xb2, 0xc3, 0xd4 }" {
            return "lowercase C array was \(lowerC)"
        }
        return nil
    }

    private static func parseRoundTrip() -> String? {
        let originals: [[UInt8]] = [
            [0x00],
            [0xDE, 0xAD, 0xBE, 0xEF],
            Array(0...255),
        ]
        for bytes in originals {
            for style in HexFormat.allCases where style != .base64 {
                let text = HexEngine.format(bytes, style: style, hexCase: .upper)
                guard let parsed = HexEngine.parseHex(text) else {
                    return "parseHex failed for \(style.title): \(text.prefix(80))"
                }
                if parsed != bytes {
                    return "round-trip mismatch for \(style.title)"
                }
                let lower = HexEngine.format(bytes, style: style, hexCase: .lower)
                guard let parsedLower = HexEngine.parseHex(lower), parsedLower == bytes else {
                    return "lowercase round-trip failed for \(style.title)"
                }
                let mixed = HexEngine.format(bytes, style: style, hexCase: .mixed)
                guard let parsedMixed = HexEngine.parseHex(mixed), parsedMixed == bytes else {
                    return "mixed round-trip failed for \(style.title)"
                }
            }
        }
        if HexEngine.parseHex("") != nil { return "empty string should not parse" }
        if HexEngine.parseHex("GG") != nil { return "non-hex should not parse" }
        if HexEngine.parseHex("ABC") != nil { return "odd-length hex should not parse" }
        return nil
    }

    private static func uuidV4() -> String? {
        do {
            for _ in 0..<8 {
                let bytes = try HexEngine.uuidV4Bytes()
                if bytes.count != 16 { return "UUID was \(bytes.count) bytes" }
                if !HexEngine.isUUIDV4(bytes) {
                    return "UUID v4 bits not set: \(HexEngine.hex(bytes, hexCase: .upper))"
                }
            }
            var notV4 = try HexEngine.randomBytes(count: 16)
            notV4[6] = (notV4[6] & 0x0F) | 0x10
            if HexEngine.isUUIDV4(notV4) { return "version-1 UUID flagged as v4" }
        } catch {
            return "uuidV4 failed: \(error)"
        }
        return nil
    }

    private static func uuidFormat() -> String? {
        let bytes: [UInt8] = [
            0x12, 0x34, 0x56, 0x78,
            0x9A, 0xBC,
            0x4D, 0xEF,
            0x80, 0x11,
            0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        ]
        let s = HexEngine.format(bytes, style: .uuid, hexCase: .upper)
        if s != "12345678-9ABC-4DEF-8011-223344556677" {
            return "UUID format was \(s)"
        }
        let odd = HexEngine.format([0xAA, 0xBB, 0xCC], style: .uuid, hexCase: .upper)
        if odd != "AABB-CC" { return "short UUID-style was \(odd)" }
        return nil
    }

    private static func bounds() -> String? {
        do {
            _ = try HexEngine.randomBytes(count: 0)
            return "count 0 should throw"
        } catch HexEngineError.invalidLength {
            // ok
        } catch {
            return "count 0 threw \(error)"
        }
        do {
            _ = try HexEngine.randomBytes(count: HexEngine.maxBytes + 1)
            return "oversize should throw"
        } catch HexEngineError.invalidLength {
            // ok
        } catch {
            return "oversize threw \(error)"
        }
        do {
            let big = try HexEngine.randomBytes(count: HexEngine.maxBytes)
            if big.count != HexEngine.maxBytes { return "maxBytes length \(big.count)" }
        } catch {
            return "maxBytes failed: \(error)"
        }
        return nil
    }

    private static func asciiPreview() -> String? {
        let bytes: [UInt8] = [0x48, 0x69, 0x21, 0x00, 0x7F, 0x41]
        let preview = HexEngine.asciiPreview(bytes)
        if preview != "Hi!..A" { return "ascii preview was \(preview)" }
        return nil
    }

    private static func dashedGroups() -> String? {
        let five: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05]
        let dashed = HexEngine.dashed(five, hexCase: .upper)
        if dashed != "0102-0304-05" { return "dashed leftover was \(dashed)" }
        return nil
    }

    private static func clipboardClear() -> String? {
        if ClipboardClearDelay.off.seconds != 0 { return "off delay should be 0" }
        if ClipboardClearDelay.thirty.seconds != 30 { return "30s delay was \(ClipboardClearDelay.thirty.seconds)" }
        if ClipboardClearDelay.sixty.seconds != 60 { return "60s delay was \(ClipboardClearDelay.sixty.seconds)" }
        if ClipboardClearDelay.parse(seconds: 30) != .thirty { return "parse 30 failed" }
        if ClipboardClearDelay.parse(seconds: 99) != .off { return "unknown delay should be off" }
        if !ClipboardClear.shouldClear(copiedChangeCount: 4, currentChangeCount: 4) {
            return "should clear when changeCount is unchanged"
        }
        if ClipboardClear.shouldClear(copiedChangeCount: 4, currentChangeCount: 5) {
            return "should not clear when something else was copied"
        }
        return nil
    }

    private static func versionStamp() -> String? {
        let parts = AppVersion.short.split(separator: ".")
        if parts.count != 3 || parts.contains(where: { Int($0) == nil }) {
            return "AppVersion.short was \(AppVersion.short)"
        }
        if Int(AppVersion.build) == nil {
            return "AppVersion.build was \(AppVersion.build)"
        }
        return nil
    }

    private static func namedUses() -> String? {
        if NamedUse.aes128.bits != 128 { return "AES-128 should be 128-bit" }
        if NamedUse.aes192.bits != 192 { return "AES-192 should be 192-bit" }
        if NamedUse.aes256.bits != 256 { return "AES-256 should be 256-bit" }
        if NamedUse.chacha20.bits != 256 { return "ChaCha20 should be 256-bit" }
        if NamedUse.aes256.bits != NamedUse.chacha20.bits {
            return "AES-256 and ChaCha20 must share a length"
        }
        if NamedUse.parse("aes-256") != .aes256 { return "parse aes-256 failed" }
        if NamedUse.parse("AES-128") != .aes128 { return "parse AES-128 failed" }
        if NamedUse.parse("chacha20") != .chacha20 { return "parse chacha20 failed" }
        if NamedUse.parse("xchacha20") != .chacha20 { return "parse xchacha20 failed" }
        if NamedUse.parse("des") != nil { return "des should not parse as a named use" }
        return nil
    }

    private static func binaryExport() -> String? {
        let bytes: [UInt8] = [0x00, 0x7F, 0x80, 0xFF]
        let data = HexEngine.binaryData(bytes)
        if data.count != bytes.count { return "binary length \(data.count)" }
        if Array(data) != bytes { return "binary round-trip mismatch" }
        let hex = HexEngine.hex(bytes, hexCase: .upper)
        if Data(hex.utf8) == data { return "hex UTF-8 collided with raw bytes" }
        return nil
    }
}
