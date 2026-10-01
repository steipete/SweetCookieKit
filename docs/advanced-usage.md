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

For Safari, Chromium, and Gecko stores, each record's `scope` retains whether the stored cookie was host-only or a domain cookie. For example, stored `.example.com` and `example.com` cookies both have the normalized `domain` value `example.com`, with `.domain` and `.hostOnly` scope respectively.

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

All three readers share an in-memory memo of decoded LevelDB entries, before origin or token filtering. The memo holds at most eight directories, evicts the least recently used directory, and reuses a result for at most ten minutes from its original read. Every lookup checks file names, sizes, nanosecond modification times, inode/device identity, and permission/change metadata. Changes to `CURRENT`, `MANIFEST-*`, `.log`, `.ldb`, or `.sst` files invalidate the memo; the readers continue to decode `.log` and `.ldb` files as before.

Only complete reads with successful decoding and matching before/after file snapshots are memoized. Unreadable, missing, malformed, or concurrently changing files retain the usual best-effort results and diagnostics, without caching those results. Hits preserve traversal order and replay the same diagnostics. Directory metadata is still inspected on hits, but file contents are not read again.

Cached values can contain session tokens and are never persisted or logged by the memo. Hosts can explicitly drop the shared memo on sign-out or whenever they want the next call to read files again:

```swift
ChromiumLocalStorageReader.invalidateCache()
```

Invalidation also covers calls through `ChromiumLevelDBReader`. Reads and invalidation are thread-safe; invalidation waits for any active traversal before clearing its memo. Arrays already returned to callers remain owned by those callers.

The ten-minute reuse limit uses a continuous clock, so time spent asleep also counts toward expiry.
