import Foundation

#if os(macOS)
import Darwin

extension ChromiumLocalStorageReader {
    enum StrictReadEvent: Sendable {
        case willOpen(String)
        case didRead(String)
    }

    /// Synthetic race injection; production has no observer and cannot override the read implementation.
    @TaskLocal static var strictReadObserver: (@Sendable (StrictReadEvent) -> Void)?
}

/// Descriptors pin every directory component. File data is read only through no-follow openat + pread.
/// Metadata checks detect observable mutation; they do not turn a live LevelDB into a transaction.
final class ChromiumAnchoredFiles: @unchecked Sendable {
    private struct DirectoryLink {
        let parent: Int32
        let name: String
        let descriptor: Int32
    }

    private struct Stamp: Equatable {
        let device: dev_t
        let inode: ino_t
        let mode: mode_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ value: stat) {
            self.device = value.st_dev
            self.inode = value.st_ino
            self.mode = value.st_mode
            self.size = value.st_size
            self.modifiedSeconds = value.st_mtimespec.tv_sec
            self.modifiedNanoseconds = value.st_mtimespec.tv_nsec
            self.changedSeconds = value.st_ctimespec.tv_sec
            self.changedNanoseconds = value.st_ctimespec.tv_nsec
        }
    }

    private let directory: URL
    private let descriptors: [Int32]
    private let links: [DirectoryLink]
    private let initial: [String: Stamp]
    private var descriptor: Int32 {
        self.descriptors.last!
    }

    var files: [URL] {
        self.initial.keys.sorted().map { self.directory.appendingPathComponent($0) }
    }

    init?(directory: URL) {
        guard directory.isFileURL, directory.path.hasPrefix("/") else { return nil }
        let root = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard root >= 0 else { return nil }
        var descriptors = [root]
        var links: [DirectoryLink] = []
        var succeeded = false
        defer {
            if !succeeded {
                descriptors.reversed().forEach { _ = close($0) }
            }
        }
        // Foundation standardization can turn /private/var back into the /var symlink on macOS.
        // Preserve the supplied physical path; never resolve a caller's symlink or dot traversal here.
        for component in directory.pathComponents.dropFirst() {
            guard component != ".", component != "..", !component.contains("/") else { return nil }
            let parent = descriptors.last!
            let child = openat(parent, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            guard child >= 0 else { return nil }
            descriptors.append(child)
            links.append(DirectoryLink(parent: parent, name: component, descriptor: child))
        }
        guard let initial = Self.snapshot(descriptors.last!), initial["CURRENT"] != nil else { return nil }
        self.directory = directory
        self.descriptors = descriptors
        self.links = links
        self.initial = initial
        succeeded = true
    }

    deinit { self.descriptors.reversed().forEach { _ = close($0) } }

    func unchanged() -> Bool {
        for link in self.links {
            var named = stat()
            var opened = stat()
            guard fstatat(link.parent, link.name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  fstat(link.descriptor, &opened) == 0,
                  named.st_mode & S_IFMT == S_IFDIR,
                  named.st_dev == opened.st_dev, named.st_ino == opened.st_ino else { return false }
        }
        return Self.snapshot(self.descriptor) == self.initial
    }

    func read(_ url: URL) throws -> Data {
        let name = url.lastPathComponent
        guard url.deletingLastPathComponent().path == self.directory.path,
              let expected = self.initial[name] else { throw CocoaError(.fileReadNoPermission) }
        ChromiumLocalStorageReader.strictReadObserver?(.willOpen(name))
        let file = openat(self.descriptor, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard file >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { _ = close(file) }
        var before = stat()
        guard fstat(file, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              Stamp(before) == expected, before.st_size >= 0, before.st_size <= 64 * 1024 * 1024
        else { throw CocoaError(.fileReadCorruptFile) }
        var data = Data(count: Int(before.st_size))
        let complete = data.withUnsafeMutableBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let count = pread(file, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, off_t(offset))
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        var after = stat()
        guard complete, fstat(file, &after) == 0, Stamp(after) == expected else {
            throw CocoaError(.fileReadCorruptFile)
        }
        ChromiumLocalStorageReader.strictReadObserver?(.didRead(name))
        return data
    }

    private static func snapshot(_ descriptor: Int32) -> [String: Stamp]? {
        // A fresh open description avoids sharing the enumeration offset with the pinned directory.
        let scan = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard scan >= 0 else { return nil }
        guard let stream = fdopendir(scan) else { _ = close(scan); return nil }
        defer { _ = closedir(stream) }
        var result: [String: Stamp] = [:]
        while true {
            errno = 0
            guard let entry = readdir(stream) else { return errno == 0 ? result : nil }
            guard let name = withUnsafeBytes(of: entry.pointee.d_name, { bytes in
                String(bytes: bytes.prefix(while: { $0 != 0 }), encoding: .utf8)
            }) else { return nil }
            guard name == "CURRENT" || name.hasPrefix("MANIFEST-") ||
                ["log", "ldb", "sst"].contains(URL(fileURLWithPath: name).pathExtension.lowercased()) else { continue }
            var info = stat()
            guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                  info.st_mode & S_IFMT == S_IFREG else { return nil }
            result[name] = Stamp(info)
        }
    }
}
#endif
