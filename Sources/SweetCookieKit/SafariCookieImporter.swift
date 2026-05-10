#if os(macOS)
import Foundation

/// Reads cookies from Safari's `Cookies.binarycookies` file (macOS).
///
/// This is a best-effort parser for the documented `binarycookies` format:
/// file header is big-endian; cookie pages and records are little-endian.
enum SafariCookieImporter {
    enum ImportError: LocalizedError {
        case cookieFileNotFound
        case cookieFileNotReadable(path: String)
        case invalidFile

        var errorDescription: String? {
            switch self {
            case .cookieFileNotFound: "Safari cookie file not found."
            case let .cookieFileNotReadable(path):
                "Safari cookie file exists but is not readable (\(path)). Enable Full Disk Access."
            case .invalidFile: "Safari cookie file is invalid."
            }
        }
    }

    struct CookieRecord {
        let domain: String
        let name: String
        let path: String
        let value: String
        let expires: Date?
        let isSecure: Bool
        let isHTTPOnly: Bool
    }

    static func availableStores(homeDirectories: [URL]) -> [BrowserCookieStore] {
        var stores: [BrowserCookieStore] = []
        var seenIDs = Set<String>()

        for url in self.candidateCookieFiles(homeDirectories: homeDirectories) {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let descriptor = self.storeDescriptor(for: url)
            var storeID = descriptor.id
            if !seenIDs.insert(storeID).inserted {
                storeID = "\(descriptor.id):\(url.path)"
                _ = seenIDs.insert(storeID)
            }

            stores.append(BrowserCookieStore(
                browser: .safari,
                profile: BrowserProfile(id: storeID, name: descriptor.name),
                kind: .safari,
                label: descriptor.label,
                databaseURL: url))
        }

        if stores.isEmpty {
            return [self.defaultStore()]
        }
        return stores
    }

    static func loadCookies(
        from store: BrowserCookieStore,
        matchingDomains domains: [String],
        domainMatch: BrowserCookieDomainMatch,
        homeDirectories: [URL],
        logger: ((String) -> Void)? = nil) throws -> [CookieRecord]
    {
        guard store.browser == .safari else {
            throw ImportError.invalidFile
        }
        guard let databaseURL = store.databaseURL else {
            return try self.loadCookies(
                matchingDomains: domains,
                domainMatch: domainMatch,
                homeDirectories: homeDirectories,
                logger: logger)
        }
        return try self.loadCookies(
            from: databaseURL,
            matchingDomains: domains,
            domainMatch: domainMatch,
            logger: logger)
    }

    static func loadCookies(
        matchingDomains domains: [String],
        domainMatch: BrowserCookieDomainMatch,
        homeDirectories: [URL],
        logger: ((String) -> Void)? = nil) throws -> [CookieRecord]
    {
        let candidates = self.candidateCookieFiles(homeDirectories: homeDirectories)
        var lastNoPermission: String?
        var lastReadError: String?

        for url in candidates {
            do {
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
                logger?("Safari cookies: trying \(url.path) (\(size ?? -1) bytes)")
                let data = try Data(contentsOf: url)
                let records = try Self.parseBinaryCookies(data: data)
                return records.filter { record in
                    BrowserCookieDomainMatcher.matches(
                        domain: record.domain,
                        patterns: domains,
                        match: domainMatch)
                }
            } catch let error as CocoaError where error.code == .fileReadNoPermission {
                lastNoPermission = url.path
                logger?("Safari cookies: permission denied for \(url.path)")
                continue
            } catch {
                lastReadError = "\(url.path): \(error.localizedDescription)"
                logger?("Safari cookies: failed to read \(url.path): \(error.localizedDescription)")
                continue
            }
        }

        if let lastNoPermission {
            throw ImportError.cookieFileNotReadable(path: lastNoPermission)
        }
        if let lastReadError {
            logger?("Safari cookies: last error: \(lastReadError)")
        }
        throw ImportError.cookieFileNotFound
    }

    private static func loadCookies(
        from url: URL,
        matchingDomains domains: [String],
        domainMatch: BrowserCookieDomainMatch,
        logger: ((String) -> Void)? = nil) throws -> [CookieRecord]
    {
        do {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
            logger?("Safari cookies: trying \(url.path) (\(size ?? -1) bytes)")
            let data = try Data(contentsOf: url)
            let records = try Self.parseBinaryCookies(data: data)
            return records.filter { record in
                BrowserCookieDomainMatcher.matches(
                    domain: record.domain,
                    patterns: domains,
                    match: domainMatch)
            }
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            logger?("Safari cookies: permission denied for \(url.path)")
            throw ImportError.cookieFileNotReadable(path: url.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            logger?("Safari cookies: missing \(url.path)")
            throw ImportError.cookieFileNotFound
        } catch let error as ImportError {
            throw error
        } catch {
            logger?("Safari cookies: failed to read \(url.path): \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - BinaryCookies parsing

    private static func parseBinaryCookies(data: Data) throws -> [CookieRecord] {
        let reader = DataReader(data)
        guard reader.readASCII(count: 4) == "cook" else { throw ImportError.invalidFile }
        let pageCount = Int(reader.readUInt32BE())
        guard pageCount >= 0 else { throw ImportError.invalidFile }

        var pageSizes: [Int] = []
        pageSizes.reserveCapacity(pageCount)
        for _ in 0..<pageCount {
            pageSizes.append(Int(reader.readUInt32BE()))
        }

        var records: [CookieRecord] = []
        var offset = reader.offset
        for size in pageSizes {
            guard offset + size <= data.count else { throw ImportError.invalidFile }
            let pageData = data.subdata(in: offset..<(offset + size))
            records.append(contentsOf: Self.parsePage(data: pageData))
            offset += size
        }
        return records
    }

    private static func parsePage(data: Data) -> [CookieRecord] {
        let r = DataReader(data)
        _ = r.readUInt32LE() // page header
        let cookieCount = Int(r.readUInt32LE())
        if cookieCount <= 0 { return [] }

        var cookieOffsets: [Int] = []
        cookieOffsets.reserveCapacity(cookieCount)
        for _ in 0..<cookieCount {
            cookieOffsets.append(Int(r.readUInt32LE()))
        }

        return cookieOffsets.compactMap { offset in
            guard offset >= 0, offset + 56 <= data.count else { return nil }
            return Self.parseCookieRecord(data: data, offset: offset)
        }
    }

    private static func parseCookieRecord(data: Data, offset: Int) -> CookieRecord? {
        let r = DataReader(data, offset: offset)
        let size = Int(r.readUInt32LE())
        guard size > 0, offset + size <= data.count else { return nil }

        _ = r.readUInt32LE() // unknown
        let flags = r.readUInt32LE()
        _ = r.readUInt32LE() // unknown

        let urlOffset = Int(r.readUInt32LE())
        let nameOffset = Int(r.readUInt32LE())
        let pathOffset = Int(r.readUInt32LE())
        let valueOffset = Int(r.readUInt32LE())
        _ = r.readUInt32LE() // commentOffset
        _ = r.readUInt32LE() // commentURL

        let expiresRef = r.readDoubleLE()
        _ = r.readDoubleLE() // creation

        let domain = Self.readCString(data: data, base: offset, offset: urlOffset) ?? ""
        let name = Self.readCString(data: data, base: offset, offset: nameOffset) ?? ""
        let path = Self.readCString(data: data, base: offset, offset: pathOffset) ?? "/"
        let value = Self.readCString(data: data, base: offset, offset: valueOffset) ?? ""

        if domain.isEmpty || name.isEmpty { return nil }

        let isSecure = (flags & 0x1) != 0
        let isHTTPOnly = (flags & 0x4) != 0
        let expires = expiresRef > 0 ? Date(timeIntervalSinceReferenceDate: expiresRef) : nil

        return CookieRecord(
            domain: Self.normalizeDomain(domain),
            name: name,
            path: path,
            value: value,
            expires: expires,
            isSecure: isSecure,
            isHTTPOnly: isHTTPOnly)
    }

    private static func readCString(data: Data, base: Int, offset: Int) -> String? {
        let start = base + offset
        guard start >= 0, start < data.count else { return nil }
        let end = data[start...].firstIndex(of: 0) ?? data.count
        guard end > start else { return nil }
        return String(data: data.subdata(in: start..<end), encoding: .utf8)
    }

    private static func normalizeDomain(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(".") { return String(trimmed.dropFirst()) }
        return trimmed
    }

    private static func candidateCookieFiles(homeDirectories: [URL]) -> [URL] {
        let homes = self.candidateHomes(from: homeDirectories)
        var urls: [URL] = []
        urls.reserveCapacity(homes.count * 4)
        for home in homes {
            urls.append(home.appendingPathComponent("Library/Cookies/Cookies.binarycookies"))
            urls.append(
                home.appendingPathComponent(
                    "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"))
            urls.append(contentsOf: self.websiteDataStoreCookieFiles(in: home))
        }
        var seen = Set<String>()
        return urls.filter { url in
            let path = url.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    private static func websiteDataStoreCookieFiles(in home: URL) -> [URL] {
        let roots = [
            home.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore"),
            home.appendingPathComponent("Library/WebKit/WebsiteDataStore"),
        ]

        return roots.flatMap { root in
            self.cookieFiles(in: root)
        }
    }

    private static func cookieFiles(in root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "Cookies.binarycookies" else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile != false else { continue }
            files.append(url)
        }
        return files
    }

    private static func candidateHomes(from homeDirectories: [URL]) -> [URL] {
        var seen = Set<String>()
        return homeDirectories.filter { home in
            let path = home.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    private static func defaultStore() -> BrowserCookieStore {
        BrowserCookieStore(
            browser: .safari,
            profile: BrowserProfile(id: "safari.default", name: "Default"),
            kind: .safari,
            label: "Safari",
            databaseURL: nil)
    }

    private static func storeDescriptor(for url: URL) -> (id: String, name: String, label: String) {
        let components = url.pathComponents
        if let index = components.firstIndex(of: "WebsiteDataStore"),
           index + 1 < components.count
        {
            let token = components[index + 1]
            return (
                id: "safari.datastore.\(token)",
                name: token,
                label: "Safari (\(token))")
        }

        let path = url.path
        if path.contains("/Library/Containers/com.apple.Safari/Data/Library/Cookies/") {
            return (id: "safari.default", name: "Default", label: "Safari")
        }
        if path.contains("/Library/Cookies/") {
            return (id: "safari.legacy", name: "Legacy", label: "Safari (Legacy)")
        }

        let name = url.deletingLastPathComponent().lastPathComponent
        return (id: "safari.\(name)", name: name, label: "Safari (\(name))")
    }
}

// MARK: - DataReader

private final class DataReader {
    let data: Data
    private(set) var offset: Int

    init(_ data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    func readASCII(count: Int) -> String? {
        let d = self.read(count)
        return String(data: d, encoding: .ascii)
    }

    func read(_ count: Int) -> Data {
        let end = min(self.offset + count, self.data.count)
        let slice = self.data[self.offset..<end]
        self.offset = end
        return Data(slice)
    }

    func readUInt32BE() -> UInt32 {
        let d = self.read(4)
        return d.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    func readUInt32LE() -> UInt32 {
        let d = self.read(4)
        return d.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }

    func readDoubleLE() -> Double {
        let d = self.read(8)
        let raw = d.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
        return Double(bitPattern: raw)
    }
}

#endif
