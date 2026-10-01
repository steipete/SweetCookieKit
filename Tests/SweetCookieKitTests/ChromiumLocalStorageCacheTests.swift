import Darwin
import Foundation
import Testing
@testable import SweetCookieKit

struct ChromiumLocalStorageCacheTests {
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
            #expect(fixture.read().count == 2)
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
                    group.addTask { fixture.read().count }
                }
                for await count in group {
                    #expect(count == 2)
                }
            }
            #expect(fixture.io.reads == 1)
            await withTaskGroup(of: Int.self) { group in
                for index in 0..<32 {
                    group.addTask {
                        if index.isMultiple(of: 4) {
                            ChromiumLocalStorageReader.invalidateCache()
                        }
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
        self.cache = LevelDBReadCache(clock: { io.now }, readData: { url in
            io.didRead()
            return try Data(contentsOf: url)
        })
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

    func remove() {
        try? FileManager.default.removeItem(at: self.directory)
    }
}

private final class TestIO: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var time: TimeInterval = 0
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
}
