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
    .package(url: "https://github.com/steipete/SweetCookieKit.git", from: "0.5.1"),
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

```swift
let stores = client.stores(in: [.safari, .chrome, .firefox])
for store in stores {
    print("\(store.browser.displayName): \(store.profile.name)")
}
```

Stores identify both the browser profile and the underlying cookie store. This lets an app show the available sources before it reads anything.

## Permissions and Keychain access

Safari cookie access may require Full Disk Access. Chromium imports may ask macOS Keychain for that browser's Safe Storage credential so encrypted cookie values can be read.

Background work can prohibit Keychain UI for one import:

```swift
let records = try BrowserCookieKeychainAccessGate.withUserInteractionDisallowed {
    try client.records(matching: query, in: store)
}
```

The [advanced usage guide](docs/advanced-usage.md) covers query matching, browser ordering, prompt preflighting, noninteractive imports, and Chromium local-storage helpers.

## API and examples

The package includes DocC documentation and a standalone example executable:

| Resource | Purpose |
| --- | --- |
| [Advanced usage](docs/advanced-usage.md) | Queries, permissions, local storage, and LevelDB helpers |
| [DocC catalog](Sources/SweetCookieKit/Documentation.docc/Documentation.md) | Public types and core concepts |
| [SweetCookieCLI](Examples/CookieCLI/README.md) | List stores and export cookies as JSON, lines, or HTTP headers |

## Development

```sh
swift build
swift test
swiftlint --strict
swift package --allow-writing-to-directory /tmp/SweetCookieKit-docc generate-documentation --target SweetCookieKit --disable-indexing --transform-for-static-hosting --output-path /tmp/SweetCookieKit-docc
```

## License

SweetCookieKit is available under the [MIT License](LICENSE).
