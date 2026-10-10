import Foundation

#if os(macOS)

extension ChromiumLocalStorageReader {
    static func liveLevelDBFiles(
        _ files: [URL],
        cache: LevelDBReadCache,
        complete: inout Bool,
        logger: (String) -> Void) -> [URL]
    {
        let candidates = files.filter { ["log", "ldb", "sst"].contains($0.pathExtension.lowercased()) }
        guard let current = files.first(where: { $0.lastPathComponent == "CURRENT" }) else { return candidates }
        guard let currentData = try? cache.readData(current),
              let currentText = String(data: currentData, encoding: .utf8), currentText.hasSuffix("\n")
        else {
            complete = false
            logger("Could not read LevelDB CURRENT")
            return []
        }
        let manifestName = String(currentText.dropLast())
        guard manifestName.hasPrefix("MANIFEST-"),
              let manifest = files.first(where: { $0.lastPathComponent == manifestName })
        else {
            complete = false
            logger("LevelDB CURRENT does not name an available manifest")
            return []
        }

        var manifestComplete = true
        let records = self.readLogRecords(from: manifest, cache: cache, complete: &manifestComplete)
        var version = ManifestVersion()
        for record in records {
            guard version.apply(record) else {
                manifestComplete = false; break
            }
        }
        guard manifestComplete, let logNumber = version.logNumber, version.hasNextFile, version.hasLastSequence else {
            complete = false
            logger("Could not decode LevelDB manifest; live files are unknown")
            return []
        }

        let liveTables = Set(version.tables.map(\.number))
        var foundTables = Set<UInt64>()
        let selected = candidates.filter { file in
            guard let number = UInt64(file.deletingPathExtension().lastPathComponent) else { return false }
            if file.pathExtension.lowercased() == "log" {
                // Match LevelDB recovery: include uncommitted newer logs and the previous log, if any.
                return number >= logNumber || number == version.previousLogNumber
            }
            guard liveTables.contains(number) else { return false }
            foundTables.insert(number)
            return true
        }
        if foundTables != liveTables {
            complete = false
            logger("LevelDB manifest references missing tables")
        }
        return selected
    }

    private struct ManifestVersion {
        struct Table: Hashable {
            let level: UInt64
            let number: UInt64
        }

        var logNumber: UInt64?
        var previousLogNumber: UInt64 = 0
        var hasNextFile = false
        var hasLastSequence = false
        var tables = Set<Table>()

        mutating func apply(_ data: Data) -> Bool {
            var reader = ByteReader(data)
            var deleted = Set<Table>()
            var added = Set<Table>()
            while !reader.isAtEnd {
                guard let tag = reader.readVarint64() else { return false }
                switch tag {
                case 1: // Comparator.
                    guard reader.readSlice() != nil else { return false }
                case 2:
                    guard let number = reader.readVarint64() else { return false }
                    self.logNumber = number
                case 3:
                    guard reader.readVarint64() != nil else { return false }
                    self.hasNextFile = true
                case 4:
                    guard let sequence = reader.readVarint64(), sequence <= UInt64.max >> 8 else { return false }
                    self.hasLastSequence = true
                case 5: // Compaction pointer.
                    guard let level = reader.readVarint64(), level < 7, reader.readSlice() != nil else { return false }
                case 6:
                    guard let level = reader.readVarint64(), level < 7,
                          let number = reader.readVarint64() else { return false }
                    deleted.insert(Table(level: level, number: number))
                case 7:
                    guard let level = reader.readVarint64(), level < 7,
                          let number = reader.readVarint64(), reader.readVarint64() != nil,
                          reader.readSlice() != nil, reader.readSlice() != nil else { return false }
                    added.insert(Table(level: level, number: number))
                case 9:
                    guard let number = reader.readVarint64() else { return false }
                    self.previousLogNumber = number
                default:
                    return false
                }
            }
            // VersionEdit additions win over deletions of the same file within that edit.
            self.tables.subtract(deleted)
            self.tables.formUnion(added)
            return true
        }
    }
}

#endif
