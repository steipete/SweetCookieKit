# Changelog

## 0.2.2 — 2026-01-20
- Firefox: add Zen browser support. (#3, thanks @vnixx)

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
