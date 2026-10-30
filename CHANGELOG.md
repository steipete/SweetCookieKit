# Changelog

## 0.5.11 — 2026-10-30

**Highlights:** Brave Origin is supported as a Chromium cookie source.

- Add Brave Origin as a Chromium cookie source, reading `BraveSoftware/Brave-Origin` with Brave's Safe Storage Keychain item (#47). Thanks @retX0!

## 0.5.10 — 2026-10-23

**Highlights:** Chromium local-storage reads keep HTTP and HTTPS origins distinct, and cookie domain filters now match consistently in SQL and in memory.

- Compare schemes when a Chromium local-storage key and the requested origin both have one, so http and https on the same host stay distinct. Matching schemes still compare hosts, so an uppercase scheme matches that origin. A schemeless key still matches that host. (#43, thanks @SebTardif)
- Normalize cookie domain contains and suffix filters before the SQLite LIKE, and escape percent and underscore, so the query matches the in-memory matcher. (#44, thanks @SebTardif)

## 0.5.9 — 2026-10-20

**Highlights:** Origin-filtered Chromium Local Storage reads now stream record by record, so reading one site's values from a large store uses a few MiB instead of hundreds; Firefox and other Gecko session cookies are imported again, and idle WAL-mode Chromium and Gecko databases without sidecars read correctly.

- Stream origin-scoped Chromium Local Storage and strict exact-key reads without retaining unrelated values or populating the whole-store cache. (steipete/CodexBar#4649)
- Fix missing Firefox and other Gecko session cookies by merging ordinary saved-session cookies with SQLite records while excluding unsupported container and partition identities. (#36, thanks @sqmagellan)
- Match exact cookie domains case-insensitively in Chromium and Gecko SQLite queries, consistent with other query modes.
- Move CI and release verification to the `xcode-27` runner's default toolchain while retaining macOS 13 support.
- Fix Chromium cookie imports from idle WAL-mode databases without sidecars, preserving active WAL values without modifying source files. (#33, thanks @pranshug2704)
- Fix Firefox and other Gecko cookie imports failing when an idle WAL-mode profile has no sidecars, while preserving active WAL cookies and leaving browser files unchanged. (#33, #34, thanks @pranshug2704)

## 0.5.8 — 2026-10-15

**Highlights:** The Claude desktop app is available as an opt-in Chromium cookie source, kept out of the default browser import order.

- Add the opt-in Claude desktop app cookie source, using its Electron cookie store and Claude Safe Storage labels (steipete/CodexBar#4494). Thanks @flutterrausch!

## 0.5.7 — 2026-10-12

**Highlights:** Chromium cookie imports check a cookie store for the requested hosts before asking for the browser's Safe Storage key, so browsers without matching cookies never trigger a Keychain prompt.

- Skip the Chromium Safe Storage key request when a browser's cookie store has no cookies for the requested domains, avoiding unnecessary Keychain prompts. (#27, steipete/CodexBar#4443)

## 0.5.6 — 2026-10-11

**Highlights:** Chromium local-storage reads return the current record by LevelDB sequence and live manifest, and a new strict exact-key API with descriptor-anchored reads serves credential discovery.

- Add strict exact-key Chromium local-storage reads with manifest, checksum, and file-change validation and descriptor-anchored symlink protection for credential discovery. (#25, thanks @OttoPrua)
- Fix Chromium local-storage current-record selection using LevelDB sequences and live manifest files, preserving sign-in values after older deletions and excluding stale tokens from text and token scans. (steipete/CodexBar#3536)
- Add Ego Lite browser discovery and encrypted-cookie imports through the shared Chromium reader. (#23, thanks @apple-ouyang)

## 0.5.5 — 2026-10-03

**Highlights:** Aside, Opera, and Opera Neon are discovered as Chromium cookie sources.

- Add Aside, Opera, and Opera Neon to Chromium cookie discovery with their profile roots and Safe Storage labels (steipete/CodexBar#4215, steipete/CodexBar#2429).

## 0.5.4 — 2026-10-01

**Highlights:** Repeated Chromium local-storage reads are served from an in-memory memo until the LevelDB files change.

- Memoize complete Chromium local-storage reads and derived text, token, and origin results in memory with file-change invalidation, bounded retention, and an explicit cache invalidation API.

## 0.5.3 — 2026-09-13

**Highlights:** Safari, Firefox, and Zen imports now preserve domain-cookie scope.

- Preserve domain-cookie scope when importing Safari, Firefox, and Zen cookies instead of reporting every cookie as host-only.

## 0.5.2 — 2026-08-03

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
