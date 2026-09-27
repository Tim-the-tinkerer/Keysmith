# Keysmith

A native macOS **password generator**. Draws cryptographically random characters from `SecRandomCopyBytes` and builds long, complex passwords from the classes you turn on.

## Features

- Length 4–128 (presets 12 / 16 / 24 / 32 / 48 / 64)
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
```

Defaults: length 24, all four character classes on, standard specials.

## Shortcuts

| Key | Action |
| --- | --- |
| ⌘R | Generate |
| ⌘⇧C | Copy password |
| ⌘S | Save text |
| ⌘⇧S | Save binary |
| ⌘K | Clear session |

## Notes

- Entropy comes from `SecRandomCopyBytes`. Selection is unbiased (rejection sampling).
- Changing options does not rewrite the current password until you generate again.
- History is discarded when you quit. Treat copied passwords as secrets.
- Text save writes every password in the batch, each followed by a newline. Binary save writes only the selected password, as raw UTF-8 bytes with no extra newline, so the file can be used as a key file.
- Clipboard auto-clear defaults to 30 seconds. Keysmith only clears the pasteboard if it still holds the password it copied.
- Marketing version and build number live in `VERSION`. `./build-app.sh` writes them into `Version.swift` and the assembled app's `Info.plist`.
