import Foundation
import SQLite3
import Testing
@testable import SweetCookieKit

#if os(macOS)

struct CookieDomainQueryTests {
    @Test(arguments: [Browser.chrome, .firefox])
    func `SQL cookie queries normalize patterns and match metacharacters literally`(browser: Browser) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cookie-domain-query-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Cookies")
        try Self.writeCookies(at: databaseURL)
        let store = BrowserCookieStore(
            browser: browser,
            profile: BrowserProfile(id: "synthetic", name: "Synthetic"),
            kind: .primary,
            label: "Synthetic",
            databaseURL: databaseURL)
        let client = BrowserCookieClient(configuration: .init(homeDirectories: [directory]))
        let cases: [(patterns: [String], expected: Set<String>)] = [
            ([" .EXAMPLE.com \n"], ["example.com", ".example.com", "sub.example.com"]),
            (["a_b.test"], ["a_b.test"]),
            (["a%b.test"], ["a%b.test"]),
            (["a\\b.test"], ["a\\b.test"]),
            (["a'b.test"], ["a'b.test"]),
            (["missing.test", "a_b.test"], ["a_b.test"]),
        ]
        try BrowserCookieKeychainAccessGate.withUserInteractionDisallowed {
            for match in [BrowserCookieDomainMatch.contains, .suffix] {
                for test in cases {
                    let query = BrowserCookieQuery(domains: test.patterns, domainMatch: match)
                    let records = try client.records(matching: query, in: store)
                    #expect(Set(records.map(\.name)) == test.expected,
                            "\(browser) \(match) \(test.patterns)")
                    #expect(records.allSatisfy { $0.value == "synthetic" })
                }
            }
        }
    }

    private static func writeCookies(at url: URL) throws {
        var database: OpaquePointer?
        try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let schema = """
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        INSERT INTO meta VALUES ('version', '23');
        CREATE TABLE cookies (host_key TEXT, name TEXT, path TEXT, expires_utc INTEGER,
                              is_secure INTEGER, is_httponly INTEGER, encrypted_value BLOB, value TEXT,
                              top_frame_site_key TEXT, samesite INTEGER);
        CREATE TABLE moz_cookies (host TEXT, name TEXT, path TEXT, value TEXT, expiry INTEGER,
                                 isSecure INTEGER, isHttpOnly INTEGER);
        """
        try #require(sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK)
        let hosts = ["example.com", ".example.com", "sub.example.com", "a_b.test", "a%b.test",
                     "a\\b.test", "a'b.test", "axb.test", "ab.test", "unrelated.test"]
        for host in hosts {
            let literal = host.replacingOccurrences(of: "'", with: "''")
            let insert = """
            INSERT INTO cookies VALUES ('\(literal)', '\(literal)', '/', 0, 0, 0, X'', 'synthetic', '', -1);
            INSERT INTO moz_cookies VALUES ('\(literal)', '\(literal)', '/', 'synthetic', 0, 0, 0);
            """
            try #require(sqlite3_exec(database, insert, nil, nil, nil) == SQLITE_OK)
        }
    }
}

#endif
