# SweetCookieKit

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
.package(path: "../SweetCookieKit")
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

### Query options

```swift
let query = BrowserCookieQuery(
    domains: ["example.com"],
    domainMatch: .suffix,
    includeExpired: false)
```

### Pick a browser order

```swift
let order = BrowserCookieImportOrder.safariChromeFirefox
for browser in order.browsers {
    let results = try client.records(matching: query, in: browser)
    // results are grouped per profile/store
}
```

## Notes

- Safari cookie access may require Full Disk Access.
- Chromium imports can trigger a Keychain prompt for "Chrome Safe Storage".
- This package does not persist cookies. It only reads and returns them.

## Development

```bash
swiftformat Sources Tests
swiftlint --strict
```

## License

See `LICENSE`.
