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

Firefox and other Gecko cookie imports read temporary copies of the database and any WAL sidecars. Both active profiles with uncheckpointed cookies and idle WAL-mode profiles without sidecars are supported; the browser's original files remain unchanged.

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

### Strict credential reads

For credential discovery on macOS, use one exact raw LevelDB user key:

```swift
let rawKey = Data("_https://example.com\0".utf8) + Data([1]) + Data("access_token".utf8)
let rawValue = ChromiumLocalStorageReader.readCurrentValue(forRawKey: rawKey, in: levelDBURL)
```

The result contains the stored bytes, including Chromium's encoding prefix. Matching is byte-for-byte, without origin normalization or token scanning. The reader requires `CURRENT`, a valid manifest, and all referenced live tables and required recovery logs. It checks record/block checksums and sequence conflicts before selecting the current value; missing or deleted keys and rejected reads all return `nil`. It never falls back to orphan-file scanning or the shared memo.

Supply a physical file URL with no symlinked directory components. Directory descriptors anchor `openat`/`O_NOFOLLOW` file opens and `pread` reads; symlinked files, files over 64 MiB, and observable replacement or mutation are rejected. This is still a live read, not a transactional snapshot: changes after the final check and rename/restore races cannot all be excluded.

### Best-effort reads and caching

All three readers select the highest LevelDB sequence for each raw user key before decoding or scanning. Write-batch operations advance the batch's sequence; `.ldb` and `.sst` records use their internal-key sequence and value type. A newer deletion hides an older value, while a newer value survives an older deletion. File modification times do not determine which value is current. Text and token scans exclude replaced and deleted records.

When `CURRENT` is present, the reader replays its manifest to select live tables and recoverable logs, excluding obsolete tables and logs left after compaction. Without `CURRENT`, it scans all `.log`, `.ldb`, and `.sst` files using the same sequence ordering; this fallback cannot identify obsolete files whose records have no newer counterpart. An unreadable or malformed current manifest yields no entries rather than guessing which files are live. Reads remain best effort against a running browser, without a transactional snapshot or full LevelDB checksum validation.

All three readers share an in-memory memo of decoded LevelDB entries, before origin or token filtering. The memo holds at most eight directories, evicts the least recently used directory, and reuses a result for at most ten minutes from its original read. Every lookup checks file names, sizes, nanosecond modification times, inode/device identity, and permission/change metadata. Changes to `CURRENT`, `MANIFEST-*`, `.log`, `.ldb`, or `.sst` files invalidate the memo.

Each directory memo also retains the text-entry array, token candidates keyed by `minimumLength`, and local-storage results keyed by normalized origin. Repeated queries return the original arrays in the same order without decoding text or rescanning tokens. Token and origin results each retain at most sixteen parameter variants using LRU eviction. These derived results expire and invalidate together with their raw entries; deriving a new variant does not extend the original ten-minute lifetime.

Only complete reads with successful decoding and matching before/after file snapshots are memoized. Unreadable, missing, malformed, or concurrently changing files retain the usual best-effort results and diagnostics, without caching those results. Hits preserve traversal order and replay the same diagnostics. Directory metadata is still inspected on hits, but file contents are not read again.

Cached values can contain session tokens and are never persisted or logged by the memo. Hosts can explicitly drop the shared memo on sign-out or whenever they want the next call to read files again:

```swift
ChromiumLocalStorageReader.invalidateCache()
```

Invalidation also covers calls through `ChromiumLevelDBReader`. Reads and invalidation are thread-safe; invalidation waits for any active traversal or derivation before clearing its memo. Arrays already returned to callers remain owned by those callers.

The ten-minute reuse limit uses a continuous clock, so time spent asleep also counts toward expiry.
