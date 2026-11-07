# Changelog

## 1.0.2 — 2026-11-07

- Password length starts at 16. The 12 preset is gone, and the slider cannot go below 16

## 1.0.1 — 2026-09-26

- Save binary: raw UTF-8 bytes of the selected password (`.bin`), with no trailing newline
- CLI: `--binary --out`

## 1.0.0 — 2026-09-15

- First release
- Cryptographically random passwords via `SecRandomCopyBytes`
- Uppercase, lowercase, numbers, and special-character toggles
- Length 4–128 with presets; standard / extended / custom specials
- Exclude lookalikes; guarantee one character from each enabled class
- Strength meter, colored password, in-session history
- Optional clipboard auto-clear after 30 or 60 seconds
- CLI (`--length`, `--pin`, `--count`, `--self-test`)
