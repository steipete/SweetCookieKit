# SweetCookieKit

SweetCookieKit extracts browser cookies on macOS and returns them as normalized records or
`HTTPCookie` values. It supports Safari, Chromium-based browsers, Firefox
Release/Beta/Developer Edition/Nightly, and Zen.

Use it when you need to:

- Select a specific browser or profile.
- Filter by domain (contains/suffix/exact).
- Convert results into `HTTPCookie` values for WebKit or `URLRequest`.

## Permissions & prompts

- Safari cookie access may require Full Disk Access.
- Chromium imports can trigger a Keychain prompt for “Chrome Safe Storage”.

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

## Errors

Most failures surface as ``BrowserCookieError``. For example, missing cookie stores report `.notFound`,
and permission issues report `.accessDenied` with a user-facing hint in ``BrowserCookieError/accessDeniedHint``.

## Topics

### Browser selection

- ``Browser``
- ``BrowserCookieDefaults``
- ``BrowserProfile``
- ``BrowserCookieStore``
- ``BrowserCookieStoreKind``

### Querying

- ``BrowserCookieClient``
- ``BrowserCookieQuery``
- ``BrowserCookieDomainMatch``
- ``BrowserCookieRecord``
- ``BrowserCookieScope``
- ``BrowserCookieStoreRecords``
- ``BrowserCookieOriginStrategy``
