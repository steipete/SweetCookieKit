# 🧁 SweetCookieKit — Native macOS cookie extraction for Safari, Chromium, and Firefox.

SweetCookieKit is a Swift 6 package for extracting browser cookies on macOS.
It supports Safari, Chromium-based browsers, and Firefox, and provides a modern API
for selecting browsers and profiles, filtering by domain, and converting results to
`HTTPCookie` values.

## Requirements

- macOS 13+
- Swift 6

## Install

### Swift Package Manager

```swift
.package(url: "https://github.com/steipete/SweetCookieKit.git", from: "0.2.1")
```

## Usage

### List stores (profiles)

```swift
import SweetCookieKit

let client = BrowserCookieClient()
let stores = client.stores(for: .chrome)
```

### Fetch records from a specific store

```swift
import SweetCookieKit

let client = BrowserCookieClient()
let stores = client.stores(for: .chrome)
let store = stores.first { $0.profile.name == "Default" }

let query = BrowserCookieQuery(domains: ["example.com"])
let records = try client.records(matching: query, in: store!)
```

### Convert to `HTTPCookie`

```swift
let cookies = try client.cookies(matching: query, in: store!)
```

### Read Chromium local storage

```swift
import SweetCookieKit

let entries = ChromiumLocalStorageReader.readEntries(
    for: "https://example.com",
    in: levelDBURL)
```

### Query options

```swift
let query = BrowserCookieQuery(
    domains: ["example.com"],
    domainMatch: .suffix,
    includeExpired: false)
```

### Pick a browser order

```swift
let order = Browser.defaultImportOrder // tries all supported browsers by default
for browser in order {
    let results = try client.records(matching: query, in: browser)
    // results are grouped per profile/store
}
```

## Example CLI

See `Examples/CookieCLI` for a standalone SwiftPM executable that lists stores and exports cookies as JSON or HTTP headers.

```bash
cd Examples/CookieCLI
swift run SweetCookieCLI --help
```

## Chromium LevelDB helpers

When you need raw text entries or token candidates from Chromium LevelDB stores,
use the LevelDB reader helpers (best-effort decoding).

```swift
import SweetCookieKit

let entries = ChromiumLevelDBReader.readTextEntries(in: levelDBURL)
let tokens = ChromiumLevelDBReader.readTokenCandidates(in: levelDBURL, minimumLength: 80)
```

## Notes

- Safari cookie access may require Full Disk Access.
- Chromium imports can trigger a Keychain prompt for "Chrome Safe Storage".
- To explain keychain prompts before they appear, set a preflight handler:

```swift
import SweetCookieKit

BrowserCookieKeychainPromptHandler.shared.handler = { context in
    // Show a blocking alert or custom UI before the system prompt appears.
    // context.kind = .chromiumSafeStorage
}
```

- This package does not persist cookies. It only reads and returns them.

## Development

```bash
swiftformat Sources Tests
swiftlint --strict
```

## License

See `LICENSE`.
