# SweetCookieKit

SweetCookieKit extracts browser cookies on macOS and returns them as normalized records or
`HTTPCookie` values. It supports Safari, Chromium-based browsers, and Firefox.

Use it when you need to:

- Select a specific browser or profile.
- Filter by domain (contains/suffix/exact).
- Convert results into `HTTPCookie` values for WebKit or `URLRequest`.

## Requirements

- macOS 13+
- Swift 6

## Quick start

```swift
import SweetCookieKit

let client = BrowserCookieClient()
let query = BrowserCookieQuery(
    domains: ["chatgpt.com", "openai.com"],
    domainMatch: .suffix,
    includeExpired: false)

let stores = client.stores(for: .chrome)
let records = try client.records(matching: query, in: stores.first!)
let cookies = try client.cookies(matching: query, in: stores.first!)
```

## Topics

### Browser selection

- ``Browser``
- ``BrowserCookieImportOrder``
- ``BrowserProfile``
- ``BrowserCookieStore``
- ``BrowserCookieStoreKind``

### Querying

- ``BrowserCookieClient``
- ``BrowserCookieQuery``
- ``BrowserCookieDomainMatch``
- ``BrowserCookieRecord``
- ``BrowserCookieStoreRecords``
- ``BrowserCookieOriginStrategy``
