import Foundation

#if os(macOS)

extension ChromiumLocalStorageReader {
    // MARK: - LevelDB traversal

    struct LevelDBEntry: Sendable {
        let key: Data
        let value: Data
        let isDeletion: Bool
        let sequence: UInt64
    }

    static func withLevelDBEntries<Value>(
        in levelDBURL: URL,
        logger: ((String) -> Void)? = nil,
        derive: ([LevelDBEntry], inout LevelDBReadCache.DerivedResults) -> Value) -> Value?
    {
        let cache = self.levelDBCache
        let result = cache.read(
            in: levelDBURL,
            load: { files, complete, log in
                self.decodeFiles(files, cache: cache, complete: &complete, logger: log)
            },
            derive: derive)
        result.diagnostics.forEach { logger?($0) }
        return result.value
    }

    private static func decodeFiles(
        _ entries: [URL],
        cache: LevelDBReadCache,
        complete: inout Bool,
        logger: (String) -> Void) -> [LevelDBEntry]
    {
        let files = self.liveLevelDBFiles(entries, cache: cache, complete: &complete, logger: logger)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var results: [LevelDBEntry] = []
        for file in files {
            let ext = file.pathExtension.lowercased()
            if ext == "log" {
                let logEntries = self.readLogEntries(from: file, cache: cache, complete: &complete)
                if logEntries.isEmpty {
                    logger("LevelDB log yielded no entries for \(file.lastPathComponent)")
                }
                results.append(contentsOf: logEntries)
            } else {
                let tableEntries = self.readTableEntries(from: file, cache: cache, complete: &complete, logger: logger)
                if tableEntries.isEmpty {
                    logger("LevelDB table yielded no entries for \(file.lastPathComponent)")
                }
                results.append(contentsOf: tableEntries)
            }
        }
        // Internal keys sort by descending sequence, then descending value type (value before deletion).
        results.sort {
            if $0.sequence != $1.sequence {
                return $0.sequence > $1.sequence
            }
            if $0.isDeletion != $1.isDeletion {
                return !$0.isDeletion
            }
            return $0.key.lexicographicallyPrecedes($1.key)
        }
        var seen = Set<Data>()
        return results.filter { seen.insert($0.key).inserted }
    }

    // MARK: - Log parsing

    private enum LogRecordType: UInt8 {
        case full = 1
        case first = 2
        case middle = 3
        case last = 4
    }

    private static func readLogEntries(
        from url: URL,
        cache: LevelDBReadCache,
        complete: inout Bool) -> [LevelDBEntry]
    {
        self.readLogRecords(from: url, cache: cache, complete: &complete).flatMap {
            self.decodeWriteBatch($0, complete: &complete)
        }
    }

    static func readLogRecords(
        from url: URL,
        cache: LevelDBReadCache,
        complete: inout Bool) -> [Data]
    {
        guard let data = try? cache.readData(url) else { complete = false; return [] }
        var records: [Data] = []
        var recordBuffer = Data()
        var fragmented = false
        var offset = 0

        while offset < data.count {
            let blockEnd = min(offset + self.blockSize, data.count)
            var blockOffset = offset
            while blockOffset + 7 <= blockEnd {
                let length = Int(self.readUInt16LE(data, at: blockOffset + 4))
                let type = data[blockOffset + 6]
                blockOffset += 7
                if length == 0 {
                    // LevelDB emits an empty FIRST when only a record header fits in this block.
                    if type == LogRecordType.first.rawValue {
                        if fragmented {
                            complete = false
                        }
                        fragmented = true
                        recordBuffer.removeAll(keepingCapacity: true)
                    } else if type != 0 {
                        complete = false
                    }
                    continue
                }
                guard blockOffset + length <= blockEnd else { complete = false; break }
                let chunk = data.subdata(in: blockOffset..<(blockOffset + length))
                blockOffset += length

                guard let recordType = LogRecordType(rawValue: type) else { complete = false; continue }
                switch recordType {
                case .full:
                    if fragmented {
                        complete = false
                    }
                    fragmented = false
                    recordBuffer.removeAll(keepingCapacity: true)
                    records.append(chunk)
                case .first:
                    if fragmented {
                        complete = false
                    }
                    fragmented = true
                    recordBuffer = chunk
                case .middle:
                    guard fragmented else { complete = false; continue }
                    recordBuffer.append(chunk)
                case .last:
                    guard fragmented else { complete = false; continue }
                    fragmented = false
                    recordBuffer.append(chunk)
                    records.append(recordBuffer)
                    recordBuffer.removeAll(keepingCapacity: true)
                }
            }
            if blockOffset < blockEnd, data[blockOffset..<blockEnd].contains(where: { $0 != 0 }) {
                complete = false
            }
            offset += self.blockSize
        }
        if fragmented {
            complete = false
        }
        if !recordBuffer.isEmpty {
            records.append(recordBuffer)
        }
        return records
    }

    private static func decodeWriteBatch(_ data: Data, complete: inout Bool) -> [LevelDBEntry] {
        guard data.count >= 12 else { complete = false; return [] }
        let sequence = self.readUInt64LE(data, at: 0)
        let count = Int(self.readUInt32LE(data, at: 8))
        let maximumSequence = UInt64.max >> 8
        guard sequence <= maximumSequence,
              UInt64(max(count - 1, 0)) <= maximumSequence - sequence,
              count <= (data.count - 12) / 2
        else { complete = false; return [] }
        var entries: [LevelDBEntry] = []
        var offset = 12
        for index in 0..<count {
            guard let tag = self.readUInt8(data, at: &offset),
                  let key = self.readLengthPrefixedSlice(data, at: &offset)
            else { complete = false; return [] }
            switch tag {
            case 0:
                entries.append(LevelDBEntry(
                    key: key, value: Data(), isDeletion: true, sequence: sequence + UInt64(index)))
            case 1:
                guard let value = self.readLengthPrefixedSlice(data, at: &offset)
                else { complete = false; return [] }
                entries.append(LevelDBEntry(
                    key: key, value: value, isDeletion: false, sequence: sequence + UInt64(index)))
            default:
                complete = false
                return []
            }
        }
        guard offset == data.count else { complete = false; return [] }
        return entries
    }

    // MARK: - Table parsing

    private struct BlockHandle: Sendable {
        let offset: Int
        let size: Int
    }

    private static func readTableEntries(
        from url: URL,
        cache: LevelDBReadCache,
        complete: inout Bool,
        logger: (String) -> Void) -> [LevelDBEntry]
    {
        guard let data = try? cache.readData(url) else { complete = false; return [] }
        guard data.count >= self.footerSize else { complete = false; return [] }

        let footerStart = data.count - self.footerSize
        let footerData = data.subdata(in: footerStart..<(data.count - 8))
        var reader = ByteReader(footerData)
        guard self.readBlockHandle(&reader) != nil,
              let indexHandle = self.readBlockHandle(&reader)
        else { complete = false; return [] }

        guard let indexBlock = self.readBlock(data: data, handle: indexHandle, logger: logger)
        else { complete = false; return [] }
        let indexEntries = self.parseDataBlock(indexBlock, treatKeysAsInternal: false, complete: &complete)
        var results: [LevelDBEntry] = []

        for entry in indexEntries {
            guard let handle = self.decodeBlockHandle(from: entry.value) else { complete = false; continue }
            guard let blockData = self.readBlock(data: data, handle: handle, logger: logger)
            else { complete = false; continue }
            let dataEntries = self.parseDataBlock(blockData, treatKeysAsInternal: true, complete: &complete)
            results.append(contentsOf: dataEntries)
        }
        return results
    }

    private static func readBlock(
        data: Data,
        handle: BlockHandle,
        logger: (String) -> Void) -> Data?
    {
        let start = handle.offset
        guard start >= 0, start <= data.count,
              handle.size >= 0, handle.size <= data.count - start
        else { return nil }
        let end = start + handle.size
        guard data.count - end >= 5 else { return nil }
        let rawBlock = data.subdata(in: start..<end)
        let compressionType = data[end]
        switch compressionType {
        case 0:
            return rawBlock
        case 1:
            return SnappyDecoder.decompress(rawBlock)
        default:
            logger("Unsupported block compression: \(compressionType)")
            return nil
        }
    }

    private static func parseDataBlock(
        _ data: Data,
        treatKeysAsInternal: Bool,
        complete: inout Bool) -> [LevelDBEntry]
    {
        guard data.count >= 4 else { complete = false; return [] }
        let restartCount = Int(self.readUInt32LE(data, at: data.count - 4))
        let restartArraySize = (restartCount + 1) * 4
        guard data.count >= restartArraySize else { complete = false; return [] }
        let limit = data.count - restartArraySize

        var entries: [LevelDBEntry] = []
        var offset = 0
        var lastKey = Data()
        while offset < limit {
            guard let shared = self.readVarint32(data, at: &offset),
                  let nonShared = self.readVarint32(data, at: &offset),
                  let valueLength = self.readVarint32(data, at: &offset)
            else { complete = false; break }

            let keyEnd = offset + Int(nonShared)
            guard keyEnd <= limit else { complete = false; break }
            let keySuffix = data.subdata(in: offset..<keyEnd)
            offset = keyEnd

            let valueEnd = offset + Int(valueLength)
            guard valueEnd <= limit else { complete = false; break }
            let value = data.subdata(in: offset..<valueEnd)
            offset = valueEnd

            guard shared <= lastKey.count else { complete = false; break }
            let prefix = lastKey.prefix(Int(shared))
            var fullKey = Data(prefix)
            fullKey.append(keySuffix)
            lastKey = fullKey

            if treatKeysAsInternal {
                guard let internalKey = self.decodeInternalKey(fullKey), internalKey.valueType <= 1
                else { complete = false; continue }
                entries.append(LevelDBEntry(
                    key: internalKey.userKey,
                    value: value,
                    isDeletion: internalKey.valueType == 0,
                    sequence: internalKey.sequence))
            } else {
                entries.append(LevelDBEntry(key: fullKey, value: value, isDeletion: false, sequence: 0))
            }
        }
        return entries
    }

    private static func decodeInternalKey(_ data: Data) -> (userKey: Data, valueType: UInt8, sequence: UInt64)? {
        guard data.count >= 8 else { return nil }
        let userKey = data.prefix(data.count - 8)
        let tag = self.readUInt64LE(data, at: data.count - 8)
        let valueType = UInt8(tag & 0xFF)
        return (Data(userKey), valueType, tag >> 8)
    }

    private static func readBlockHandle(_ reader: inout ByteReader) -> BlockHandle? {
        guard let offset = reader.readVarint64(),
              let size = reader.readVarint64()
        else { return nil }
        guard let parsedOffset = Int(exactly: offset),
              let parsedSize = Int(exactly: size)
        else { return nil }
        return BlockHandle(offset: parsedOffset, size: parsedSize)
    }

    private static func decodeBlockHandle(from value: Data) -> BlockHandle? {
        var reader = ByteReader(value)
        guard let offset = reader.readVarint64(),
              let size = reader.readVarint64()
        else { return nil }
        guard let parsedOffset = Int(exactly: offset),
              let parsedSize = Int(exactly: size)
        else { return nil }
        return BlockHandle(offset: parsedOffset, size: parsedSize)
    }

    // MARK: - Data helpers

    struct ByteReader {
        private let bytes: [UInt8]
        private(set) var index: Int = 0

        init(_ data: Data) {
            self.bytes = Array(data)
        }

        var isAtEnd: Bool {
            self.index == self.bytes.count
        }

        mutating func readSlice() -> Data? {
            guard let length = self.readVarint64(), length <= UInt32.max,
                  length <= self.bytes.count - self.index
            else { return nil }
            let end = self.index + Int(length)
            defer { self.index = end }
            return Data(self.bytes[self.index..<end])
        }

        mutating func readVarint64() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while shift < 64 {
                guard let byte = self.readUInt8() else { return nil }
                guard shift < 63 || byte <= 1 else { return nil }
                result |= UInt64(byte & 0x7F) << shift
                if (byte & 0x80) == 0 {
                    return result
                }
                shift += 7
            }
            return nil
        }

        mutating func readUInt8() -> UInt8? {
            guard self.index < self.bytes.count else { return nil }
            let value = self.bytes[self.index]
            self.index += 1
            return value
        }
    }

    private static func readUInt8(_ data: Data, at offset: inout Int) -> UInt8? {
        guard offset < data.count else { return nil }
        let value = data[offset]
        offset += 1
        return value
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let byte0 = UInt16(data[offset])
        let byte1 = UInt16(data[offset + 1])
        return byte0 | (byte1 << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let byte0 = UInt32(data[offset])
        let byte1 = UInt32(data[offset + 1]) << 8
        let byte2 = UInt32(data[offset + 2]) << 16
        let byte3 = UInt32(data[offset + 3]) << 24
        return byte0 | byte1 | byte2 | byte3
    }

    private static func readUInt64LE(_ data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << (UInt64(index) * 8)
        }
        return value
    }

    private static func readVarint32(_ data: Data, at offset: inout Int) -> UInt32? {
        var result: UInt32 = 0
        var shift: UInt32 = 0
        while shift < 32 {
            guard let byte = self.readUInt8(data, at: &offset) else { return nil }
            guard shift < 28 || byte <= 0x0F else { return nil }
            result |= UInt32(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
        }
        return nil
    }

    private static func readLengthPrefixedSlice(_ data: Data, at offset: inout Int) -> Data? {
        guard let length = self.readVarint32(data, at: &offset) else { return nil }
        let count = Int(length)
        guard offset <= data.count, count <= data.count - offset else { return nil }
        let slice = data.subdata(in: offset..<(offset + count))
        offset += count
        return slice
    }
}

#endif
