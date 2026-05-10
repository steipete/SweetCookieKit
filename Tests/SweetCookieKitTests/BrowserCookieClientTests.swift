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
    func `browser cookie import order labels`() {
        let order = Browser.defaultImportOrder
        #expect(order.first == .safari)
        #expect(order.contains(.chrome))
        #expect(order.contains(.dia))
        #expect(order.contains(.firefox))
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
                "Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Profile 1/WebsiteData/Cookies/Cookies.binarycookies"),
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

    private static func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SweetCookieKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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
