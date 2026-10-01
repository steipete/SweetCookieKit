import Foundation
import Testing
@testable import SweetCookieKit

#if os(macOS)

struct ChromiumLevelDBTableTests {
    @Test
    func `reads entries from snappy table`() throws {
        let levelDBURL = try self.makeLevelDBDirectory()
        let key = self.localStorageKey(storageKey: "https://example.com", key: "access_token")
        let value = self.localStorageValue("token-123")
        let internalKey = self.levelDBInternalKey(userKey: key, valueType: 1, sequence: 1)

        try self.writeTable(
            entries: [(key: internalKey, value: value)],
            to: levelDBURL,
            useSnappy: true)

        let entries = ChromiumLocalStorageReader.readEntries(
            for: "https://example.com",
            in: levelDBURL)

        #expect(entries.count == 1)
        #expect(entries.first?.key == "access_token")
        #expect(entries.first?.value == "token-123")
    }

    @Test
    func `reads entries from raw table`() throws {
        let levelDBURL = try self.makeLevelDBDirectory()
        let key = self.localStorageKey(storageKey: "https://example.com", key: "session")
        let value = self.localStorageValue("value-raw")
        let internalKey = self.levelDBInternalKey(userKey: key, valueType: 1, sequence: 1)

        try self.writeTable(
            entries: [(key: internalKey, value: value)],
            to: levelDBURL,
            useSnappy: false)

        let entries = ChromiumLocalStorageReader.readEntries(
            for: "https://example.com",
            in: levelDBURL)

        #expect(entries.count == 1)
        #expect(entries.first?.key == "session")
        #expect(entries.first?.value == "value-raw")
    }

    @Test
    func `ignores out of range block handles`() throws {
        let levelDBURL = try self.makeLevelDBDirectory()
        var footer = Data([0, 0])
        footer.append(self.varint64(UInt64.max))
        footer.append(self.varint64(UInt64.max))
        footer.append(contentsOf: Array(repeating: 0, count: 40 - footer.count))
        footer.append(contentsOf: Array(repeating: 0, count: 8))
        try footer.write(to: levelDBURL.appendingPathComponent("000005.ldb"))

        let entries = ChromiumLocalStorageReader.readEntries(
            for: "https://example.com",
            in: levelDBURL)

        #expect(entries.isEmpty)
    }
}

extension ChromiumLevelDBTableTests {
    private func makeLevelDBDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
        let url = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func localStorageKey(storageKey: String, key: String) -> Data {
        var data = Data([0x5F])
        data.append(contentsOf: storageKey.utf8)
        data.append(0x00)
        data.append(contentsOf: key.utf8)
        return data
    }

    private func localStorageValue(_ value: String) -> Data {
        var data = Data([0x01])
        data.append(contentsOf: value.utf8)
        return data
    }

    func levelDBInternalKey(userKey: Data, valueType: UInt8, sequence: UInt64) -> Data {
        var data = Data(userKey)
        let tag = (sequence << 8) | UInt64(valueType)
        data.append(contentsOf: self.littleEndianBytes(tag))
        return data
    }

    func writeTable(
        entries: [(key: Data, value: Data)],
        to url: URL,
        useSnappy: Bool) throws
    {
        let dataBlockRaw = self.buildDataBlock(entries: entries)
        let dataBlockPayload = useSnappy ? self.snappyLiteralBlock(dataBlockRaw) : dataBlockRaw
        let dataCompressionType: UInt8 = useSnappy ? 1 : 0

        var table = Data()
        let dataBlockOffset = table.count
        table.append(dataBlockPayload)
        table.append(dataCompressionType)
        table.append(contentsOf: [0, 0, 0, 0])

        let handleValue = self.blockHandleData(offset: dataBlockOffset, size: dataBlockPayload.count)
        let indexKey = Data("index".utf8)
        let indexBlockRaw = self.buildDataBlock(entries: [(key: indexKey, value: handleValue)])
        let indexBlockOffset = table.count
        table.append(indexBlockRaw)
        table.append(0)
        table.append(contentsOf: [0, 0, 0, 0])

        table.append(self.footerData(indexOffset: indexBlockOffset, indexSize: indexBlockRaw.count))

        try table.write(to: url.appendingPathComponent("000005.ldb"))
    }

    private func buildDataBlock(entries: [(key: Data, value: Data)]) -> Data {
        var data = Data()
        for entry in entries {
            data.append(self.varint32(0))
            data.append(self.varint32(entry.key.count))
            data.append(self.varint32(entry.value.count))
            data.append(entry.key)
            data.append(entry.value)
        }
        data.append(contentsOf: self.littleEndianBytes(UInt32(0)))
        data.append(contentsOf: self.littleEndianBytes(UInt32(1)))
        return data
    }

    private func footerData(indexOffset: Int, indexSize: Int) -> Data {
        var data = Data()
        data.append(self.blockHandleData(offset: 0, size: 0))
        data.append(self.blockHandleData(offset: indexOffset, size: indexSize))
        if data.count < 40 {
            data.append(contentsOf: Array(repeating: 0, count: 40 - data.count))
        }
        data.append(contentsOf: Array(repeating: 0, count: 8))
        return data
    }

    private func blockHandleData(offset: Int, size: Int) -> Data {
        var data = Data()
        data.append(self.varint64(offset))
        data.append(self.varint64(size))
        return data
    }

    private func snappyLiteralBlock(_ data: Data) -> Data {
        var output = Data()
        output.append(self.varint32(data.count))
        output.append(contentsOf: self.snappyLiteralTagBytes(length: data.count))
        output.append(data)
        return output
    }

    private func snappyLiteralTagBytes(length: Int) -> [UInt8] {
        guard length > 0 else { return [0] }
        if length < 60 {
            return [UInt8((length - 1) << 2)]
        }
        var remaining = length - 1
        var bytes: [UInt8] = []
        while remaining > 0 {
            bytes.append(UInt8(remaining & 0xFF))
            remaining >>= 8
        }
        let tag = UInt8((59 + bytes.count) << 2)
        return [tag] + bytes
    }

    private func varint32(_ value: Int) -> Data {
        var result = Data()
        var remaining = UInt32(value)
        while true {
            if remaining & ~0x7F == 0 {
                result.append(UInt8(remaining))
                break
            }
            result.append(UInt8((remaining & 0x7F) | 0x80))
            remaining >>= 7
        }
        return result
    }

    private func varint64(_ value: Int) -> Data {
        self.varint64(UInt64(value))
    }

    private func varint64(_ value: UInt64) -> Data {
        var result = Data()
        var remaining = value
        while true {
            if remaining & ~0x7F == 0 {
                result.append(UInt8(remaining))
                break
            }
            result.append(UInt8((remaining & 0x7F) | 0x80))
            remaining >>= 7
        }
        return result
    }

    private func littleEndianBytes(_ value: some FixedWidthInteger) -> [UInt8] {
        let littleEndian = value.littleEndian
        return withUnsafeBytes(of: littleEndian) { Array($0) }
    }
}

#endif
