#if os(macOS)
import Foundation
import SQLite3

/// Reads cookies from Gecko profile databases and session recovery files (macOS).
enum GeckoCookieImporter {
    enum ImportError: LocalizedError {
        case cookieDBNotFound(path: String, browser: Browser)
        case cookieDBNotReadable(path: String, browser: Browser)
        case sqliteFailed(message: String, browser: Browser)

        var errorDescription: String? {
            switch self {
            case let .cookieDBNotFound(path, browser):
                "\(browser.displayName) cookie DB not found at \(path)."
            case let .cookieDBNotReadable(path, browser):
                "\(browser.displayName) cookie DB exists but is not readable (\(path))."
            case let .sqliteFailed(message, browser):
                "Failed to read \(browser.displayName) cookies: \(message)"
            }
        }
    }

    struct CookieRecord: Sendable {
        let host: String
        let name: String
        let path: String
        let value: String
        let expires: Date?
        let sessionExpiry: Date?
        let sameSitePolicy: HTTPCookieStringPolicy?
        let isSecure: Bool
        let isHTTPOnly: Bool
    }

    static func availableStores(for browser: Browser, homeDirectories: [URL]) -> [BrowserCookieStore] {
        let metadata = BrowserCatalog.metadata(for: browser)
        guard let profilesFolder = metadata.geckoProfilesFolder else { return [] }
        let labelPrefix = metadata.displayName

        let roots: [URL] = homeDirectories.map { home in
            home
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent(profilesFolder)
                .appendingPathComponent("Profiles")
        }

        var candidates: [GeckoProfileCandidate] = []
        for root in roots {
            candidates.append(contentsOf: Self.geckoProfileCookieDBs(
                root: root,
                labelPrefix: labelPrefix,
                browser: browser))
        }
        return candidates
            .filter { FileManager.default.fileExists(atPath: $0.cookiesDB.path) }
            .filter { candidate in
                metadata.geckoProfileSelection.includes(
                    remotingName: Self.remotingName(for: candidate.cookiesDB.deletingLastPathComponent()))
            }
            .map { candidate in
                BrowserCookieStore(
                    browser: candidate.browser,
                    profile: candidate.profile,
                    kind: .primary,
                    label: candidate.label,
                    databaseURL: candidate.cookiesDB)
            }
    }

    static func loadCookies(
        from store: BrowserCookieStore,
        matchingDomains domains: [String],
        domainMatch: BrowserCookieDomainMatch) throws -> [CookieRecord]
    {
        guard let sourceDB = store.databaseURL else {
            throw ImportError.cookieDBNotFound(
                path: "Missing cookie DB for \(store.label)",
                browser: store.browser)
        }
        var (cookies, expiryDivisor) = try Self.readCookiesFromLockedGeckoDB(
            sourceDB: sourceDB,
            matchingDomains: domains,
            domainMatch: domainMatch,
            browser: store.browser)
        var identities = Set(cookies.map(CookieIdentity.init))
        let sessions = GeckoSessionCookieReader.readCookies(
            in: sourceDB.deletingLastPathComponent(), expiryDivisor: expiryDivisor)
        for cookie in sessions where BrowserCookieDomainMatcher.matches(
            domain: cookie.host, patterns: domains, match: domainMatch)
        {
            // An expired or unsupported SQLite row must still suppress stale recovery values.
            if identities.insert(CookieIdentity(cookie)).inserted {
                cookies.append(cookie)
            }
        }
        return cookies.filter { $0.sameSitePolicy != nil }
    }

    private struct CookieIdentity: Hashable {
        let host: String
        let name: String
        let path: String

        init(_ cookie: CookieRecord) {
            self.host = cookie.host
            self.name = cookie.name
            self.path = cookie.path
        }
    }

    // MARK: - DB copy helper

    private static func readCookiesFromLockedGeckoDB(
        sourceDB: URL,
        matchingDomains: [String],
        domainMatch: BrowserCookieDomainMatch,
        browser: Browser) throws -> (cookies: [CookieRecord], expiryDivisor: TimeInterval)
    {
        guard FileManager.default.isReadableFile(atPath: sourceDB.path) else {
            throw ImportError.cookieDBNotReadable(path: sourceDB.path, browser: browser)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweet-cookie-kit-gecko-cookies-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let copiedDB = tempDir.appendingPathComponent("cookies.sqlite")
        try FileManager.default.copyItem(at: sourceDB, to: copiedDB)

        for suffix in ["-wal", "-shm"] {
            let src = URL(fileURLWithPath: sourceDB.path + suffix)
            if FileManager.default.fileExists(atPath: src.path) {
                let dst = URL(fileURLWithPath: copiedDB.path + suffix)
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }

        defer { try? FileManager.default.removeItem(at: tempDir) }

        return try Self.readCookies(
            fromDB: copiedDB.path,
            matchingDomains: matchingDomains,
            domainMatch: domainMatch,
            browser: browser)
    }

    // MARK: - SQLite read

    private static func readCookies(
        fromDB path: String,
        matchingDomains: [String],
        domainMatch: BrowserCookieDomainMatch,
        browser: Browser) throws -> (cookies: [CookieRecord], expiryDivisor: TimeInterval)
    {
        var db: OpaquePointer?
        // Only the disposable copy is writable, so SQLite can recreate missing WAL sidecars.
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
            throw ImportError.sqliteFailed(message: String(cString: sqlite3_errmsg(db)), browser: browser)
        }
        defer { sqlite3_close(db) }

        var version: OpaquePointer?
        defer { sqlite3_finalize(version) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &version, nil) == SQLITE_OK,
              sqlite3_step(version) == SQLITE_ROW
        else {
            throw ImportError.sqliteFailed(message: String(cString: sqlite3_errmsg(db)), browser: browser)
        }
        // Gecko schema 16 migrated expiry from seconds to milliseconds.
        let expiryDivisor: TimeInterval = sqlite3_column_int(version, 0) >= 16 ? 1000 : 1

        let conditions = BrowserCookieDomainMatcher.sqlCondition(
            column: "host",
            patterns: matchingDomains,
            match: domainMatch)
        func columnExists(_ column: String) -> Bool {
            sqlite3_table_column_metadata(db, nil, "moz_cookies", column, nil, nil, nil, nil, nil) == SQLITE_OK
        }
        let originFilter = columnExists("originAttributes") ? "AND originAttributes = ''" : ""
        let partitionFilter = columnExists("isPartitionedAttributeSet") ? "AND isPartitionedAttributeSet = 0" : ""
        let sameSiteColumn = columnExists("sameSite") ? "sameSite" : "0"
        let sql = """
        SELECT host, name, path, value, expiry, isSecure, isHttpOnly, \(sameSiteColumn)
        FROM moz_cookies
        WHERE (\(conditions)) \(originFilter) \(partitionFilter)
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw ImportError.sqliteFailed(message: String(cString: sqlite3_errmsg(db)), browser: browser)
        }
        defer { sqlite3_finalize(stmt) }

        var out: [CookieRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let host = Self.readTextColumn(stmt, index: 0),
                  let name = Self.readTextColumn(stmt, index: 1),
                  let path = Self.readTextColumn(stmt, index: 2),
                  let value = Self.readTextColumn(stmt, index: 3)
            else { continue }

            let sameSitePolicy = sqlite3_column_type(stmt, 7) == SQLITE_INTEGER
                ? Self.sameSitePolicy(for: sqlite3_column_int64(stmt, 7)) : nil
            let expiry = sqlite3_column_int64(stmt, 4)
            let isSecure = sqlite3_column_int(stmt, 5) != 0
            let isHTTPOnly = sqlite3_column_int(stmt, 6) != 0

            let expiresDate = expiry > 0 ? Date(timeIntervalSince1970: TimeInterval(expiry) / expiryDivisor) : nil

            out.append(CookieRecord(
                host: host,
                name: name,
                path: path,
                value: value,
                expires: expiresDate,
                sessionExpiry: nil,
                sameSitePolicy: sameSitePolicy,
                isSecure: isSecure,
                isHTTPOnly: isHTTPOnly))
        }

        return (out, expiryDivisor)
    }

    static func sameSitePolicy(for value: Int64) -> HTTPCookieStringPolicy? {
        switch value {
        case 0: HTTPCookieStringPolicy(rawValue: "None")
        case 1, 256: .sameSiteLax // Gecko's SAMESITE_UNSET uses Lax by default.
        case 2: .sameSiteStrict
        default: nil
        }
    }

    private static func readTextColumn(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    // MARK: - Profile discovery

    private struct GeckoProfileCandidate: Sendable {
        let browser: Browser
        let profile: BrowserProfile
        let label: String
        let cookiesDB: URL
    }

    private static func geckoProfileCookieDBs(
        root: URL,
        labelPrefix: String,
        browser: Browser) -> [GeckoProfileCandidate]
    {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        let profileDirs = entries.filter { url in
            guard let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory), isDir else {
                return false
            }
            return true
        }
        .sorted { lhs, rhs in
            let left = Self.profileSortKey(lhs.lastPathComponent)
            let right = Self.profileSortKey(rhs.lastPathComponent)
            if left.rank != right.rank {
                return left.rank < right.rank
            }
            return left.name < right.name
        }

        return profileDirs.map { dir in
            let profileName = dir.lastPathComponent
            let profile = BrowserProfile(id: dir.path, name: profileName)
            let label = "\(labelPrefix) \(profileName)"
            let cookiesDB = dir.appendingPathComponent("cookies.sqlite")
            return GeckoProfileCandidate(browser: browser, profile: profile, label: label, cookiesDB: cookiesDB)
        }
    }

    private static func profileSortKey(_ name: String) -> (rank: Int, name: String) {
        let lower = name.lowercased()
        if lower.contains("default-release") {
            return (0, lower)
        }
        if lower.contains("default") {
            return (1, lower)
        }
        return (2, lower)
    }

    /// Gecko channels share a profile root. The profile's last application identifies
    /// which installed channel currently owns it without relying on profile naming.
    private static func remotingName(for profileDirectory: URL) -> String? {
        let compatibilityURL = profileDirectory.appendingPathComponent("compatibility.ini")
        guard let compatibility = Self.iniContents(at: compatibilityURL) else { return nil }

        let appDirectory = Self.iniValue(named: "LastAppDir", in: compatibility)
        let platformDirectory = Self.iniValue(named: "LastPlatformDir", in: compatibility)
        var applicationINIs: [URL] = []
        if let appDirectory, appDirectory.hasPrefix("/") {
            applicationINIs.append(
                URL(fileURLWithPath: appDirectory)
                    .deletingLastPathComponent()
                    .appendingPathComponent("application.ini"))
        }
        if let platformDirectory, platformDirectory.hasPrefix("/") {
            applicationINIs.append(
                URL(fileURLWithPath: platformDirectory)
                    .appendingPathComponent("application.ini"))
        }

        for applicationINI in applicationINIs {
            guard let application = Self.iniContents(at: applicationINI),
                  let remotingName = Self.iniValue(named: "RemotingName", in: application),
                  !remotingName.isEmpty
            else { continue }
            return remotingName
        }
        return nil
    }

    private static func iniContents(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1024) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func iniValue(named name: String, in contents: String) -> String? {
        let prefix = "\(name)="
        for line in contents.split(whereSeparator: { $0.isNewline }) where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
#endif
