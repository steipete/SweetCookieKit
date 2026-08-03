# Changelog

## 0.5.2 - Unreleased

- Preserve host-only versus domain scope on normalized browser cookie records.

## 0.5.1 — 2026-08-01

- Chromium: validate and strip schema-v24 domain hashes while preserving long and Unicode legacy cookie values. (#17, thanks @Yuxin-Qiao)
- Chromium: prevent duplicate legacy Keychain prompts while preserving no-UI Safe Storage fallback. (#16, thanks @lgrygo-codi)

## 0.5.0 — 2026-07-18

### Highlights

- Give each Chromium import explicit control over whether macOS Keychain may show user interaction, while preserving interactive recovery by default. (#15, thanks @Yuxin-Qiao)
- Discover Firefox Beta, Developer Edition, and Nightly profiles as distinct stores without cross-channel duplicates. (#13, thanks @BasixKOR)
- Reject malformed Safari cookie and Chromium LevelDB/Snappy data without unchecked reads or unbounded allocations. (#11)

### Keychain access

- Add `BrowserCookieKeychainAccessGate.withUserInteractionDisallowed` for background imports that must not display Keychain UI.
- Try every available Chromium Safe Storage label without interaction before returning `BrowserCookieError.accessDenied`.

### Browser support

- Add typed browser cases, profile discovery, display metadata, and tests for Firefox Beta, Developer Edition, and Nightly.

### Security and reliability

- Bound Safari binary-cookie parsing and reject malformed page, record, and offset structures before reading them.
- Harden Chromium LevelDB and Snappy decoding against truncated input, invalid lengths, and oversized allocations.

### Maintenance

- Update SwiftPM metadata for Swift 6.2 and keep the Swift-DocC plugin on the latest 1.5.0 release.

## 0.4.1 — 2026-05-10
- Safari: discover profile-specific `WebsiteDataStore` cookie files and load cookies from the selected Safari store. (thanks @przemyslaw-szurmak)
- Chromium: add Comet browser support. (thanks @Hilo-Hilo)
- Chromium: add Yandex Browser support and use per-browser Safe Storage keys. (thanks @serezha93)
- Helium: use the `Helium Storage Key` Keychain label and avoid reusing another browser's cached Safe Storage key. (thanks @bald-ai)
- Tests: cover Safari fallback, profile store discovery, and selected-store cookie reads.

## 0.4.0 — 2026-01-20
- Export browser metadata helpers for host app detection (bundle names, profile roots, Safe Storage labels).
- Tests: cover browser metadata helper accessors and bundle name overrides.

## 0.3.0 — 2026-01-20
- Firefox: add Zen browser support. (#3, thanks @vnixx)
- Chromium: add Dia browser support. (#2, thanks @archodev)
- Refactor: centralize browser metadata and Gecko importer wiring.

## 0.2.1 — 2026-01-18
- Chromium: honor host app keychain access disable flag to suppress Safe Storage prompts.

## 0.2.0 — 2026-01-01
- Chromium: add Helium support (profiles + keychain labels).
- Chromium: centralize profile root discovery (new `ChromiumProfileLocator`).

## 0.1.4 — 2025-12-31
- Chromium LevelDB: add helper API for raw text entry and token scanning.
- Tests: expand Snappy + LevelDB table coverage (compressed + raw).

## 0.1.3 — 2025-12-31
- Local storage: add a Chromium LevelDB reader with Snappy support for localStorage entries.
- Tests: use Swift Testing for local storage reader coverage.

## 0.1.2 — 2025-12-30
- Keychain: add a preflight hook to explain Chromium Safe Storage prompts before the macOS dialog.

## 0.1.1

- Expand the default browser search order to try all supported browsers by default.

## 0.1.0

Initial release of SweetCookieKit.

- Native macOS cookie extraction for Safari, Chromium-based browsers, and Firefox.
- Supported browsers: Safari; Chromium family (Chrome, Chrome Beta/Canary, Chromium, Arc + beta/canary, Brave + beta/nightly, Edge + beta/canary, Vivaldi, ChatGPT Atlas); Firefox.
- Profile-aware store discovery with typed models (`Browser`, `BrowserProfile`, `BrowserCookieStore`, `BrowserCookieStoreKind`).
- High-level client (`BrowserCookieClient`) for listing stores and loading records or `HTTPCookie` values.
- Query model with domain filters, match strategies (contains/suffix/exact), optional expired-cookie inclusion, and reference date control.
- Origin strategies for cookie conversion: domain-based, fixed URL, or custom resolver.
- Convenience defaults: `Browser.defaultImportOrder`, `BrowserCookieDefaults.importOrder`, and readable labels for browser collections.
- Multi-browser helpers to load records/cookies across multiple browsers in one call.
- Chromium decryption via Keychain “Chrome Safe Storage” (best-effort).
- Configuration hooks for custom home directories (for sandboxing/testing).
- Read-only, no persistence; returns normalized records or `HTTPCookie` values.
- Documentation: docc + README examples + CLI example project (`Examples/CookieCLI`).
- Tests: Swift Testing coverage for public API and Chromium decryption helpers.
