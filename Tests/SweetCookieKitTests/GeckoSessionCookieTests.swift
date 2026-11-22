import Compression
import Foundation
import SQLite3
import Testing
@testable import SweetCookieKit

#if os(macOS)
struct GeckoSessionCookieTests {
    @Test(arguments: [Browser.firefox, .firefoxBeta, .firefoxDeveloperEdition, .firefoxNightly, .zen])
    func `imports compressed recovery session cookies alongside SQLite`(browser: Browser) throws {
        let fixture = try Fixture(browser: browser)
        defer { fixture.remove() }
        let recovery = try fixture.writeRecovery(cookies: [
            Self.cookie(host: ".example.com", name: "login", value: "synthetic-session"),
        ])
        let originalDatabase = try Data(contentsOf: fixture.database)
        let originalRecovery = try Data(contentsOf: recovery)

        let records = try fixture.records()

        #expect(Set(records.map(\.name)) == ["persistent", "login"])
        let session = try #require(records.first { $0.name == "login" })
        #expect(session.value == "synthetic-session")
        #expect(session.domain == "example.com")
        #expect(session.scope == .domain)
        #expect(session.expires == nil)
        #expect(session.isSecure)
        #expect(session.isHTTPOnly)
        let converted = try #require(BrowserCookieClient.makeHTTPCookies([session]).first)
        #expect(converted.isSessionOnly)
        #expect(try Data(contentsOf: fixture.database) == originalDatabase)
        #expect(try Data(contentsOf: recovery) == originalRecovery)
    }

    @Test
    func `SQLite wins duplicates while scope and path remain distinct`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeRecovery(cookies: [
            Self.cookie(host: ".example.com", name: "persistent", value: "stale"),
            Self.cookie(host: "example.com", name: "persistent", value: "host-only"),
            Self.cookie(host: ".example.com", name: "persistent", value: "different-path", path: "/app"),
            Self.cookie(name: "login", value: "first"),
            Self.cookie(name: "login", value: "second"),
        ])

        let records = try fixture.records()
        #expect(records.count == 4)
        #expect(records.map(\.value) == ["synthetic-db", "host-only", "different-path", "first"])
        #expect(records[0].scope == .domain)
        #expect(records[1].scope == .hostOnly)
        #expect(records[2].path == "/app")
    }

    @Test(arguments: [false, true])
    func `expired or unsupported SQLite cookie is not resurrected by recovery`(unsupported: Bool) throws {
        let fixture = try Fixture(sqliteSameSite: unsupported ? 999 : 0)
        defer { fixture.remove() }
        try fixture.writeRecovery(cookies: [Self.cookie(host: ".example.com", name: "persistent")])
        let date = Date(timeIntervalSince1970: unsupported ? 200 : 4000000001)
        let records = try fixture.records(query: .init(referenceDate: date))
        #expect(records.isEmpty)
    }

    @Test(arguments: [15, 16])
    func `explicit recovery expiry participates in expiry filtering`(schema: Int) throws {
        let fixture = try Fixture(schema: schema)
        let expiryMultiplier = schema == 16 ? 1000 : 1
        defer { fixture.remove() }
        var expired = Self.cookie(name: "expired")
        expired["expiry"] = 100 * expiryMultiplier
        var fresh = Self.cookie(name: "fresh")
        fresh["expiry"] = 300 * expiryMultiplier
        var invalid = Self.cookie(name: "invalid")
        invalid["expiry"] = true
        try fixture.writeRecovery(cookies: [expired, fresh, invalid, Self.cookie(name: "session")])

        let now = Date(timeIntervalSince1970: 200)
        let records = try fixture.records(query: .init(referenceDate: now))
        #expect(records.map(\.name) == ["persistent", "fresh", "session"])
        #expect(records.first?.expires == Date(timeIntervalSince1970: 4000000000))
        let session = try #require(records.first { $0.name == "fresh" })
        #expect(session.expires == nil)
        #expect(try #require(BrowserCookieClient.makeHTTPCookies([session]).first).isSessionOnly)
        #expect(try fixture.records(query: .init(includeExpired: true, referenceDate: now))
            .map(\.name) == ["persistent", "expired", "fresh", "session"])
    }

    @Test
    func `omitted default name and path match Firefox restore semantics`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeRecovery(cookies: [["host": "example.com", "value": "unnamed"]])
        let records = try fixture.records()
        #expect(records.count == 2)
        let session = try #require(records.first { $0.value == "unnamed" })
        #expect(session.name.isEmpty)
        #expect(session.path.isEmpty)
        #expect(session.expires == nil)
    }

    @Test
    func `isolated and partitioned recovery cookies are not flattened into ordinary cookies`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var container = Self.cookie(name: "login", value: "container")
        container["originAttributes"] = ["userContextId": 3]
        var partitioned = Self.cookie(name: "partitioned")
        partitioned["originAttributes"] = ["partitionKey": "(https,example.org)"]
        var partitionFlag = Self.cookie(name: "partition-flag")
        partitionFlag["isPartitioned"] = true
        var privateCookie = Self.cookie(name: "private")
        privateCookie["originAttributes"] = ["privateBrowsingId": 1]
        var firstParty = Self.cookie(name: "first-party")
        firstParty["originAttributes"] = ["firstPartyDomain": "example.org"]
        var unknown = Self.cookie(name: "unknown")
        unknown["originAttributes"] = ["futureIsolation": 1]
        var malformed = Self.cookie(name: "malformed")
        malformed["originAttributes"] = "^userContextId=1"
        var ordinary = Self.cookie(name: "login", value: "ordinary")
        ordinary["originAttributes"] = [
            "userContextId": 0, "privateBrowsingId": 0, "firstPartyDomain": "", "partitionKey": "",
        ]
        try fixture.writeRecovery(cookies: [
            container, partitioned, partitionFlag, privateCookie, firstParty, unknown, malformed, ordinary,
        ])
        #expect(try fixture.records().map(\.value) == ["synthetic-db", "ordinary"])
    }

    @Test(arguments: [BrowserCookieDomainMatch.exact, .suffix, .contains])
    func `recovery uses requested domain matching`(match: BrowserCookieDomainMatch) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeRecovery(cookies: [
            Self.cookie(host: ".example.com", name: "root"),
            Self.cookie(host: "sub.example.com", name: "sub"),
            Self.cookie(host: "example.com.other", name: "contains"),
            Self.cookie(host: "unrelated.test", name: "unrelated"),
        ])
        let records = try fixture.records(query: .init(domains: ["EXAMPLE.COM"], domainMatch: match))
        let expected: Set<String>
        switch match {
        case .exact: expected = ["persistent", "root"]
        case .suffix: expected = ["persistent", "root", "sub"]
        case .contains: expected = ["persistent", "root", "sub", "contains"]
        }
        #expect(Set(records.map(\.name)) == expected)
        #expect(try fixture.records(query: .init()).count == 5)
    }

    @Test
    func `backup is used only when primary is absent`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(try fixture.records().map(\.value) == ["synthetic-db"])
        try fixture.writeRecovery(cookies: [Self.cookie(value: "backup")], name: "recovery.baklz4")
        #expect(try fixture.records().map(\.value) == ["synthetic-db", "backup"])
        let primary = try fixture.writeRecovery(cookies: [Self.cookie(value: "primary")])
        #expect(try fixture.records().map(\.value) == ["synthetic-db", "primary"])
        try fixture.writeRecovery(cookies: [])
        #expect(try fixture.records().map(\.value) == ["synthetic-db"])
        try Data("corrupt current snapshot".utf8).write(to: primary)
        #expect(try fixture.records().map(\.value) == ["synthetic-db"])
    }

    @Test
    func `clean shutdown snapshot takes precedence over stale recovery backup`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeRecovery(cookies: [Self.cookie(value: "stale-backup")], name: "recovery.baklz4")
        let clean = try fixture.writeRecovery(cookies: [Self.cookie(value: "clean")], name: "sessionstore.jsonlz4")
        #expect(try fixture.records().map(\.value) == ["synthetic-db", "clean"])
        let primary = try fixture.writeRecovery(cookies: [Self.cookie(value: "current")])
        #expect(try fixture.records().map(\.value) == ["synthetic-db", "current"])
        try FileManager.default.removeItem(at: primary)
        try Data("corrupt clean snapshot".utf8).write(to: clean)
        #expect(try fixture.records().map(\.value) == ["synthetic-db"])
    }

    @Test
    func `isolated SQLite identity does not suppress ordinary recovery cookie`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var handle: OpaquePointer?
        try #require(sqlite3_open(fixture.database.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        let sql = """
        ALTER TABLE moz_cookies ADD COLUMN originAttributes TEXT NOT NULL DEFAULT '';
        ALTER TABLE moz_cookies ADD COLUMN isPartitionedAttributeSet INTEGER NOT NULL DEFAULT 0;
        UPDATE moz_cookies SET originAttributes = '^userContextId=2';
        INSERT INTO moz_cookies
            SELECT host, 'partitioned', path, value, expiry, isSecure, isHttpOnly, 0, '', 1 FROM moz_cookies;
        INSERT INTO moz_cookies
            SELECT host, 'unspecified', path, value, expiry, isSecure, isHttpOnly, 256, '', 0
            FROM moz_cookies WHERE name = 'persistent';
        """
        try #require(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        var ordinary = Self.cookie(host: ".example.com", name: "persistent", value: "ordinary")
        ordinary["sameSite"] = 2
        try fixture.writeRecovery(cookies: [ordinary])

        let cookies = BrowserCookieClient.makeHTTPCookies(try fixture.records())
        #expect(cookies.map(\.name) == ["unspecified", "persistent"])
        #expect(cookies.map(\.sameSitePolicy) == [.sameSiteLax, .sameSiteStrict])
        #expect(cookies.last?.value == "ordinary")
    }

    @Test
    func `malformed entries do not hide valid cookies`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let root: [String: Any] = ["cookies": [
            "invalid entry",
            ["host": "example.com", "name": "missing-value", "path": "/"],
            ["host": "", "name": "empty-host", "path": "/", "value": "invalid"],
            ["host": "example.com", "name": "minimal", "path": "/", "value": ""],
            Self.cookie(name: "unicode", value: "synthetic-🍪"),
        ]]
        try fixture.writeJSON(JSONSerialization.data(withJSONObject: root))
        let records = try fixture.records()
        #expect(records.map(\.name) == ["persistent", "minimal", "unicode"])
        #expect(records[1].value.isEmpty)
        #expect(!records[1].isSecure)
        #expect(!records[1].isHTTPOnly)
        #expect(records[2].value == "synthetic-🍪")
    }

    @Test
    func `truncated malformed and oversized recovery files preserve SQLite imports`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.writeRecovery(cookies: [Self.cookie()])
        let valid = try Data(contentsOf: url)
        for count in 0..<valid.count {
            try Data(valid.prefix(count)).write(to: url)
            #expect(GeckoSessionCookieReader.readCookies(in: fixture.directory).isEmpty)
        }
        var badMagic = valid
        badMagic[0] = 0
        try badMagic.write(to: url)
        #expect(GeckoSessionCookieReader.readCookies(in: fixture.directory).isEmpty)
        let originalLength = valid[8..<12].enumerated().reduce(0) { $0 | (UInt32($1.element) << (8 * $1.offset)) }
        for length in [0, originalLength - 1, originalLength + 1, UInt32.max] {
            var invalid = valid
            var littleEndian = length.littleEndian
            withUnsafeBytes(of: &littleEndian) { invalid.replaceSubrange(8..<12, with: $0) }
            try invalid.write(to: url)
            #expect(GeckoSessionCookieReader.readCookies(in: fixture.directory).isEmpty)
        }
        for json in [Data("invalid JSON".utf8), Data("{\"cookies\":false}".utf8)] {
            try fixture.writeJSON(json)
            #expect(try fixture.records().map(\.name) == ["persistent"])
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 64 * 1024 * 1024 + 1)
        try handle.close()
        #expect(try fixture.records().map(\.name) == ["persistent"])
    }

    @Test
    func `accepts independently encoded literal LZ4 block`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let json = Data("""
        {"cookies":[{"host":"example.com","name":"literal","path":"/","value":"ok"}]}
        """.utf8)
        var data = Data("mozLz40\0".utf8)
        var length = UInt32(json.count).littleEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        // Token with a literal run longer than 15 bytes, followed by its extension and final literals.
        data.append(contentsOf: [0xF0, UInt8(json.count - 15)])
        data.append(json)
        let url = try fixture.writeRecovery(cookies: [])
        try data.write(to: url)
        #expect(try fixture.records().map(\.name) == ["persistent", "literal"])
    }

    private static func cookie(
        host: String = "example.com",
        name: String = "login",
        value: String = "synthetic-session",
        path: String = "/") -> [String: Any]
    {
        ["host": host, "name": name, "value": value, "path": path,
         "secure": true, "httponly": true, "originAttributes": [:], "sameSite": 0, "schemeMap": 2]
    }

    private struct Fixture {
        let directory: URL
        let browser: Browser
        var database: URL { self.directory.appendingPathComponent("cookies.sqlite") }

        init(browser: Browser = .firefox, schema: Int = 15, sqliteSameSite: Int = 0) throws {
            self.browser = browser
            self.directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("GeckoSessionTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            var handle: OpaquePointer?
            try #require(sqlite3_open(self.database.path, &handle) == SQLITE_OK)
            defer { sqlite3_close(handle) }
            let expiry = schema == 16 ? Int64(4000000000000) : 4000000000
            let sql = """
            PRAGMA user_version = \(schema);
            CREATE TABLE moz_cookies (host TEXT, name TEXT, path TEXT, value TEXT, expiry INTEGER,
                                     isSecure INTEGER, isHttpOnly INTEGER, sameSite INTEGER);
            INSERT INTO moz_cookies VALUES ('.example.com', 'persistent', '/', 'synthetic-db',
                                            \(expiry), 1, 1, \(sqliteSameSite));
            """
            try #require(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }

        func remove() {
            try? FileManager.default.removeItem(at: self.directory)
        }

        func records(query: BrowserCookieQuery = .init(domains: ["example.com"], domainMatch: .suffix)) throws
            -> [BrowserCookieRecord]
        {
            let store = BrowserCookieStore(
                browser: self.browser,
                profile: .init(id: "synthetic", name: "Synthetic"),
                kind: .primary,
                label: "Synthetic",
                databaseURL: self.database)
            return try BrowserCookieClient(configuration: .init(homeDirectories: [self.directory]))
                .records(matching: query, in: store)
        }

        @discardableResult
        func writeRecovery(cookies: [[String: Any]], name: String = "recovery.jsonlz4") throws -> URL {
            let json = try JSONSerialization.data(withJSONObject: ["cookies": cookies])
            return try self.writeJSON(json, name: name)
        }

        @discardableResult
        func writeJSON(_ json: Data, name: String = "recovery.jsonlz4") throws -> URL {
            var compressed = [UInt8](repeating: 0, count: json.count * 2 + 64)
            let count = json.withUnsafeBytes { source in
                compression_encode_buffer(
                    &compressed,
                    compressed.count,
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    json.count,
                    nil,
                    COMPRESSION_LZ4_RAW)
            }
            var length = UInt32(json.count).littleEndian
            var data = Data("mozLz40\0".utf8)
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            if count > 0 {
                data.append(contentsOf: compressed.prefix(count))
            } else {
                // Apple's encoder returns zero when short input cannot be compressed.
                data.append(UInt8(min(json.count, 15)) << 4)
                if json.count >= 15 {
                    var extra = json.count - 15
                    while extra >= 255 {
                        data.append(255)
                        extra -= 255
                    }
                    data.append(UInt8(extra))
                }
                data.append(json)
            }
            let url = self.directory.appendingPathComponent(
                name == "sessionstore.jsonlz4" ? name : "sessionstore-backups/\(name)")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        }
    }
}
#endif
