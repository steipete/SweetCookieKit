import Foundation
import Testing
@testable import SweetCookieKit

#if os(macOS)

struct ChromiumLevelDBCurrentRecordTests {
    @Test
    func `plain value`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write("000003.log", data: fixture.batch(sequence: 1, values: ["synthetic-current-session"]))
        #expect(fixture.values() == ["synthetic-current-session"])
    }

    @Test
    func `sequence beats file modification time`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write(
            "000003.log",
            data: fixture.batch(sequence: 1, values: ["synthetic-replaced-session"]),
            time: 200)
        try fixture.write(
            "000004.log",
            data: fixture.batch(sequence: 2, values: ["synthetic-current-session"]),
            time: 100)
        #expect(fixture.values() == ["synthetic-current-session"])
    }

    @Test
    func `sign out deletes value`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write(
            "000003.log",
            data:
            fixture.batch(sequence: 1, values: ["synthetic-session"]) + fixture.batch(sequence: 2, values: [nil]))
        #expect(fixture.values().isEmpty)
    }

    @Test
    func `sign in after deletion restores value`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write(
            "000003.log",
            data:
            fixture.batch(sequence: 1, values: [nil]) + fixture.batch(
                sequence: 2,
                values: ["synthetic-current-session"]))
        #expect(fixture.values() == ["synthetic-current-session"])
    }

    @Test(arguments: [false, true])
    func `each write batch operation advances sequence`(deleted: Bool) throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        let values: [String?] = deleted ? [nil, "synthetic-session", nil] : ["old", nil, "synthetic-session"]
        try fixture.write("000003.log", data: fixture.batch(sequence: 100, values: values))
        try fixture.write("000004.log", data: fixture.batch(sequence: 101, values: ["intermediate"]), time: 200)
        #expect(fixture.values() == (deleted ? [] : ["synthetic-session"]))
    }

    @Test
    func `batch sequence beats physical record order`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write(
            "000003.log",
            data:
            fixture.batch(sequence: 1 << 40, values: ["new"]) + fixture.batch(sequence: 1, values: ["old"]))
        #expect(fixture.values() == ["new"])
    }

    @Test(arguments: [false, true], [false, true])
    func `table internal keys resolve values and tombstones`(snappy: Bool, deleted: Bool) throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        let values: [String?] = deleted ? ["old", nil] : [nil, "new"]
        try fixture.write("000005.ldb", data: fixture.table(sequence: 1 << 40, values: values, snappy: snappy))
        #expect(fixture.values() == (deleted ? [] : ["new"]))
    }

    @Test(arguments: [false, true], [false, true])
    func `compacted table and stale orphan lose to newer log`(snappy: Bool, manifest: Bool) throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write("000005.ldb", data: fixture.table(sequence: 10, values: ["compacted"]), time: 300)
        try fixture.write("000002.sst", data: fixture.table(sequence: 1, values: ["stale"], snappy: snappy), time: 400)
        try fixture.write("000006.log", data: fixture.batch(sequence: 11, values: ["synthetic-current-session"]))
        if manifest {
            try fixture.write("MANIFEST-000001", data: fixture.version(log: 6, added: [5]))
            try fixture.write("CURRENT", data: Data("MANIFEST-000001\n".utf8))
        }
        #expect(fixture.values() == ["synthetic-current-session"])
        #expect(ChromiumLevelDBReader.readTextEntries(in: fixture.directory)
            .map(\.value) == ["synthetic-current-session"])
        #expect(ChromiumLevelDBReader.readTokenCandidates(in: fixture.directory, minimumLength: 15)
            == ["synthetic-current-session"])
    }

    @Test(arguments: [false, true])
    func `newer table sequence beats an older log value or deletion`(deleted: Bool) throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write("000005.sst", data: fixture.table(sequence: 20, values: [deleted ? nil : "new"]))
        try fixture.write("000003.log", data: fixture.batch(sequence: 1, values: [deleted ? "old" : nil]), time: 200)
        #expect(fixture.values() == (deleted ? [] : ["new"]))
    }

    @Test
    func `current manifest excludes deleted and orphan tables and obsolete logs`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write("000005.sst", data: fixture.table(sequence: 10, values: ["live"], snappy: true))
        try fixture.write("000004.ldb", data: fixture.table(sequence: 30, values: ["deleted-table"]), time: 300)
        try fixture.write("000099.ldb", data: fixture.table(sequence: 90, values: ["orphan"]), time: 400)
        try fixture.write("000003.log", data: fixture.batch(sequence: 100, values: ["obsolete-log"]), time: 500)
        let first = fixture.version(log: 6, added: [4, 5])
        let second = fixture.record(Data([6, 0, 4]))
        try fixture.write("MANIFEST-000001", data: first + second)
        try fixture.write("MANIFEST-000002", data: fixture.version(log: 3, added: [99]), time: 600)
        try fixture.write("CURRENT", data: Data("MANIFEST-000001\n".utf8))
        #expect(fixture.values() == ["live"])
        // CURRENT replacement must invalidate both the raw memo and origin results.
        try fixture.write("CURRENT", data: Data("MANIFEST-000002\n".utf8))
        #expect(fixture.values() == ["obsolete-log"])
    }

    @Test
    func `manifest includes previous current and newer recovery logs`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write("MANIFEST-000001", data: fixture.version(log: 6, previousLog: 4))
        try fixture.write("CURRENT", data: Data("MANIFEST-000001\n".utf8))
        try fixture.write("000003.log", data: fixture.batch(sequence: 100, values: ["obsolete"]))
        try fixture.write("000004.log", data: fixture.batch(sequence: 10, values: ["previous"]))
        #expect(fixture.values() == ["previous"])
        try fixture.write("000006.log", data: fixture.batch(sequence: 11, values: ["current"]))
        #expect(fixture.values() == ["current"])
        try fixture.write("000007.log", data: fixture.batch(sequence: 12, values: ["recovered"]))
        #expect(fixture.values() == ["recovered"])
    }

    @Test
    func `fragmented manifest replays later edits and rejects a truncated tail`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write("000005.ldb", data: fixture.table(sequence: 10, values: ["live"]))
        var edit = Data(fixture.version(log: 6).dropFirst(7))
        edit += Data([5, 0]) + fixture.slice(Data(repeating: 65, count: 33000))
        let split = ChromiumLocalStorageReader.blockSize - 7
        var manifest = fixture.record(Data(edit.prefix(split)), type: 2)
        manifest += fixture.record(Data(edit.dropFirst(split)), type: 4)
        manifest += fixture.version(log: 6, added: [5])
        try fixture.write("MANIFEST-000001", data: manifest)
        try fixture.write("CURRENT", data: Data("MANIFEST-000001\n".utf8))
        #expect(fixture.values() == ["live"])
        manifest += fixture.record(Data([6, 0, 5])).dropLast()
        try fixture.write("MANIFEST-000001", data: manifest)
        #expect(fixture.values().isEmpty)
    }

    @Test
    func `deleted current value is absent from every reader`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write("000005.ldb", data: fixture.table(sequence: 1, values: ["synthetic-old-session"]))
        try fixture.write("000006.log", data: fixture.batch(sequence: 2, values: [nil]))
        #expect(fixture.values().isEmpty)
        #expect(ChromiumLevelDBReader.readTextEntries(in: fixture.directory).isEmpty)
        #expect(ChromiumLevelDBReader.readTokenCandidates(in: fixture.directory, minimumLength: 5).isEmpty)
    }

    @Test(arguments: ["CURRENT", "MANIFEST-000001"])
    func `malformed manifest metadata does not scan orphan files`(name: String) throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write("000003.log", data: fixture.batch(sequence: 1, values: ["orphan"]))
        try fixture.write("MANIFEST-000001", data: fixture.version(log: 4))
        try fixture.write("CURRENT", data: Data("MANIFEST-000001\n".utf8))
        try fixture.write(name, data: Data([0xFF]))
        #expect(fixture.values().isEmpty)
    }

    @Test
    func `truncated tables and logs retain a complete older record without crashing`() throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write("000003.log", data: fixture.batch(sequence: 1, values: ["intact"]))
        let log = fixture.batch(sequence: 2, values: [nil, "incomplete"])
        for length in 1..<log.count {
            try fixture.write("000004.log", data: Data(log.prefix(length)))
            #expect(fixture.values() == ["intact"])
        }
        let table = fixture.table(sequence: 3, values: ["incomplete"], snappy: true)
        for length in 1..<table.count {
            try fixture.write("000005.sst", data: Data(table.prefix(length)))
            #expect(fixture.values() == ["intact"])
        }
    }

    @Test(arguments: ["count", "sequence", "trailing", "varint"])
    func `malformed batches cannot replace a valid value`(kind: String) throws {
        let fixture = try SyntheticLevelDB()
        defer { fixture.remove() }
        try fixture.write("000003.log", data: fixture.batch(sequence: 1, values: ["intact"]))
        var batch = Data(fixture.batch(sequence: 2, values: ["invalid"]).dropFirst(7))
        switch kind {
        case "count": batch[8] = 2
        case "sequence": batch.replaceSubrange(0..<8, with: fixture.littleEndian(UInt64.max))
        case "trailing": batch.append(0)
        default: batch.replaceSubrange(13..<14, with: Data([0xFF, 0xFF, 0xFF, 0xFF, 0x7F]))
        }
        try fixture.write("000004.log", data: fixture.record(batch))
        #expect(fixture.values() == ["intact"])
    }
}

/// Every fixture contains generated, synthetic data only.
struct SyntheticLevelDB {
    let directory: URL
    let key = Data("_https://example.com\0".utf8) + Data([1]) + Data("access_token".utf8)

    init() throws {
        self.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: self.directory)
    }

    func values() -> [String] {
        ChromiumLocalStorageReader.readEntries(for: "https://example.com", in: self.directory).map(\.value)
    }

    func write(_ name: String, data: Data, time: TimeInterval = 100) throws {
        let url = self.directory.appendingPathComponent(name)
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: time)],
            ofItemAtPath: url.path)
    }

    func batch(sequence: UInt64, values: [String?]) -> Data {
        var data = self.littleEndian(sequence) + self.littleEndian(UInt32(values.count))
        for value in values {
            data.append(value == nil ? 0 : 1)
            data.append(self.slice(self.key))
            if let value {
                data.append(self.slice(Data([1]) + Data(value.utf8)))
            }
        }
        return self.record(data)
    }

    func record(_ data: Data, type: UInt8 = 1) -> Data {
        self.checksum(Data([type]) + data) + self.littleEndian(UInt16(data.count)) + Data([type]) + data
    }

    func checksum(_ data: Data) -> Data {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 == 1 ? 0x82F6_3B78 : 0)
            }
        }
        crc = ~crc
        return self.littleEndian(((crc >> 15) | (crc << 17)) &+ 0xA282_EAD8)
    }

    func slice(_ data: Data) -> Data {
        self.varint(UInt64(data.count)) + data
    }

    func varint(_ value: UInt64) -> Data {
        var remaining = value
        var result = Data()
        while remaining >= 128 {
            result.append(UInt8(remaining & 127) | 128)
            remaining >>= 7
        }
        result.append(UInt8(remaining))
        return result
    }

    func littleEndian(_ value: some FixedWidthInteger) -> Data {
        var value = value.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    func version(log: UInt64, previousLog: UInt64 = 0, added: [UInt64] = []) -> Data {
        var edit = Data([1]) + self.slice(Data("leveldb.BytewiseComparator".utf8))
        edit += Data([2]) + self.varint(log) + Data([9]) + self.varint(previousLog)
        edit += Data([3, 110, 4, 100])
        let internalKey = self.key + self.littleEndian(UInt64(1))
        for number in added {
            edit += Data([7, 0]) + self.varint(number) + self.varint(100)
            edit += self.slice(internalKey) + self.slice(internalKey)
        }
        return self.record(edit)
    }

    func table(sequence: UInt64, values: [String?], snappy: Bool = false) -> Data {
        let entries = values.enumerated().reversed().map { index, value in
            let tag = ((sequence + UInt64(index)) << 8) | (value == nil ? 0 : 1)
            return (self.key + self.littleEndian(tag), value.map { Data([1]) + Data($0.utf8) } ?? Data())
        }
        let raw = self.block(entries)
        var payload = raw
        if snappy {
            let length = raw.count - 1
            let tag = length < 60 ? Data([UInt8(length << 2)]) : Data([240, UInt8(length)])
            payload = self.varint(UInt64(raw.count)) + tag + raw
        }
        let compression: UInt8 = snappy ? 1 : 0
        var table = payload + Data([compression]) + self.checksum(payload + Data([compression]))
        let metaOffset = table.count
        let meta = self.block([])
        table += meta + Data([0]) + self.checksum(meta + Data([0]))
        let indexOffset = table.count
        let index = self.block([(entries.last?.0 ?? self.key, Data([0]) + self.varint(UInt64(payload.count)))])
        table += index + Data([0]) + self.checksum(index + Data([0]))
        var footer = self.varint(UInt64(metaOffset)) + self.varint(UInt64(meta.count))
        footer += self.varint(UInt64(indexOffset)) + self.varint(UInt64(index.count))
        footer += Data(repeating: 0, count: 40 - footer.count)
        footer += self.littleEndian(UInt64(0xDB47_7524_8B80_FB57))
        return table + footer
    }

    private func block(_ entries: [(Data, Data)]) -> Data {
        var data = Data()
        for (key, value) in entries {
            data += Data([0]) + self.varint(UInt64(key.count)) + self.varint(UInt64(value.count)) + key + value
        }
        return data + self.littleEndian(UInt32(0)) + self.littleEndian(UInt32(1))
    }
}

#endif
