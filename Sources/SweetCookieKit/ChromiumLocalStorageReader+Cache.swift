import Foundation

#if os(macOS)
import Darwin

extension ChromiumLocalStorageReader {
    /// Task-local injection keeps synthetic clocks and I/O hooks isolated in parallel tests.
    @TaskLocal static var levelDBCache = LevelDBReadCache()

    /// Drops all memoized local-storage data, including data used by `ChromiumLevelDBReader`.
    public static func invalidateCache() {
        self.levelDBCache.invalidate()
    }
}

/// All mutable state and traversal I/O are protected by the lock. Callers replay diagnostics after unlocking.
final class LevelDBReadCache: @unchecked Sendable {
    private static let epoch = ContinuousClock.now

    enum Derivation: Hashable {
        case textDecode, tokenScan, localStorageKey, localStorageValue
    }

    struct OriginResult {
        let entries: [ChromiumLocalStorageEntry]
        let decodedKeys: Int
    }

    struct DerivedResults {
        var text: [ChromiumLevelDBTextEntry]?
        var tokens = Variants<Int, [String]>()
        var origins = Variants<Data, OriginResult>()
    }

    struct Variants<Key: Hashable, Value> {
        private var values: [Key: Value] = [:]
        private var recency: [Key] = []

        mutating func value(for key: Key, create: () -> Value) -> Value {
            self.recency.removeAll { $0 == key }
            self.recency.append(key)
            if let cached = self.values[key] {
                return cached
            }
            let value = create()
            self.values[key] = value
            if self.recency.count > 16 {
                self.values.removeValue(forKey: self.recency.removeFirst())
            }
            return value
        }
    }

    private struct FileStamp: Equatable {
        let name: String
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
        let inode: ino_t
        let device: dev_t
        let mode: mode_t
    }

    private struct Memo {
        let snapshot: [FileStamp]
        let entries: [ChromiumLocalStorageReader.LevelDBEntry]
        let diagnostics: [String]
        let created: TimeInterval
        var derived: DerivedResults
    }

    private let lock = NSLock()
    private let clock: @Sendable () -> TimeInterval
    let readData: @Sendable (URL) throws -> Data
    let onDerivation: (@Sendable (Derivation) -> Void)?
    private var memos: [String: Memo] = [:]
    private var recency: [String] = []

    init(
        clock: @escaping @Sendable () -> TimeInterval = {
            let elapsed = LevelDBReadCache.epoch.duration(to: .now).components
            return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        },
        readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0, options: [.mappedIfSafe]) },
        onDerivation: (@Sendable (Derivation) -> Void)? = nil)
    {
        self.clock = clock
        self.readData = readData
        self.onDerivation = onDerivation
    }

    func invalidate() {
        self.lock.withLock {
            self.memos.removeAll()
            self.recency.removeAll()
        }
    }

    func read<Value>(
        in directory: URL,
        load: ([URL], inout Bool, (String) -> Void) -> [ChromiumLocalStorageReader.LevelDBEntry],
        derive: ([ChromiumLocalStorageReader.LevelDBEntry], inout DerivedResults) -> Value)
        -> (value: Value?, diagnostics: [String])
    {
        self.lock.withLock {
            let now = self.clock()
            self.memos = self.memos.filter { now >= $0.value.created && now - $0.value.created < 600 }
            self.recency.removeAll { self.memos[$0] == nil }
            let path = directory.standardizedFileURL.path
            guard let files = Self.files(in: directory) else {
                self.memos.removeValue(forKey: path)
                self.recency.removeAll { $0 == path }
                return (nil, [])
            }
            let before = Self.snapshot(files)
            if let before, var memo = self.memos[path], memo.snapshot == before {
                self.recency.removeAll { $0 == path }
                self.recency.append(path)
                let value = derive(memo.entries, &memo.derived)
                self.memos[path] = memo
                return (value, memo.diagnostics)
            }
            self.memos.removeValue(forKey: path)
            self.recency.removeAll { $0 == path }
            var complete = true
            var diagnostics: [String] = []
            let entries = load(files, &complete) { diagnostics.append($0) }
            var derived = DerivedResults()
            let value = derive(entries, &derived)
            if complete, let before, let after = Self.files(in: directory).flatMap(Self.snapshot), before == after {
                self.memos[path] = Memo(
                    snapshot: before, entries: entries, diagnostics: diagnostics, created: now, derived: derived)
                self.recency.append(path)
                if self.recency.count > 8 {
                    self.memos.removeValue(forKey: self.recency.removeFirst())
                }
            }
            return (value, diagnostics)
        }
    }

    private static func files(in directory: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
    }

    private static func snapshot(_ files: [URL]) -> [FileStamp]? {
        var result: [FileStamp] = []
        for file in files {
            let name = file.lastPathComponent
            guard name == "CURRENT" || name.hasPrefix("MANIFEST-") ||
                ["log", "ldb", "sst"].contains(file.pathExtension.lowercased()) else { continue }
            var info = stat()
            guard stat(file.path, &info) == 0, access(file.path, R_OK) == 0 else { return nil }
            result.append(FileStamp(
                name: name,
                size: info.st_size,
                modifiedSeconds: info.st_mtimespec.tv_sec,
                modifiedNanoseconds: info.st_mtimespec.tv_nsec,
                changedSeconds: info.st_ctimespec.tv_sec,
                changedNanoseconds: info.st_ctimespec.tv_nsec,
                inode: info.st_ino,
                device: info.st_dev,
                mode: info.st_mode))
        }
        // Retain enumeration order too: equal-mtime files use that order during traversal.
        return result
    }
}
#endif
