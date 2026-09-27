import Foundation

enum SelfTest {
    static func run() -> String? {
        if let err = rngLength() { return err }
        if let err = rngDistinct() { return err }
        if let err = bounds() { return err }
        if let err = emptyCharset() { return err }
        if let err = classInclusion() { return err }
        if let err = allClassesPresent() { return err }
        if let err = ambiguousExclusion() { return err }
        if let err = specialSets() { return err }
        if let err = customSpecials() { return err }
        if let err = entropy() { return err }
        if let err = classify() { return err }
        if let err = clipboardClear() { return err }
        if let err = versionStamp() { return err }
        if let err = lengthPresets() { return err }
        if let err = pinDigitsOnly() { return err }
        if let err = binaryExport() { return err }
        return nil
    }

    private static func rngLength() -> String? {
        do {
            let b = try PasswordEngine.randomBytes(count: 32)
            if b.count != 32 { return "randomBytes(32) returned \(b.count)" }
            let one = try PasswordEngine.randomBytes(count: 1)
            if one.count != 1 { return "randomBytes(1) returned \(one.count)" }
        } catch {
            return "randomBytes failed: \(error)"
        }
        return nil
    }

    private static func rngDistinct() -> String? {
        do {
            let a = try PasswordEngine.randomBytes(count: 32)
            let b = try PasswordEngine.randomBytes(count: 32)
            if a == b { return "two 256-bit draws were identical (astronomically unlikely — RNG broken?)" }
            var options = PasswordOptions()
            options.length = 24
            let p1 = try PasswordEngine.generate(options: options)
            let p2 = try PasswordEngine.generate(options: options)
            if p1 == p2 { return "two 24-char passwords were identical (RNG broken?)" }
            if p1.count != 24 { return "password length \(p1.count)" }
        } catch {
            return "distinct draw failed: \(error)"
        }
        return nil
    }

    private static func bounds() -> String? {
        var options = PasswordOptions()
        options.length = 3
        do {
            _ = try PasswordEngine.generate(options: options)
            return "length 3 should throw"
        } catch PasswordEngineError.invalidLength {
            // ok
        } catch {
            return "length 3 threw \(error)"
        }
        options.length = PasswordEngine.maxLength + 1
        do {
            _ = try PasswordEngine.generate(options: options)
            return "oversize should throw"
        } catch PasswordEngineError.invalidLength {
            // ok
        } catch {
            return "oversize threw \(error)"
        }
        options.length = PasswordEngine.maxLength
        do {
            let p = try PasswordEngine.generate(options: options)
            if p.count != PasswordEngine.maxLength { return "max length was \(p.count)" }
        } catch {
            return "max length failed: \(error)"
        }
        options.length = PasswordEngine.minLength
        do {
            let p = try PasswordEngine.generate(options: options)
            if p.count != PasswordEngine.minLength { return "min length was \(p.count)" }
        } catch {
            return "min length failed: \(error)"
        }
        return nil
    }

    private static func emptyCharset() -> String? {
        var options = PasswordOptions()
        options.uppercase = false
        options.lowercase = false
        options.digits = false
        options.specials = false
        do {
            _ = try PasswordEngine.generate(options: options)
            return "empty charset should throw"
        } catch PasswordEngineError.emptyCharset {
            // ok
        } catch {
            return "empty charset threw \(error)"
        }
        options.specials = true
        options.specialKind = .custom
        options.customSpecials = "abc123"
        do {
            _ = try PasswordEngine.generate(options: options)
            return "letter/digit custom specials should throw empty"
        } catch PasswordEngineError.emptyCharset {
            // ok
        } catch {
            return "invalid custom specials threw \(error)"
        }
        return nil
    }

    private static func classInclusion() -> String? {
        struct Case {
            var name: String
            var mutate: (inout PasswordOptions) -> Void
            var allowed: (Character) -> Bool
        }
        let cases: [Case] = [
            Case(name: "upper", mutate: { o in
                o.uppercase = true; o.lowercase = false; o.digits = false; o.specials = false
            }, allowed: { $0.isUppercase && $0.isLetter }),
            Case(name: "lower", mutate: { o in
                o.uppercase = false; o.lowercase = true; o.digits = false; o.specials = false
            }, allowed: { $0.isLowercase && $0.isLetter }),
            Case(name: "digits", mutate: { o in
                o.uppercase = false; o.lowercase = false; o.digits = true; o.specials = false
            }, allowed: { $0.isNumber }),
            Case(name: "specials", mutate: { o in
                o.uppercase = false; o.lowercase = false; o.digits = false; o.specials = true
                o.specialKind = .standard
            }, allowed: { "!@#$%^&*".contains($0) }),
        ]
        for item in cases {
            var options = PasswordOptions()
            options.length = 16
            item.mutate(&options)
            do {
                let p = try PasswordEngine.generate(options: options)
                if p.contains(where: { !item.allowed($0) }) {
                    return "\(item.name) leaked foreign chars: \(p)"
                }
            } catch {
                return "\(item.name) generate failed: \(error)"
            }
        }
        return nil
    }

    private static func allClassesPresent() -> String? {
        var options = PasswordOptions()
        options.length = 24
        options.uppercase = true
        options.lowercase = true
        options.digits = true
        options.specials = true
        do {
            for _ in 0..<40 {
                let p = try PasswordEngine.generate(options: options)
                let counts = PasswordEngine.counts(in: p)
                for cls in CharClass.allCases {
                    if (counts[cls] ?? 0) < 1 {
                        return "missing \(cls.title) in \(p)"
                    }
                }
            }
        } catch {
            return "class guarantee failed: \(error)"
        }
        return nil
    }

    private static func ambiguousExclusion() -> String? {
        var options = PasswordOptions()
        options.length = 48
        options.excludeAmbiguous = true
        do {
            for _ in 0..<20 {
                let p = try PasswordEngine.generate(options: options)
                if p.contains(where: { PasswordEngine.ambiguous.contains($0) }) {
                    return "lookalike leaked: \(p)"
                }
            }
        } catch {
            return "ambiguous exclusion failed: \(error)"
        }
        let upper = PasswordEngine.pool(for: .uppercase, options: options)
        if upper.contains("O") || upper.contains("I") {
            return "uppercase pool still has lookalikes"
        }
        let digits = PasswordEngine.pool(for: .digits, options: options)
        if digits.contains("0") || digits.contains("1") {
            return "digit pool still has lookalikes"
        }
        return nil
    }

    private static func specialSets() -> String? {
        var options = PasswordOptions()
        options.specialKind = .standard
        let std = PasswordEngine.specials(for: options)
        if String(std) != "!@#$%^&*" { return "standard specials were \(String(std))" }
        options.specialKind = .extended
        let ext = PasswordEngine.specials(for: options)
        if ext.count <= std.count { return "extended should be larger than standard" }
        if !Set(std).isSubset(of: Set(ext)) { return "standard is not a subset of extended" }
        return nil
    }

    private static func customSpecials() -> String? {
        let unique = PasswordEngine.uniqueSpecials("!!@@  abc123 _-_")
        if String(unique) != "!@_-" {
            return "unique specials were \(String(unique))"
        }
        if PasswordEngine.uniqueSpecials("hello").isEmpty == false {
            return "letters should not count as specials"
        }
        var options = PasswordOptions()
        options.uppercase = false
        options.lowercase = false
        options.digits = false
        options.specials = true
        options.specialKind = .custom
        options.customSpecials = "_-+="
        options.length = 12
        do {
            let p = try PasswordEngine.generate(options: options)
            if p.contains(where: { !"_-+=".contains($0) }) {
                return "custom specials leaked: \(p)"
            }
        } catch {
            return "custom specials generate failed: \(error)"
        }
        return nil
    }

    private static func entropy() -> String? {
        var options = PasswordOptions()
        options.length = 4
        options.uppercase = false
        options.lowercase = false
        options.digits = true
        options.specials = false
        let bits = PasswordEngine.entropyBits(options: options)
        let expected = 4.0 * log2(10.0)
        if abs(bits - expected) > 0.01 { return "PIN entropy \(bits) expected \(expected)" }
        if PasswordEngine.strength(options: options) != .tooWeak {
            return "4-digit PIN should be too weak"
        }
        options.length = 24
        options.uppercase = true
        options.lowercase = true
        options.digits = true
        options.specials = true
        options.specialKind = .standard
        let strongBits = PasswordEngine.entropyBits(options: options)
        if strongBits < 128 { return "24-char all-class entropy too low: \(strongBits)" }
        if PasswordEngine.strength(options: options) != .paranoid {
            return "24-char all-class should be paranoid, got \(PasswordEngine.strength(options: options).title)"
        }
        if Strength.from(bits: 50) != .fair { return "50 bits should be fair" }
        if Strength.from(bits: 70) != .strong { return "70 bits should be strong" }
        if Strength.from(bits: 100) != .excellent { return "100 bits should be excellent" }
        return nil
    }

    private static func classify() -> String? {
        if PasswordEngine.classify("A") != .uppercase { return "A not uppercase" }
        if PasswordEngine.classify("z") != .lowercase { return "z not lowercase" }
        if PasswordEngine.classify("7") != .digits { return "7 not digit" }
        if PasswordEngine.classify("!") != .specials { return "! not special" }
        let counts = PasswordEngine.counts(in: "Aa1!")
        if counts[.uppercase] != 1 { return "count upper" }
        if counts[.lowercase] != 1 { return "count lower" }
        if counts[.digits] != 1 { return "count digits" }
        if counts[.specials] != 1 { return "count specials" }
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

    private static func lengthPresets() -> String? {
        for n in PasswordEngine.lengthPresets {
            if n < PasswordEngine.minLength || n > PasswordEngine.maxLength {
                return "preset \(n) out of range"
            }
        }
        if PasswordEngine.clampedLength(0) != PasswordEngine.minLength {
            return "clamp low failed"
        }
        if PasswordEngine.clampedLength(999) != PasswordEngine.maxLength {
            return "clamp high failed"
        }
        return nil
    }

    private static func pinDigitsOnly() -> String? {
        var options = PasswordOptions()
        options.length = 6
        options.uppercase = false
        options.lowercase = false
        options.digits = true
        options.specials = false
        do {
            for _ in 0..<20 {
                let p = try PasswordEngine.generate(options: options)
                if p.count != 6 { return "PIN length \(p.count)" }
                if p.contains(where: { !$0.isNumber }) { return "PIN leaked non-digits: \(p)" }
            }
        } catch {
            return "PIN generate failed: \(error)"
        }
        return nil
    }

    private static func binaryExport() -> String? {
        let password = "Ab3!a★"
        let data = PasswordEngine.binaryData(password)
        if data != Data(password.utf8) { return "binary bytes mismatch" }
        if data.last == 0x0A { return "binary export added a newline" }
        let textFile = Data((password + "\n").utf8)
        if textFile == data { return "text save collided with binary key" }
        if data.count == password.count { return "expected multi-byte UTF-8 in binary key" }
        return nil
    }
}
