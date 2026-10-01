import Darwin
import Foundation
import Testing
@testable import SweetCookieKit

struct ChromiumLocalStorageCacheTests {
    @Test
    func `warm derived queries preserve results diagnostics and perform no decoding`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let helper = ChromiumLocalStorageReaderTests()
        try helper.writeLog(entries: ["synthetic-token", "secondary-token"].map {
            (helper.localStorageKey(storageKey: "https://example.com", key: $0), helper.localStorageValue($0), false)
        }, to: fixture.directory)
        try Data().write(to: fixture.directory.appendingPathComponent("000004.log"))
        ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            var coldLog: [String] = []
            let text = ChromiumLocalStorageReader.readTextEntries(in: fixture.directory) { coldLog.append($0) }
            let textWork = fixture.io.derivations
            #expect(textWork[.textDecode] == 4)
            var warmLog: [String] = []
            let warmText = ChromiumLevelDBReader.readTextEntries(in: fixture.directory) { warmLog.append($0) }
            #expect(text.map(\.key) == warmText.map(\.key))
            #expect(text.map(\.value) == warmText.map(\.value))
            #expect(coldLog == warmLog)
            #expect(fixture.io.derivations == textWork)

            coldLog.removeAll()
            warmLog.removeAll()
            let tokens = ChromiumLocalStorageReader.readTokenCandidates(
                in: fixture.directory, minimumLength: 10) { coldLog.append($0) }
            let tokenWork = fixture.io.derivations
            #expect(tokenWork[.tokenScan] == 4)
            #expect(tokens.contains("synthetic-token"))
            let warmTokens = ChromiumLevelDBReader.readTokenCandidates(
                in: fixture.directory, minimumLength: 10) { warmLog.append($0) }
            #expect(tokens == warmTokens)
            #expect(coldLog == warmLog)
            #expect(fixture.io.derivations == tokenWork)

            coldLog.removeAll()
            warmLog.removeAll()
            let origin = ChromiumLocalStorageReader.readEntries(
                for: "https://example.com", in: fixture.directory) { coldLog.append($0) }
            let originWork = fixture.io.derivations
            #expect(origin.count == 2)
            #expect(originWork[.localStorageKey] == 2)
            let warmOrigin = ChromiumLocalStorageReader.readEntries(
                for: "https://example.com/", in: fixture.directory) { warmLog.append($0) }
            #expect(origin.map(\.origin) == warmOrigin.map(\.origin))
            #expect(origin.map(\.key) == warmOrigin.map(\.key))
            #expect(origin.map(\.value) == warmOrigin.map(\.value))
            #expect(origin.map(\.rawValueLength) == warmOrigin.map(\.rawValueLength))
            #expect(coldLog == warmLog)
            #expect(fixture.io.derivations == originWork)
            #expect(fixture.io.reads == 2)
        }
    }

    @Test
    func `token lengths and origins have separate derived results`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            let short = ChromiumLocalStorageReader.readTokenCandidates(in: fixture.directory, minimumLength: 10)
            let long = ChromiumLocalStorageReader.readTokenCandidates(in: fixture.directory, minimumLength: 16)
            #expect(short.contains("synthetic-token"))
            #expect(long.isEmpty)
            #expect(fixture.io.derivations[.tokenScan] == 8)
            #expect(ChromiumLocalStorageReader.readTokenCandidates(in: fixture.directory, minimumLength: 10) == short)
            #expect(ChromiumLocalStorageReader.readTokenCandidates(in: fixture.directory, minimumLength: 16) == long)
            #expect(fixture.io.derivations[.tokenScan] == 8)
            #expect(fixture.io.derivations[.textDecode] == nil)
            let first = ChromiumLocalStorageReader.readEntries(for: "https://example.com", in: fixture.directory)
            let other = ChromiumLocalStorageReader.readEntries(for: "https://other.example", in: fixture.directory)
            let missing = ChromiumLocalStorageReader.readEntries(for: "https://missing.example", in: fixture.directory)
            #expect(first.first?.origin == "https://example.com")
            #expect(other.first?.origin == "https://other.example")
            #expect(missing.isEmpty)
            let work = fixture.io.derivations
            _ = ChromiumLocalStorageReader.readEntries(for: "https://example.com", in: fixture.directory)
            _ = ChromiumLocalStorageReader.readEntries(for: "https://other.example", in: fixture.directory)
            _ = ChromiumLocalStorageReader.readEntries(for: "https://missing.example", in: fixture.directory)
            #expect(fixture.io.derivations == work)
            #expect(fixture.io.reads == 1)
        }
    }

    @Test(arguments: ["snapshot", "expiry", "explicit", "lru"])
    func `raw memo invalidation drops every derived result`(reason: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            fixture.readAll()
            let work = fixture.io.derivations
            fixture.readAll()
            #expect(fixture.io.derivations == work)
            switch reason {
            case "snapshot":
                try fixture.populate()
            case "expiry":
                fixture.io.advance(by: 599)
                _ = ChromiumLocalStorageReader.readTokenCandidates(in: fixture.directory, minimumLength: 12)
                _ = ChromiumLocalStorageReader.readEntries(for: "https://missing.example", in: fixture.directory)
                fixture.io.advance(by: 1)
            case "explicit":
                ChromiumLocalStorageReader.invalidateCache()
            default:
                for _ in 0..<8 {
                    let other = try Fixture()
                    _ = other.read()
                    other.remove()
                }
            }
            let beforeReload = fixture.io.derivations
            fixture.readAll()
            for kind in [LevelDBReadCache.Derivation.textDecode, .tokenScan, .localStorageKey, .localStorageValue] {
                #expect(fixture.io.derivations[kind, default: 0] > beforeReload[kind, default: 0])
            }
            let afterReload = fixture.io.derivations
            fixture.readAll()
            #expect(fixture.io.derivations == afterReload)
        }
    }

    @Test
    func `origin variants preserve the exact Unicode spelling`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let composed = "https://caf\u{00E9}.example"
        let decomposed = "https://cafe\u{0301}.example"
        let helper = ChromiumLocalStorageReaderTests()
        try helper.writeLog(entries: [(
            helper.localStorageKey(storageKey: composed, key: "token"),
            helper.localStorageValue("synthetic-token"), false)], to: fixture.directory)
        ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            let first = ChromiumLocalStorageReader.readEntries(for: composed, in: fixture.directory)
            let second = ChromiumLocalStorageReader.readEntries(for: decomposed, in: fixture.directory)
            #expect(first.map { Array($0.origin.utf8) } == [Array(composed.utf8)])
            #expect(second.map { Array($0.origin.utf8) } == [Array(decomposed.utf8)])
            let work = fixture.io.derivations
            _ = ChromiumLocalStorageReader.readEntries(for: composed, in: fixture.directory)
            _ = ChromiumLocalStorageReader.readEntries(for: decomposed, in: fixture.directory)
            #expect(fixture.io.derivations == work)
        }
    }

    @Test
    func `parameter variants are bounded and retain recently used results`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            for length in 1...16 {
                _ = ChromiumLocalStorageReader.readTokenCandidates(in: fixture.directory, minimumLength: length)
                _ = ChromiumLocalStorageReader.readEntries(
                    for: "https://origin\(length).example",
                    in: fixture.directory)
            }
            for length in [1, 17, 1] {
                _ = ChromiumLocalStorageReader.readTokenCandidates(in: fixture.directory, minimumLength: length)
                _ = ChromiumLocalStorageReader.readEntries(
                    for: "https://origin\(length).example",
                    in: fixture.directory)
            }
            #expect(fixture.io.derivations[.tokenScan] == 17 * 4)
            #expect(fixture.io.derivations[.localStorageKey] == 17 * 2)
            _ = ChromiumLocalStorageReader.readTokenCandidates(in: fixture.directory, minimumLength: 2)
            _ = ChromiumLocalStorageReader.readEntries(for: "https://origin2.example", in: fixture.directory)
            #expect(fixture.io.derivations[.tokenScan] == 18 * 4)
            #expect(fixture.io.derivations[.localStorageKey] == 18 * 2)
            #expect(fixture.io.reads == 1)
        }
    }

    @Test
    func `public readers share raw entries and replay diagnostics`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data().write(to: fixture.directory.appendingPathComponent("000004.log"))
        ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            var firstLog: [String] = []
            let first = ChromiumLocalStorageReader.readTextEntries(in: fixture.directory) { firstLog.append($0) }
            #expect(fixture.io.reads == 2)
            var secondLog: [String] = []
            let second = ChromiumLevelDBReader.readTextEntries(in: fixture.directory) { secondLog.append($0) }
            #expect(first.map(\.key) == second.map(\.key))
            #expect(first.map(\.value) == second.map(\.value))
            #expect(firstLog == secondLog)
            #expect(firstLog == ["[chromium-storage] LevelDB log yielded no entries for 000004.log"])
            for origin in ["https://example.com", "https://other.example"] {
                let values = ChromiumLocalStorageReader.readEntries(for: origin, in: fixture.directory)
                #expect(values.count == 1)
                #expect(values.first?.value == "synthetic-token")
                #expect(values.first?.rawValueLength == 16)
            }
            #expect(ChromiumLevelDBReader.readTokenCandidates(in: fixture.directory, minimumLength: 10)
                .contains("synthetic-token"))
            let alias = URL(fileURLWithPath: fixture.directory.path + "/./")
            #expect(ChromiumLocalStorageReader.readTextEntries(in: alias).count == 2)
            #expect(fixture.io.reads == 2)
            // Diagnostics are delivered outside the cache lock, including on a hit.
            _ = ChromiumLocalStorageReader.readTextEntries(in: fixture.directory) { _ in
                ChromiumLocalStorageReader.invalidateCache()
            }
            #expect(fixture.read().count == 2)
            #expect(fixture.io.reads == 4)
        }
    }

    @Test
    func `append and same size replacement invalidate`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            let first = fixture.read()
            let data = try Data(contentsOf: fixture.log)
            let handle = try FileHandle(forWritingTo: fixture.log)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
            #expect(fixture.read().count == first.count * 2)
            #expect(fixture.io.reads == 2)
            let oldDate = try fixture.log.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate!
            try (data + data).write(to: fixture.log, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: fixture.log.path)
            #expect(fixture.read().count == first.count * 2)
            #expect(fixture.io.reads == 3)
            _ = fixture.read()
            #expect(fixture.io.reads == 3)
        }
    }

    @Test(arguments: ["CURRENT", "MANIFEST-000001", "000007.log", "000007.ldb", "000007.sst"])
    func `adding changing and removing files invalidate`(name: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            _ = fixture.read()
            let url = fixture.directory.appendingPathComponent(name)
            let table = ChromiumLevelDBTableTests()
            if name.hasSuffix("ldb") {
                try table.writeTable(entries: [], to: fixture.directory, useSnappy: false)
                try FileManager.default.moveItem(at: fixture.directory.appendingPathComponent("000005.ldb"), to: url)
            } else {
                try Data().write(to: url)
            }
            _ = fixture.read()
            let afterAdd = fixture.io.reads
            #expect(afterAdd > 1)
            _ = fixture.read()
            #expect(fixture.io.reads == afterAdd)
            var info = stat()
            #expect(stat(url.path, &info) == 0)
            // Change only one nanosecond, retaining the original second and size.
            let nanoseconds = (info.st_mtimespec.tv_nsec + 1) % 1_000_000_000
            var times = [info.st_atimespec, timespec(tv_sec: info.st_mtimespec.tv_sec, tv_nsec: nanoseconds)]
            #expect(utimensat(AT_FDCWD, url.path, &times, 0) == 0)
            _ = fixture.read()
            #expect(fixture.io.reads > afterAdd)
            let afterChange = fixture.io.reads
            try FileManager.default.removeItem(at: url)
            _ = fixture.read()
            #expect(fixture.io.reads == afterChange + 1)
        }
    }

    @Test
    func `unreadable files never memoize and recovery works`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            _ = fixture.read()
            #expect(chmod(fixture.log.path, 0) == 0)
            defer { _ = chmod(fixture.log.path, 0o600) }
            #expect(access(fixture.log.path, R_OK) != 0)
            #expect(fixture.read().isEmpty)
            #expect(fixture.read().isEmpty)
            #expect(fixture.io.reads == 3)
            #expect(chmod(fixture.log.path, 0o600) == 0)
            #expect(fixture.read().count == 2)
            _ = fixture.read()
            #expect(fixture.io.reads == 4)
        }
    }

    @Test
    func `read errors and concurrent file changes never memoize`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = LevelDBReadCache(readData: { url in
            let count = fixture.io.didRead()
            if count == 1 {
                throw CocoaError(.fileReadNoPermission)
            }
            let data = try Data(contentsOf: url)
            if count == 2 {
                try FileManager.default.removeItem(at: url)
            }
            return data
        })
        try ChromiumLocalStorageReader.$levelDBCache.withValue(cache) {
            #expect(fixture.read().isEmpty)
            #expect(fixture.read().count == 2)
            try fixture.populate()
            #expect(fixture.read().count == 2)
            #expect(fixture.io.reads == 3)
            _ = fixture.read()
            #expect(fixture.io.reads == 3)
        }
    }

    @Test(arguments: [Data([1]), Data([0, 0, 0, 0, 1, 0, 99, 1]), Data(repeating: 0, count: 12)])
    func `malformed logs never memoize`(suffix: Data) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try Data(contentsOf: fixture.log)
        var malformed = suffix
        if suffix.count == 12 {
            // A full write batch claims one missing operation.
            malformed[8] = 1
            malformed = Data([0, 0, 0, 0, 12, 0, 1]) + malformed
        }
        try (original + malformed).write(to: fixture.log)
        ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            #expect(fixture.read().count == 2)
            let firstWork = fixture.io.derivations
            #expect(fixture.read().count == 2)
            #expect(fixture.io.derivations[.textDecode, default: 0] > firstWork[.textDecode, default: 0])
            #expect(fixture.io.reads == 2)
        }
    }

    @Test(arguments: [false, true])
    func `tables memoize only after complete decoding`(snappy: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let table = ChromiumLevelDBTableTests()
        let key = table.levelDBInternalKey(userKey: Data("table-key".utf8), valueType: 1, sequence: 1)
        try table.writeTable(entries: [(key, Data("table-value".utf8))], to: fixture.directory, useSnappy: snappy)
        try ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            #expect(fixture.read().count == 3)
            #expect(fixture.read().count == 3)
            #expect(fixture.io.reads == 2)
            let url = fixture.directory.appendingPathComponent("000005.ldb")
            var data = try Data(contentsOf: url)
            // The data block starts at zero; corrupt its shared-key varint while preserving the index/footer.
            data[0] = 255
            try data.write(to: url)
            let first = fixture.read()
            let second = fixture.read()
            #expect(first.map(\.value) == second.map(\.value))
            #expect(fixture.io.reads == 6)
        }
    }

    @Test
    func `complete fragments memoize but unfinished fragments do not`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let batch = try Data(contentsOf: fixture.log).dropFirst(7)
        let split = batch.count / 2
        func record(_ payload: Data, type: UInt8) -> Data {
            Data([0, 0, 0, 0, UInt8(payload.count), 0, type]) + payload
        }
        let first = record(Data(batch.prefix(split)), type: 2)
        let last = record(Data(batch.dropFirst(split)), type: 4)
        try (first + last).write(to: fixture.log)
        try ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            #expect(fixture.read().count == 2)
            #expect(fixture.read().count == 2)
            #expect(fixture.io.reads == 1)
            // Best-effort decoding of an unterminated first fragment still returns its entries.
            try record(Data(batch), type: 2).write(to: fixture.log)
            #expect(fixture.read().count == 2)
            #expect(fixture.read().count == 2)
            #expect(fixture.io.reads == 3)
        }
    }

    @Test
    func `empty first fragment at block boundary memoizes`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var last = try Data(contentsOf: fixture.log)
        last[6] = 4
        try ChromiumLocalStorageReaderTests().writeLog(
            entries: [(Data("x".utf8), Data(repeating: 65, count: 32736), false)],
            to: fixture.directory)
        let prefix = try Data(contentsOf: fixture.log)
        #expect(prefix.count == ChromiumLocalStorageReader.blockSize - 7)
        try (prefix + Data([0, 0, 0, 0, 0, 0, 2]) + last).write(to: fixture.log)
        ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            #expect(fixture.read().count == 3)
            #expect(fixture.read().count == 3)
            #expect(fixture.io.reads == 1)
        }
    }

    @Test
    func `expiry is absolute and LRU evicts the least recently used directory`() throws {
        let fixtures = try (0..<9).map { _ in try Fixture() }
        defer { fixtures.forEach { $0.remove() } }
        let first = fixtures[0]
        ChromiumLocalStorageReader.$levelDBCache.withValue(first.cache) {
            for fixture in fixtures.prefix(8) {
                _ = fixture.read()
            }
            #expect(first.io.reads == 8)
            _ = first.read()
            _ = fixtures[8].read()
            _ = first.read()
            #expect(first.io.reads == 9)
            _ = fixtures[1].read()
            #expect(first.io.reads == 10)
            first.io.advance(by: 599)
            _ = first.read()
            #expect(first.io.reads == 10)
            first.io.advance(by: 1)
            _ = first.read()
            #expect(first.io.reads == 11)
            ChromiumLocalStorageReader.invalidateCache()
            _ = first.read()
            #expect(first.io.reads == 12)
        }
    }

    @Test
    func `concurrent readers and invalidation are safe`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        await ChromiumLocalStorageReader.$levelDBCache.withValue(fixture.cache) {
            await withTaskGroup(of: Int.self) { group in
                for _ in 0..<32 {
                    group.addTask {
                        fixture.readAll()
                        return fixture.read().count
                    }
                }
                for await count in group {
                    #expect(count == 2)
                }
            }
            #expect(fixture.io.reads == 1)
            let warmWork = fixture.io.derivations
            fixture.readAll()
            #expect(fixture.io.derivations == warmWork)
            await withTaskGroup(of: Int.self) { group in
                for index in 0..<32 {
                    group.addTask {
                        if index.isMultiple(of: 4) {
                            ChromiumLocalStorageReader.invalidateCache()
                        }
                        fixture.readAll()
                        return fixture.read().count
                    }
                }
                for await count in group {
                    #expect(count == 2)
                }
            }
        }
    }
}

private struct Fixture: Sendable {
    let directory: URL
    let io = TestIO()
    let cache: LevelDBReadCache
    var log: URL {
        self.directory.appendingPathComponent("000003.log")
    }

    init() throws {
        self.directory = try ChromiumLocalStorageReaderTests().makeLevelDBDirectory()
        let io = self.io
        self.cache = LevelDBReadCache(
            clock: { io.now },
            readData: { url in
                io.didRead()
                return try Data(contentsOf: url)
            },
            onDerivation: { io.didDerive($0) })
        try self.populate()
    }

    func populate() throws {
        let helper = ChromiumLocalStorageReaderTests()
        let entries = ["https://example.com", "https://other.example"].map {
            (helper.localStorageKey(storageKey: $0, key: "token"), helper.localStorageValue("synthetic-token"), false)
        }
        try helper.writeLog(entries: entries, to: self.directory)
    }

    func read() -> [ChromiumLevelDBTextEntry] {
        ChromiumLocalStorageReader.readTextEntries(in: self.directory)
    }

    func readAll() {
        _ = self.read()
        _ = ChromiumLocalStorageReader.readTokenCandidates(in: self.directory, minimumLength: 10)
        _ = ChromiumLocalStorageReader.readTokenCandidates(in: self.directory, minimumLength: 16)
        _ = ChromiumLocalStorageReader.readEntries(for: "https://example.com", in: self.directory)
    }

    func remove() {
        try? FileManager.default.removeItem(at: self.directory)
    }
}

private final class TestIO: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var time: TimeInterval = 0
    private var work: [LevelDBReadCache.Derivation: Int] = [:]
    var derivations: [LevelDBReadCache.Derivation: Int] {
        self.lock.withLock { self.work }
    }

    var reads: Int {
        self.lock.withLock { self.count }
    }

    var now: TimeInterval {
        self.lock.withLock { self.time }
    }

    @discardableResult
    func didRead() -> Int {
        self.lock.withLock {
            self.count += 1
            return self.count
        }
    }

    func advance(by interval: TimeInterval) {
        self.lock.withLock { self.time += interval }
    }

    func didDerive(_ kind: LevelDBReadCache.Derivation) {
        self.lock.withLock { self.work[kind, default: 0] += 1 }
    }
}
