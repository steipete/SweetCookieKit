import Foundation
import Testing
@testable import SweetCookieKit

#if os(macOS)

struct BrowserCookieClientTests {
    @Test
    func `make HTTP cookies sets expected fields`() {
        let record = BrowserCookieRecord(
            domain: ".example.com",
            name: "session",
            path: "/",
            value: "abc",
            expires: Date(timeIntervalSince1970: 1_700_000_000),
            isSecure: true,
            isHTTPOnly: true)

        let cookies = BrowserCookieClient.makeHTTPCookies([record])
        #expect(cookies.count == 1)
        guard let cookie = cookies.first else { return }
        #expect(cookie.domain == "example.com")
        #expect(cookie.name == "session")
        #expect(cookie.path == "/")
        #expect(cookie.value == "abc")
        #expect(cookie.isSecure)
        #expect(cookie.isHTTPOnly)
    }

    @Test
    func `chromium parent and host cookie records remain distinguishable`() {
        let fixtures: [(hostKey: String, scope: BrowserCookieScope)] = [
            (".zoom.us", .domain),
            ("zoom.us", .hostOnly),
            (".ai.zoom.us", .domain),
            ("ai.zoom.us", .hostOnly),
        ]

        for fixture in fixtures {
            let chromiumRecord = ChromeCookieImporter.CookieRecord(
                hostKey: fixture.hostKey,
                name: "synthetic",
                path: "/",
                expiresUTC: 0,
                isSecure: true,
                isHTTPOnly: true,
                value: "synthetic")
            let record = BrowserCookieClient.makeBrowserCookieRecord(chromiumRecord)

            #expect(record.domain == fixture.hostKey.trimmingPrefix("."))
            #expect(record.scope == fixture.scope)
            #expect(record.name == "synthetic")
        }
    }

    @Test
    func `public record initializer accepts normalized domain with explicit scope`() {
        let record = BrowserCookieRecord(
            domain: "zoom.us",
            name: "synthetic",
            path: "/",
            value: "synthetic",
            expires: nil,
            isSecure: true,
            isHTTPOnly: true,
            scope: .domain)

        #expect(record.domain == "zoom.us")
        #expect(record.scope == .domain)
    }

    @Test
    func `legacy record initializer infers scope from an unnormalized domain`() {
        let domainCookie = BrowserCookieRecord(
            domain: ".example.com",
            name: "domain",
            path: "/",
            value: "synthetic",
            expires: nil,
            isSecure: true,
            isHTTPOnly: true)
        let hostCookie = BrowserCookieRecord(
            domain: "example.com",
            name: "host",
            path: "/",
            value: "synthetic",
            expires: nil,
            isSecure: true,
            isHTTPOnly: true)

        #expect(domainCookie.scope == .domain)
        #expect(hostCookie.scope == .hostOnly)
    }

    @Test
    func `browser cookie import order labels`() {
        let order = Browser.defaultImportOrder
        #expect(order.first == .safari)
        #expect(order.contains(.chrome))
        #expect(order.contains(.dia))
        #expect(order.contains(.firefox))
        #expect(order.contains(.firefoxBeta))
        #expect(order.contains(.firefoxDeveloperEdition))
        #expect(order.contains(.firefoxNightly))
        #expect(order.contains(.zen))
        #expect(Set(order).count == order.count)

        let shortList: [Browser] = [.safari, .chrome, .firefox]
        #expect(shortList.displayLabel == "Safari → Chrome → Firefox")
        #expect(shortList.shortLabel == "Safari/Chrome/Firefox")
        #expect(shortList.loginHint == "Safari, Chrome, or Firefox")
    }

    @Test
    func `browser cookie query defaults`() {
        let query = BrowserCookieQuery()
        #expect(query.domains.isEmpty)
        #expect(query.domainMatch == .contains)
        #expect(query.includeExpired == false)
    }

    @Test
    func `firefox channel stores are classified without duplicates`() throws {
        let home = try Self.makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let profiles: [(directory: String, remotingName: String?)] = [
            ("release.default-release", "firefox"),
            ("esr.default-esr", "firefox-esr"),
            ("beta.default-beta", "firefox-beta"),
            ("developer.dev-edition-default", "firefox-dev"),
            ("nightly.default-nightly", "firefox-nightly"),
            ("legacy.default", nil),
        ]
        for profile in profiles {
            try Self.writeGeckoProfile(
                home: home,
                directory: profile.directory,
                remotingName: profile.remotingName)
        }

        let client = BrowserCookieClient(configuration: .init(homeDirectories: [home]))
        let expectedProfiles: [Browser: Set<String>] = [
            .firefox: ["release.default-release", "esr.default-esr", "legacy.default"],
            .firefoxBeta: ["beta.default-beta"],
            .firefoxDeveloperEdition: ["developer.dev-edition-default"],
            .firefoxNightly: ["nightly.default-nightly"],
        ]

        let browsers = expectedProfiles.keys.sorted { $0.rawValue < $1.rawValue }
        for browser in browsers {
            let names = Set(client.stores(for: browser).map(\.profile.name))
            #expect(names == expectedProfiles[browser])
        }

        let stores = client.stores(in: browsers)
        let databasePaths = stores.compactMap(\.databaseURL?.path)
        #expect(Set(databasePaths).count == databasePaths.count)
    }

    @Test
    func `safari stores falls back when no cookie files exist`() throws {
        let home = try Self.makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let client = BrowserCookieClient(configuration: .init(homeDirectories: [home]))
        let stores = client.stores(for: .safari)

        #expect(stores.count == 1)
        #expect(stores.first?.label == "Safari")
        #expect(stores.first?.databaseURL == nil)
    }

    @Test
    func `safari stores discovers website data store cookie files`() throws {
        let home = try Self.makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try Self.writeCookieFile(
            home.appendingPathComponent("Library/Cookies/Cookies.binarycookies"),
            domain: "legacy.example",
            name: "legacy",
            value: "1")
        try Self.writeCookieFile(
            home.appendingPathComponent(
                "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"),
            domain: "default.example",
            name: "default",
            value: "1")
        try Self.writeCookieFile(
            home.appendingPathComponent(
                "Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore")
                .appendingPathComponent("Profile 1/WebsiteData/Cookies/Cookies.binarycookies"),
            domain: "profile1.example",
            name: "profile1",
            value: "1")
        try Self.writeCookieFile(
            home.appendingPathComponent(
                "Library/WebKit/WebsiteDataStore/Profile 2/WebsiteData/Cookies/Cookies.binarycookies"),
            domain: "profile2.example",
            name: "profile2",
            value: "1")

        let client = BrowserCookieClient(configuration: .init(homeDirectories: [home]))
        let stores = client.stores(for: .safari)
        let labels = stores.map(\.label)

        #expect(labels.contains("Safari (Legacy)"))
        #expect(labels.contains("Safari"))
        #expect(labels.contains("Safari (Profile 1)"))
        #expect(labels.contains("Safari (Profile 2)"))
    }

    @Test
    func `safari records reads selected website data store`() throws {
        let home = try Self.makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        try Self.writeCookieFile(
            home.appendingPathComponent("Library/Cookies/Cookies.binarycookies"),
            domain: "legacy.example",
            name: "session",
            value: "legacy")
        try Self.writeCookieFile(
            home.appendingPathComponent(
                "Library/WebKit/WebsiteDataStore/Profile 2/WebsiteData/Cookies/Cookies.binarycookies"),
            domain: "profile.example",
            name: "session",
            value: "profile")

        let client = BrowserCookieClient(configuration: .init(homeDirectories: [home]))
        let store = try #require(client.stores(for: .safari).first { $0.label == "Safari (Profile 2)" })
        let records = try client.records(matching: .init(domains: ["profile.example"]), in: store)

        #expect(records.map(\.domain) == ["profile.example"])
        #expect(records.map(\.value) == ["profile"])
    }

    @Test
    func `safari rejects truncated cookie files`() throws {
        let home = try Self.makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let cookieURL = home.appendingPathComponent("Library/Cookies/Cookies.binarycookies")
        try FileManager.default.createDirectory(
            at: cookieURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let validData = Self.binaryCookieData(domain: "synthetic.example", name: "session", value: "synthetic")
        try validData.write(to: cookieURL)

        let client = BrowserCookieClient(configuration: .init(homeDirectories: [home]))
        let store = try #require(client.stores(for: .safari).first)
        for length in 0..<validData.count {
            try Data(validData.prefix(length)).write(to: cookieURL)
            #expect(throws: BrowserCookieError.self) {
                try client.records(matching: .init(), in: store)
            }
        }

        try (Data("cook".utf8) + Data([0xFF, 0xFF, 0xFF, 0xFF])).write(to: cookieURL)
        #expect(throws: BrowserCookieError.self) {
            try client.records(matching: .init(), in: store)
        }
    }

    private static func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SweetCookieKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writeGeckoProfile(home: URL, directory: String, remotingName: String?) throws {
        let profile = home.appendingPathComponent("Library/Application Support/Firefox/Profiles/\(directory)")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data().write(to: profile.appendingPathComponent("cookies.sqlite"))
        guard let remotingName else { return }

        let application = home.appendingPathComponent("Applications/\(remotingName)/Contents/Resources")
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
        try "[App]\nRemotingName=\(remotingName)\n".write(
            to: application.appendingPathComponent("application.ini"),
            atomically: true,
            encoding: .utf8)
        try "[Compatibility]\nLastAppDir=\(application.appendingPathComponent("browser").path)\n".write(
            to: profile.appendingPathComponent("compatibility.ini"),
            atomically: true,
            encoding: .utf8)
    }

    private static func writeCookieFile(_ url: URL, domain: String, name: String, value: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try self.binaryCookieData(domain: domain, name: name, value: value).write(to: url)
    }

    private static func binaryCookieData(domain: String, name: String, value: String) -> Data {
        var record = Data()
        let headerSize = 56
        let path = "/"
        let domainOffset = headerSize
        let nameOffset = domainOffset + domain.utf8.count + 1
        let pathOffset = nameOffset + name.utf8.count + 1
        let valueOffset = pathOffset + path.utf8.count + 1
        let recordSize = valueOffset + value.utf8.count + 1

        record.appendUInt32LE(UInt32(recordSize))
        record.appendUInt32LE(0)
        record.appendUInt32LE(0x5)
        record.appendUInt32LE(0)
        record.appendUInt32LE(UInt32(domainOffset))
        record.appendUInt32LE(UInt32(nameOffset))
        record.appendUInt32LE(UInt32(pathOffset))
        record.appendUInt32LE(UInt32(valueOffset))
        record.appendUInt32LE(0)
        record.appendUInt32LE(0)
        record.appendDoubleLE(0)
        record.appendDoubleLE(0)
        record.appendCString(domain)
        record.appendCString(name)
        record.appendCString(path)
        record.appendCString(value)

        var page = Data()
        page.appendUInt32LE(0)
        page.appendUInt32LE(1)
        page.appendUInt32LE(12)
        page.append(record)

        var file = Data("cook".utf8)
        file.appendUInt32BE(1)
        file.appendUInt32BE(UInt32(page.count))
        file.append(page)
        return file
    }
}

extension Data {
    fileprivate mutating func appendUInt32BE(_ value: UInt32) {
        self.append(contentsOf: [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ])
    }

    fileprivate mutating func appendUInt32LE(_ value: UInt32) {
        self.append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }

    fileprivate mutating func appendDoubleLE(_ value: Double) {
        let raw = value.bitPattern
        self.append(contentsOf: (0..<8).map { shift in
            UInt8((raw >> UInt64(shift * 8)) & 0xFF)
        })
    }

    fileprivate mutating func appendCString(_ value: String) {
        self.append(contentsOf: value.utf8)
        self.append(0)
    }
}

#endif
