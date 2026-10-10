import Foundation
import Testing
@testable import SweetCookieKit

#if os(macOS)
struct ChromiumStrictCurrentValueTests {
    @Test
    func `physical system temporary directory remains readable without standardization`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try self.manifest(fixture)
        try fixture.write("000004.log", data: fixture.batch(sequence: 1, values: ["current"]))
        #expect(ChromiumAnchoredFiles(directory: fixture.directory) != nil)
        #expect(self.read(fixture) == Data([1]) + Data("current".utf8))
    }

    @Test(arguments: [false, true])
    func `latest session and logout`(snappy: Bool) throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try self.manifest(fixture, tables: [3])
        try fixture.write("000003.ldb", data: fixture.table(sequence: 30, values: ["old"], snappy: snappy))
        try fixture.write("000004.log", data: fixture.batch(sequence: 31, values: [nil, "new"]))
        #expect(self.read(fixture) == Data([1]) + Data("new".utf8))
        try fixture.write("000004.log", data: fixture.batch(sequence: 31, values: [nil, "new", nil]))
        #expect(self.read(fixture) == nil)
    }

    @Test(arguments: [
        "no-current",
        "bad-current",
        "missing-table",
        "missing-log",
        "truncated-log",
        "log-crc",
        "manifest-crc",
        "table-crc",
        "conflicting-sequence",
    ])
    func `incomplete or ambiguous snapshots fail closed`(kind: String) throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try self.manifest(fixture, tables: [3])
        try fixture.write("000003.ldb", data: fixture.table(sequence: 30, values: ["old"]))
        try fixture.write("000004.log", data: fixture.batch(sequence: 31, values: ["new"]))
        switch kind {
        case "no-current": try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("CURRENT"))
        case "bad-current": try fixture.write("CURRENT", data: Data("MANIFEST-missing\n".utf8))
        case "missing-table": try FileManager.default
            .removeItem(at: fixture.directory.appendingPathComponent("000003.ldb"))
        case "missing-log": try FileManager.default
            .removeItem(at: fixture.directory.appendingPathComponent("000004.log"))
        case "truncated-log":
            try fixture.write("000004.log", data: fixture.batch(sequence: 31, values: ["new"]) + Data([99]))
        case "conflicting-sequence":
            try fixture.write("000005.log", data: fixture.batch(sequence: 31, values: [nil]))
        default:
            let name = kind == "manifest-crc" ? "MANIFEST-000001" : kind == "log-crc" ? "000004.log" : "000003.ldb"
            var data = try Data(contentsOf: fixture.directory.appendingPathComponent(name))
            data[0] ^= 1
            try fixture.write(name, data: data)
        }
        #expect(self.read(fixture) == nil)
        if kind == "no-current" || kind == "truncated-log" {
            // Existing best-effort API returns data for these fixtures; it is not the new credential contract.
            #expect(!fixture.values().isEmpty)
        }
    }

    @Test func `missing previous log cannot revive old table value`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write("CURRENT", data: Data("MANIFEST-000001\n".utf8))
        try fixture.write("MANIFEST-000001", data: fixture.version(log: 7, previousLog: 6, added: [3]))
        try fixture.write("000003.ldb", data: fixture.table(sequence: 30, values: ["old"]))
        try fixture.write("000007.log", data: Data())
        #expect(self.read(fixture) == nil)
        try fixture.write("000006.log", data: fixture.batch(sequence: 31, values: [nil]))
        #expect(self.read(fixture) == nil)
        try fixture.write("000007.log", data: fixture.batch(sequence: 32, values: ["new"]))
        #expect(self.read(fixture) == Data([1]) + Data("new".utf8))
    }

    @Test(arguments: ["http://example.com", "https://example.com:443", "https://sub.example.com"])
    func `exact raw origin does not use host matching`(origin: String) throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try self.manifest(fixture)
        try fixture.write("000004.log", data: fixture.batch(sequence: 1, values: ["synthetic"]))
        let wrongKey = Data("_\(origin)\0".utf8) + Data([1]) + Data("access_token".utf8)
        #expect(ChromiumLocalStorageReader.readCurrentValue(forRawKey: wrongKey, in: fixture.directory) == nil)
        #expect(self.read(fixture) != nil)
        if origin == "http://example.com" {
            #expect(!ChromiumLocalStorageReader.readEntries(for: origin, in: fixture.directory).isEmpty)
        }
    }

    @Test func `changes during read fail closed`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try self.manifest(fixture)
        try fixture.write("000004.log", data: fixture.batch(sequence: 1, values: ["old"]))
        let observer: @Sendable (ChromiumLocalStorageReader.StrictReadEvent) -> Void = { event in
            if case .didRead("000004.log") = event {
                do { try fixture.write("000005.log", data: fixture.batch(sequence: 2, values: [nil])) } catch {
                    Issue.record("Could not change synthetic WAL: \(error)")
                }
            }
        }
        ChromiumLocalStorageReader.$strictReadObserver.withValue(observer) {
            #expect(self.read(fixture) == nil)
        }
    }

    @Test(arguments: ["CURRENT", "MANIFEST-000001", "000004.log"])
    func `symlink replacement never reads the replacement`(name: String) throws {
        let fixture = try SyntheticLevelDB()
        let other = try SyntheticLevelDB()
        defer { fixture.remove(); other.remove() }
        try self.manifest(fixture)
        try fixture.write("000004.log", data: fixture.batch(sequence: 1, values: ["old"]))
        try other.write(name, data: Data("outside must not be read".utf8))
        let observer: @Sendable (ChromiumLocalStorageReader.StrictReadEvent) -> Void = { event in
            switch event {
            case let .willOpen(opened) where opened == name:
                do {
                    let url = fixture.directory.appendingPathComponent(name)
                    try FileManager.default.removeItem(at: url)
                    try FileManager.default.createSymbolicLink(
                        at: url, withDestinationURL: other.directory.appendingPathComponent(name))
                } catch { Issue.record("Could not replace synthetic file: \(error)") }
            case let .didRead(opened) where opened == name:
                Issue.record("A replaced symbolic link must never be read")
            default: break
            }
        }
        ChromiumLocalStorageReader.$strictReadObserver.withValue(observer) {
            #expect(self.read(fixture) == nil)
        }
    }

    @Test(arguments: ["CURRENT", "MANIFEST-000001", "000004.log"])
    func `in place mutation after read fails closed`(name: String) throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try self.manifest(fixture)
        try fixture.write("000004.log", data: fixture.batch(sequence: 1, values: ["old"]))
        let observer: @Sendable (ChromiumLocalStorageReader.StrictReadEvent) -> Void = { event in
            if case let .didRead(opened) = event, opened == name {
                do { try fixture.write(name, data: Data("changed".utf8)) } catch {
                    Issue.record("Could not mutate synthetic file: \(error)")
                }
            }
        }
        ChromiumLocalStorageReader.$strictReadObserver.withValue(observer) {
            #expect(self.read(fixture) == nil)
        }
    }

    @Test(arguments: [false, true])
    func `directory replacement cannot redirect descriptor reads`(symlink: Bool) throws {
        let fixture = try SyntheticLevelDB()
        let other = try SyntheticLevelDB()
        let moved = fixture.directory.appendingPathExtension("moved")
        defer { fixture.remove(); other.remove(); try? FileManager.default.removeItem(at: moved) }
        try self.manifest(fixture)
        let original = fixture.batch(sequence: 1, values: ["original"])
        try fixture.write("000004.log", data: original)
        try other.write("000004.log", data: Data("outside".utf8))
        let files = try #require(ChromiumAnchoredFiles(directory: fixture.directory))
        try FileManager.default.moveItem(at: fixture.directory, to: moved)
        if symlink {
            try FileManager.default.createSymbolicLink(at: fixture.directory, withDestinationURL: other.directory)
        } else {
            try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
            try fixture.write("000004.log", data: Data("replacement".utf8))
        }
        #expect(try files.read(fixture.directory.appendingPathComponent("000004.log")) == original)
        #expect(!files.unchanged())
    }

    @Test func `replacing a parent directory does not redirect reads`() throws {
        let fixture = try SyntheticLevelDB()
        let moved = fixture.directory.appendingPathExtension("moved")
        defer { fixture.remove(); try? FileManager.default.removeItem(at: moved) }
        let nested = fixture.directory.appendingPathComponent("parent/leveldb")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: nested.appendingPathComponent("CURRENT"))
        let files = try #require(ChromiumAnchoredFiles(directory: nested))
        try FileManager.default.moveItem(at: fixture.directory, to: moved)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("replacement".utf8).write(to: nested.appendingPathComponent("CURRENT"))
        #expect(try files.read(nested.appendingPathComponent("CURRENT")) == Data("original".utf8))
        #expect(!files.unchanged())
    }

    @Test(arguments: ["directory", "log"])
    func `symlinks fail closed`(kind: String) throws {
        let fixture = try SyntheticLevelDB()
        let other = try SyntheticLevelDB()
        defer { fixture.remove(); other.remove() }
        try self.manifest(fixture)
        try fixture.write("000004.log", data: fixture.batch(sequence: 1, values: ["value"]))
        let link = other.directory.appendingPathComponent(kind == "directory" ? "linked" : "data")
        if kind == "directory" {
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.directory)
            #expect(ChromiumLocalStorageReader.readCurrentValue(forRawKey: fixture.key, in: link) == nil)
        } else {
            let log = fixture.directory.appendingPathComponent("000004.log")
            try FileManager.default.moveItem(at: log, to: link)
            try FileManager.default.createSymbolicLink(at: log, withDestinationURL: link)
            #expect(self.read(fixture) == nil)
        }
    }

    private func read(_ fixture: SyntheticLevelDB) -> Data? {
        ChromiumLocalStorageReader.readCurrentValue(forRawKey: fixture.key, in: fixture.directory)
    }

    private func manifest(_ fixture: SyntheticLevelDB, tables: [UInt64] = []) throws {
        try fixture.write("CURRENT", data: Data("MANIFEST-000001\n".utf8))
        try fixture.write("MANIFEST-000001", data: fixture.version(log: 4, added: tables))
    }
}
#endif
