import Foundation

#if os(macOS)

/// Supported browsers for cookie extraction on macOS.
public enum Browser: String, Sendable, Hashable, CaseIterable {
    case safari
    case chrome
    case chromeBeta
    case chromeCanary
    case arc
    case arcBeta
    case arcCanary
    case chatgptAtlas
    case chromium
    case firefox
    case brave
    case braveBeta
    case braveNightly
    case edge
    case edgeBeta
    case edgeCanary
    case vivaldi

    public var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .chromeBeta: "Chrome Beta"
        case .chromeCanary: "Chrome Canary"
        case .arc: "Arc"
        case .arcBeta: "Arc Beta"
        case .arcCanary: "Arc Canary"
        case .chatgptAtlas: "ChatGPT Atlas"
        case .chromium: "Chromium"
        case .firefox: "Firefox"
        case .brave: "Brave"
        case .braveBeta: "Brave Beta"
        case .braveNightly: "Brave Nightly"
        case .edge: "Microsoft Edge"
        case .edgeBeta: "Microsoft Edge Beta"
        case .edgeCanary: "Microsoft Edge Canary"
        case .vivaldi: "Vivaldi"
        }
    }

    var engine: BrowserEngine {
        switch self {
        case .safari:
            .webkit
        case .firefox:
            .firefox
        default:
            .chromium
        }
    }
}

enum BrowserEngine: Sendable {
    case webkit
    case chromium
    case firefox
}

/// Ordered list of browsers to try when importing cookies.
public enum BrowserCookieImportOrder: Sendable {
    case safariChromeFirefox

    public var browsers: [Browser] {
        switch self {
        case .safariChromeFirefox:
            [.safari, .chrome, .firefox]
        }
    }

    /// Human-readable label for settings UI.
    public var displayLabel: String {
        switch self {
        case .safariChromeFirefox:
            "Safari → Chrome → Firefox"
        }
    }

    /// Short label for compact UI.
    public var shortLabel: String {
        switch self {
        case .safariChromeFirefox:
            "Safari/Chrome/Firefox"
        }
    }

    /// Hint for user-facing login prompts.
    public var loginHint: String {
        switch self {
        case .safariChromeFirefox:
            "Safari, Chrome, or Firefox"
        }
    }
}

/// Domain matching strategy for cookie queries.
public enum BrowserCookieDomainMatch: Sendable {
    case contains
    case suffix
    case exact
}

/// Maps a cookie domain to an origin URL when building `HTTPCookie` values.
public enum BrowserCookieOriginStrategy: Sendable {
    /// Use `https://{domain}`.
    case domainBased
    /// Always use the provided origin URL.
    case fixed(URL)
    /// Custom resolver that maps domain → origin URL.
    case custom(@Sendable (String) -> URL?)

    func resolve(domain: String) -> URL? {
        switch self {
        case .domainBased:
            URL(string: "https://\(domain)")
        case let .fixed(url):
            url
        case let .custom(resolver):
            resolver(domain)
        }
    }
}

/// Query definition for fetching browser cookies.
public struct BrowserCookieQuery: Sendable {
    /// Domain patterns to match (empty = no filtering).
    public var domains: [String]
    /// Matching strategy for domains.
    public var domainMatch: BrowserCookieDomainMatch
    /// Origin URL resolver for building `HTTPCookie` values.
    public var origin: BrowserCookieOriginStrategy
    /// Include expired cookies when true.
    public var includeExpired: Bool
    /// Reference date used to filter expired cookies.
    public var referenceDate: Date

    public init(
        domains: [String],
        domainMatch: BrowserCookieDomainMatch = .contains,
        origin: BrowserCookieOriginStrategy = .domainBased,
        includeExpired: Bool = false,
        referenceDate: Date = Date())
    {
        self.domains = domains
        self.domainMatch = domainMatch
        self.origin = origin
        self.includeExpired = includeExpired
        self.referenceDate = referenceDate
    }
}

/// A browser profile identifier.
public struct BrowserProfile: Sendable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Which cookie store a browser profile represents.
public enum BrowserCookieStoreKind: String, Sendable {
    case primary
    case network
    case safari
}

/// A concrete cookie store for a browser profile.
public struct BrowserCookieStore: Sendable, Hashable {
    /// Browser family and distribution.
    public let browser: Browser
    /// Browser profile metadata.
    public let profile: BrowserProfile
    /// Cookie store kind (e.g., primary vs network).
    public let kind: BrowserCookieStoreKind
    /// Human-readable label for UI or logs.
    public let label: String
    /// Backing cookie database URL when applicable.
    public let databaseURL: URL?

    public init(
        browser: Browser,
        profile: BrowserProfile,
        kind: BrowserCookieStoreKind,
        label: String,
        databaseURL: URL?)
    {
        self.browser = browser
        self.profile = profile
        self.kind = kind
        self.label = label
        self.databaseURL = databaseURL
    }
}

/// A browser cookie record normalized for cross-browser handling.
public struct BrowserCookieRecord: Sendable {
    public let domain: String
    public let name: String
    public let path: String
    public let value: String
    public let expires: Date?
    public let isSecure: Bool
    public let isHTTPOnly: Bool

    public init(
        domain: String,
        name: String,
        path: String,
        value: String,
        expires: Date?,
        isSecure: Bool,
        isHTTPOnly: Bool)
    {
        self.domain = domain
        self.name = name
        self.path = path
        self.value = value
        self.expires = expires
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }
}

/// Cookie records loaded from a specific browser store.
public struct BrowserCookieStoreRecords: Sendable {
    /// Cookie store that produced these records.
    public let store: BrowserCookieStore
    /// Cookie records from the store.
    public let records: [BrowserCookieRecord]

    public init(store: BrowserCookieStore, records: [BrowserCookieRecord]) {
        self.store = store
        self.records = records
    }

    public var label: String {
        self.store.label
    }

    public var browser: Browser {
        self.store.browser
    }

    public func cookies(origin: BrowserCookieOriginStrategy = .domainBased) -> [HTTPCookie] {
        BrowserCookieClient.makeHTTPCookies(self.records, origin: origin)
    }
}

/// Errors raised when reading browser cookies.
public enum BrowserCookieError: LocalizedError, Sendable {
    case notFound(browser: Browser, details: String)
    case accessDenied(browser: Browser, details: String)
    case loadFailed(browser: Browser, details: String)

    public var errorDescription: String? {
        switch self {
        case let .notFound(_, details), let .accessDenied(_, details), let .loadFailed(_, details):
            details
        }
    }

    public var browser: Browser {
        switch self {
        case let .notFound(browser, _), let .accessDenied(browser, _), let .loadFailed(browser, _):
            browser
        }
    }

    /// Optional guidance for user-facing permission errors.
    public var accessDeniedHint: String? {
        switch self {
        case let .accessDenied(_, details):
            details
        case .notFound, .loadFailed:
            nil
        }
    }
}

/// High-level API for enumerating and reading browser cookies.
public struct BrowserCookieClient: Sendable {
    public struct Configuration: Sendable {
        public var homeDirectories: [URL]

        public init(homeDirectories: [URL] = BrowserCookieClient.defaultHomeDirectories()) {
            self.homeDirectories = homeDirectories
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Returns cookie stores for a specific browser (profile + store kind).
    public func stores(for browser: Browser) -> [BrowserCookieStore] {
        switch browser.engine {
        case .webkit:
            let profile = BrowserProfile(id: "safari.default", name: "Default")
            return [BrowserCookieStore(
                browser: .safari,
                profile: profile,
                kind: .safari,
                label: "Safari",
                databaseURL: nil)]
        case .chromium:
            return ChromeCookieImporter.availableStores(
                for: browser,
                homeDirectories: self.configuration.homeDirectories)
        case .firefox:
            return FirefoxCookieImporter.availableStores(homeDirectories: self.configuration.homeDirectories)
        }
    }

    /// Returns cookie stores for multiple browsers.
    public func stores(in browsers: [Browser]) -> [BrowserCookieStore] {
        browsers.flatMap { self.stores(for: $0) }
    }

    /// Loads cookie records from a specific browser.
    /// - Returns: Records grouped per browser profile/store.
    public func records(
        matching query: BrowserCookieQuery,
        in browser: Browser,
        logger: ((String) -> Void)? = nil) throws -> [BrowserCookieStoreRecords]
    {
        let stores = self.stores(for: browser)
        if stores.isEmpty {
            throw BrowserCookieError.notFound(
                browser: browser,
                details: "\(browser.displayName) cookie store not found.")
        }
        return try stores.compactMap { store in
            let records = try self.records(matching: query, in: store, logger: logger)
            guard !records.isEmpty else { return nil }
            return BrowserCookieStoreRecords(store: store, records: records)
        }
    }

    /// Loads cookie records from a specific cookie store.
    public func records(
        matching query: BrowserCookieQuery,
        in store: BrowserCookieStore,
        logger: ((String) -> Void)? = nil) throws -> [BrowserCookieRecord]
    {
        let records: [BrowserCookieRecord]
        switch store.browser.engine {
        case .webkit:
            do {
                let loaded = try SafariCookieImporter.loadCookies(
                    matchingDomains: query.domains,
                    domainMatch: query.domainMatch,
                    homeDirectories: self.configuration.homeDirectories,
                    logger: logger)
                records = loaded.map { record in
                    BrowserCookieRecord(
                        domain: BrowserCookieDomainMatcher.normalizeDomain(record.domain),
                        name: record.name,
                        path: record.path,
                        value: record.value,
                        expires: record.expires,
                        isSecure: record.isSecure,
                        isHTTPOnly: record.isHTTPOnly)
                }
            } catch let error as SafariCookieImporter.ImportError {
                throw BrowserCookieError.mapSafariError(error, browser: store.browser)
            } catch {
                throw BrowserCookieError.loadFailed(
                    browser: store.browser,
                    details: "Safari cookie load failed: \(error.localizedDescription)")
            }
        case .chromium:
            do {
                let loaded = try ChromeCookieImporter.loadCookies(
                    from: store,
                    matchingDomains: query.domains,
                    domainMatch: query.domainMatch)
                records = loaded.map { record in
                    BrowserCookieRecord(
                        domain: BrowserCookieDomainMatcher.normalizeDomain(record.hostKey),
                        name: record.name,
                        path: record.path,
                        value: record.value,
                        expires: BrowserCookieDomainMatcher.chromeExpiryDate(expiresUTC: record.expiresUTC),
                        isSecure: record.isSecure,
                        isHTTPOnly: record.isHTTPOnly)
                }
            } catch let error as ChromeCookieImporter.ImportError {
                throw BrowserCookieError.mapChromeError(error, browser: store.browser)
            } catch {
                throw BrowserCookieError.loadFailed(
                    browser: store.browser,
                    details: "\(store.browser.displayName) cookie load failed: \(error.localizedDescription)")
            }
        case .firefox:
            do {
                let loaded = try FirefoxCookieImporter.loadCookies(
                    from: store,
                    matchingDomains: query.domains,
                    domainMatch: query.domainMatch)
                records = loaded.map { record in
                    BrowserCookieRecord(
                        domain: BrowserCookieDomainMatcher.normalizeDomain(record.host),
                        name: record.name,
                        path: record.path,
                        value: record.value,
                        expires: record.expires,
                        isSecure: record.isSecure,
                        isHTTPOnly: record.isHTTPOnly)
                }
            } catch let error as FirefoxCookieImporter.ImportError {
                throw BrowserCookieError.mapFirefoxError(error, browser: store.browser)
            } catch {
                throw BrowserCookieError.loadFailed(
                    browser: store.browser,
                    details: "Firefox cookie load failed: \(error.localizedDescription)")
            }
        }

        return BrowserCookieDomainMatcher.filterExpired(
            records,
            includeExpired: query.includeExpired,
            now: query.referenceDate)
    }

    /// Loads `HTTPCookie` values from a specific cookie store.
    public func cookies(
        matching query: BrowserCookieQuery,
        in store: BrowserCookieStore,
        logger: ((String) -> Void)? = nil) throws -> [HTTPCookie]
    {
        let records = try self.records(matching: query, in: store, logger: logger)
        return Self.makeHTTPCookies(records, origin: query.origin)
    }

    /// Convert cookie records into `HTTPCookie` values.
    public static func makeHTTPCookies(
        _ records: [BrowserCookieRecord],
        origin: BrowserCookieOriginStrategy = .domainBased) -> [HTTPCookie]
    {
        records.compactMap { record in
            let domain = BrowserCookieDomainMatcher.normalizeDomain(record.domain)
            guard !domain.isEmpty else { return nil }
            var props: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: record.path,
                .name: record.name,
                .value: record.value,
                .secure: record.isSecure,
            ]
            if let originURL = origin.resolve(domain: domain) {
                props[.originURL] = originURL
            }
            if record.isHTTPOnly {
                props[.init("HttpOnly")] = "TRUE"
            }
            if let expires = record.expires {
                props[.expires] = expires
            }
            return HTTPCookie(properties: props)
        }
    }

    public static func defaultHomeDirectories() -> [URL] {
        var homes: [URL] = []
        homes.append(FileManager.default.homeDirectoryForCurrentUser)
        if let userHome = NSHomeDirectoryForUser(NSUserName()) {
            homes.append(URL(fileURLWithPath: userHome))
        }
        if let envHome = ProcessInfo.processInfo.environment["HOME"], !envHome.isEmpty {
            homes.append(URL(fileURLWithPath: envHome))
        }
        var seen = Set<String>()
        return homes.filter { home in
            let path = home.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }
}

enum BrowserCookieDomainMatcher {
    static func normalizeDomain(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(".") { return String(trimmed.dropFirst()) }
        return trimmed
    }

    static func matches(domain: String, patterns: [String], match: BrowserCookieDomainMatch) -> Bool {
        guard !patterns.isEmpty else { return true }
        let haystack = self.normalizeDomain(domain).lowercased()
        return patterns.contains { pattern in
            let needle = self.normalizeDomain(pattern).lowercased()
            switch match {
            case .contains:
                return haystack.contains(needle)
            case .suffix:
                return haystack.hasSuffix(needle)
            case .exact:
                return haystack == needle
            }
        }
    }

    static func filterExpired(
        _ records: [BrowserCookieRecord],
        includeExpired: Bool,
        now: Date) -> [BrowserCookieRecord]
    {
        guard !includeExpired else { return records }
        return records.filter { record in
            guard let expires = record.expires else { return true }
            return expires >= now
        }
    }

    static func chromeExpiryDate(expiresUTC: Int64) -> Date? {
        guard expiresUTC > 0 else { return nil }
        let seconds = (Double(expiresUTC) / 1_000_000.0) - 11_644_473_600.0
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func sqlCondition(column: String, patterns: [String], match: BrowserCookieDomainMatch) -> String {
        guard !patterns.isEmpty else { return "1=1" }
        let clauses: [String] = patterns.map { raw in
            let value = self.escapeForSQL(raw)
            switch match {
            case .contains:
                return "\(column) LIKE '%\(value)%'"
            case .suffix:
                return "\(column) LIKE '%\(value)'"
            case .exact:
                let normalized = self.escapeForSQL(self.normalizeDomain(raw))
                return "(\(column) = '\(normalized)' OR \(column) = '.\(normalized)')"
            }
        }
        return clauses.joined(separator: " OR ")
    }

    static func escapeForSQL(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}

extension BrowserCookieError {
    static func mapSafariError(_ error: SafariCookieImporter.ImportError, browser: Browser) -> BrowserCookieError {
        switch error {
        case .cookieFileNotFound:
            BrowserCookieError.notFound(browser: browser, details: error.localizedDescription)
        case .cookieFileNotReadable:
            BrowserCookieError.accessDenied(browser: browser, details: error.localizedDescription)
        case .invalidFile:
            BrowserCookieError.loadFailed(browser: browser, details: error.localizedDescription)
        }
    }

    static func mapChromeError(_ error: ChromeCookieImporter.ImportError, browser: Browser) -> BrowserCookieError {
        switch error {
        case .cookieDBNotFound:
            BrowserCookieError.notFound(browser: browser, details: error.localizedDescription)
        case .keychainDenied:
            BrowserCookieError.accessDenied(browser: browser, details: error.localizedDescription)
        case .sqliteFailed:
            BrowserCookieError.loadFailed(browser: browser, details: error.localizedDescription)
        }
    }

    static func mapFirefoxError(_ error: FirefoxCookieImporter.ImportError, browser: Browser) -> BrowserCookieError {
        switch error {
        case .cookieDBNotFound:
            BrowserCookieError.notFound(browser: browser, details: error.localizedDescription)
        case .cookieDBNotReadable:
            BrowserCookieError.accessDenied(browser: browser, details: error.localizedDescription)
        case .sqliteFailed:
            BrowserCookieError.loadFailed(browser: browser, details: error.localizedDescription)
        }
    }
}

#endif
