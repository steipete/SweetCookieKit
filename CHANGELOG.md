# Changelog

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
