# Changelog

## 0.1.0

Initial release of SweetCookieKit.

- Modern Swift API with `BrowserCookieClient`, `BrowserCookieQuery`, and typed models for browsers, profiles, and stores.
- Profile-aware store discovery for Safari, Chromium-based browsers, and Firefox.
- Domain matching options (contains/suffix/exact) plus optional expired-cookie filtering.
- Cookie conversion helpers that return `HTTPCookie` values ready for WebKit or URL requests.
- Chromium decryption support via Keychain “Chrome Safe Storage” (best-effort).
- Full docc coverage and README examples.
- Swift Testing coverage for the public API and Chromium decryption.
