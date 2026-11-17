# Keysmith

A native macOS generator for **passwords** and **hex keys**. Both draw from `SecRandomCopyBytes`. Password is the old Keysmith workspace. Hex is the old Nybble workspace. They share one window, one clipboard timer, and one menu bar.

Switch with the control at the top of the sidebar, or with ⌘1 and ⌘2. Each workspace keeps its own session in memory.

## Password

- Length 16–128 (presets 16 / 24 / 32 / 48 / 64)
- Independent toggles: uppercase, lowercase, numbers, special characters
- Special sets: standard (`!@#$%^&*`), extended, or a custom set
- Optional lookalike exclusion (`0 O o I l 1 |`)
- At least one character from each enabled class when length allows
- Live entropy estimate and strength meter
- Batch generate (up to 50)
- Session history kept in memory only — nothing is written until you copy or save
- Save as text, or as a binary key file (raw UTF-8 bytes of the selected password, no trailing newline)
- Optional clipboard auto-clear after 30 or 60 seconds
- CLI for headless generate and a self-test

## Hex

- Size presets: 64, 128, 192, 256, 384, 512 bits
- Named uses for common lengths: AES-128, AES-192, AES-256, ChaCha20 (labels only)
- Custom length, 1–1024 bytes
- UUID v4 (RFC 4122 version and variant bits)
- Formats: compact, spaced, colon, dashed, `0x` prefix, C array, Swift array, UUID, Base64
- Uppercase, lowercase, or mixed hex digits
- Batch generate (up to 50 keys)
- Hex dump with an ASCII column and a color fingerprint of the bytes
- Export as hex text or raw binary bytes

## Requirements

- macOS 13+
- Xcode / Swift toolchain

## Build & run

```bash
cd ~/Apps-Usefull/Keysmith
./build-app.sh
```

Without launching:

```bash
./build-app.sh --no-launch
open Keysmith.app
```

## CLI

```bash
Keysmith --version
Keysmith --self-test
Keysmith --length 32
Keysmith --length 32 --binary --out secret.key
Keysmith --length 16 --no-special
Keysmith --pin 6
Keysmith --exclude-ambiguous --count 5
Keysmith --specials extended
Keysmith --specials custom --custom-specials '_-+='
Keysmith --bits 256
Keysmith --use aes-256 --binary --out aes.key
Keysmith --bytes 32 --format colon --count 3
Keysmith --uuid --lower
Keysmith --bits 256 --mixed
Keysmith --bits 128 --format swift --out aes.hex
```

Password defaults: length 24, all four character classes on, standard specials.

Hex defaults: 256 bits, compact uppercase. A hex flag (`--bits`, `--bytes`, `--uuid`, `--format`, `--case`, `--lower`, `--mixed`, `--use`) selects hex output. Password flags and hex flags cannot be combined. `--count` alone still prints passwords.

## Shortcuts

| Key | Action |
| --- | --- |
| ⌘1 | Password workspace |
| ⌘2 | Hex workspace |
| ⌘R | Generate |
| ⌘⇧C | Copy password or key |
| ⌘S | Save text or hex |
| ⌘⇧S | Save binary |
| ⌘K | Clear the current session |

## Notes

- Entropy comes from `SecRandomCopyBytes`. Selection is unbiased (rejection sampling).
- Changing options does not rewrite the current password until you generate again.
- History is discarded when you quit. Treat copied passwords as secrets.
- Text save writes every password in the batch, each followed by a newline. Binary save writes only the selected password, as raw UTF-8 bytes with no extra newline, so the file can be used as a key file.
- Changing format or case reformats the same hex bytes. It does not draw new entropy.
- Named uses only set the bit length. AES-256 and ChaCha20 both draw 256 CSPRNG bits.
- Mixed case is derived from the key, so copy, dump, and format changes keep the same mix.
- Clipboard auto-clear defaults to 30 seconds and applies to whichever workspace copied last. Keysmith only clears the pasteboard if it still holds that secret.
- Marketing version and build number live in `VERSION`. `./build-app.sh` writes them into `Version.swift` and the assembled app's `Info.plist`.
