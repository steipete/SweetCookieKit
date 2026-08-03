# Advanced usage

SweetCookieKit exposes profile-aware cookie queries, Keychain interaction controls, and best-effort Chromium local-storage readers. Start with the [README quick start](../README.md#quick-start) before using these lower-level APIs.

## Query cookies

`BrowserCookieQuery` filters domains, controls expiry handling, and selects how cookie domains become origin URLs during `HTTPCookie` conversion.

```swift
import SweetCookieKit

let query = BrowserCookieQuery(
    domains: ["example.com"],
    domainMatch: .suffix,
    includeExpired: false)
```

Domain matching supports `.contains`, `.suffix`, and `.exact`. An empty `domains` array does not filter by domain.

Use a concrete store when the user has selected a profile:

```swift
let client = BrowserCookieClient()
let stores = client.stores(for: .chrome)
guard let store = stores.first(where: { $0.profile.name == "Default" }) else {
    fatalError("Chrome Default profile not found")
}

let records = try client.records(matching: query, in: store)
let cookies = try client.cookies(matching: query, in: store)
```

`records(matching:in:)` returns normalized `BrowserCookieRecord` values. `cookies(matching:in:)` converts matching records to `HTTPCookie` values using the query's origin strategy.

## Search multiple browsers

`Browser.defaultImportOrder` contains every supported browser in the package's preferred search order. Callers can loop over that list or provide a smaller selection:

```swift
for browser in Browser.defaultImportOrder {
    let results = try client.records(matching: query, in: browser)
    for result in results {
        print("\(result.label): \(result.records.count)")
    }
}
```

The result stays grouped by profile and store. Use `client.stores(in:)` when an interface needs to list all available sources before reading them.

## Explain Keychain prompts

Chromium-based browsers encrypt cookie values with a Safe Storage credential in macOS Keychain. Set a preflight handler when the host app needs to explain that system prompt before it appears:

```swift
BrowserCookieKeychainPromptHandler.handler = { context in
    // Present the host app's explanation before macOS requests access.
    print("Cookie decryption needs \(context.label)")
}
```

The handler is not called when Keychain can return the credential without interaction.

For background work that must not display Keychain UI, scope the import with `withUserInteractionDisallowed`. SweetCookieKit tries the available Safe Storage labels without interaction and reports `BrowserCookieError.accessDenied` when none can be read:

```swift
let records = try BrowserCookieKeychainAccessGate.withUserInteractionDisallowed {
    try client.records(matching: query, in: store)
}
```

Safari cookie access may require Full Disk Access. Most read failures surface as `BrowserCookieError`; permission failures use `.accessDenied` and expose a user-facing `accessDeniedHint`.

## Read Chromium local storage

Use `ChromiumLocalStorageReader` when the LevelDB directory is already known and the caller needs decoded entries for one origin:

```swift
import SweetCookieKit

let entries = ChromiumLocalStorageReader.readEntries(
    for: "https://example.com",
    in: levelDBURL)
```

For lower-level inspection, `ChromiumLevelDBReader` exposes best-effort text decoding and token candidate scanning:

```swift
let entries = ChromiumLevelDBReader.readTextEntries(in: levelDBURL)
let tokens = ChromiumLevelDBReader.readTokenCandidates(
    in: levelDBURL,
    minimumLength: 80)
```

These helpers read local storage; they do not modify or persist browser data.
