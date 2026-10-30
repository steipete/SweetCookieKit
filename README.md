# SweetCookieKit 🧁 — Browser cookies, served native.

[![CI](https://img.shields.io/github/actions/workflow/status/steipete/SweetCookieKit/ci.yml?branch=main&style=flat-square&label=ci)](https://github.com/steipete/SweetCookieKit/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/steipete/SweetCookieKit?style=flat-square)](https://github.com/steipete/SweetCookieKit/releases/latest)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138?style=flat-square)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-000000?style=flat-square)](https://www.apple.com/macos/)
[![License](https://img.shields.io/github/license/steipete/SweetCookieKit?style=flat-square)](LICENSE)

SweetCookieKit is a Swift package that discovers profiles and reads cookies from Safari, Chromium-based browsers, Firefox, and Zen on macOS. It returns normalized records or `HTTPCookie` values for apps and command-line tools.

## Install

SweetCookieKit requires macOS 13 or newer and Swift 6.2 or newer. Add it to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/steipete/SweetCookieKit.git", from: "0.5.11"),
],
targets: [
    .target(name: "YourTarget", dependencies: ["SweetCookieKit"]),
]
```

## Quick start

Choose a browser, discover its profiles, and read cookies matching a domain:

```swift
import SweetCookieKit

let client = BrowserCookieClient()
let query = BrowserCookieQuery(domains: ["example.com"], domainMatch: .suffix)
guard let store = client.stores(for: .chrome).first else {
    fatalError("Chrome cookie store not found")
}
let cookies = try client.cookies(matching: query, in: store)
print("Loaded \(cookies.count) cookies from \(store.profile.name)")
```

`BrowserCookieClient` can return normalized `BrowserCookieRecord` values instead when the caller does not need `HTTPCookie` conversion. Each record retains its original `scope`, so callers can distinguish a domain cookie such as Chromium's `.example.com` from a host-only `example.com` cookie after the leading dot is normalized away. SweetCookieKit only reads browser data; it does not persist cookies.

## Browsers and profiles

`Browser.defaultImportOrder` covers every supported Safari, Chromium, and Gecko browser. Pass a narrower list when the user has already chosen a source:

Chromium sources include Aside (`Aside`), Opera (`com.operasoftware.Opera`), and Opera Neon (`com.operasoftware.OperaNeon`) under `~/Library/Application Support`. Aside uses the `Aside Safe Storage` / `Aside` Keychain label; both Opera variants use `Opera Safe Storage` / `Opera`. Brave Origin (`BraveSoftware/Brave-Origin`) is a separate store from Brave but reuses Brave's `Brave Safe Storage` / `Brave` Keychain label. Discovery reuses the standard `Default` and `Profile N` layout. Hosts can retain Chrome-only policies by passing `[.chrome]`.

Ego Lite (`.egoLite`, app bundle `ego lite.app`) uses `~/Library/Application Support/Citro Labs/ego lite` and the `ego safe storage` / `ego` Keychain label. Its profiles use the shared Chromium discovery and cookie decryption path.

The Claude desktop app (`.claudeDesktop`, `Claude.app`) is an explicit opt-in source, excluded from `Browser.defaultImportOrder`. Its single Electron store lives at `~/Library/Application Support/Claude/Cookies` (or `Network/Cookies`) and uses the `Claude Safe Storage` / `Claude Key` Keychain label. Pass `[.claudeDesktop]` to discover it; host filtering and noninteractive Keychain policies apply as for browser stores.

```swift
let stores = client.stores(in: [.safari, .chrome, .firefox])
for store in stores {
    print("\(store.browser.displayName): \(store.profile.name)")
}
```

Stores identify both the browser profile and the underlying cookie store. This lets an app show the available sources before it reads anything.

## Permissions and Keychain access

Safari cookie access may require Full Disk Access. Chromium imports filter cookie hosts before requesting that browser's Safe Storage credential from macOS Keychain. Stores with no matching cookies and cookies with plaintext values need no Keychain access; matching encrypted values may require a prompt.

Background work can prohibit Keychain UI for one import:

```swift
let records = try BrowserCookieKeychainAccessGate.withUserInteractionDisallowed {
    try client.records(matching: query, in: store)
}
```

The [advanced usage guide](docs/advanced-usage.md) covers query matching, browser ordering, prompt preflighting, noninteractive imports, and Chromium local-storage helpers.

For origin-scoped Local Storage, call `ChromiumLocalStorageReader.readEntries(for:in:)`. It streams LevelDB files and decodes only matching values, without retaining a whole-store cache. `readCurrentValue(forRawKey:in:)` uses the same filtered traversal for strict, byte-exact credential reads.

## API and examples

The package includes DocC documentation and a standalone example executable:

| Resource | Purpose |
| --- | --- |
| [Advanced usage](docs/advanced-usage.md) | Queries, permissions, local storage, and LevelDB helpers |
| [DocC catalog](Sources/SweetCookieKit/Documentation.docc/Documentation.md) | Public types and core concepts |
| [SweetCookieCLI](Examples/CookieCLI/README.md) | List stores and export cookies as JSON, lines, or HTTP headers |

## Development

CI and release verification use the default Xcode 27 toolchain on GitHub's Apple silicon `xcode-27` runner, retaining the macOS 13 deployment target and Swift 6.2 package minimum.

```sh
swift build
swift test
swiftlint --strict
swift package --allow-writing-to-directory /tmp/SweetCookieKit-docc generate-documentation --target SweetCookieKit --disable-indexing --transform-for-static-hosting --output-path /tmp/SweetCookieKit-docc
```

## License

SweetCookieKit is available under the [MIT License](LICENSE).
