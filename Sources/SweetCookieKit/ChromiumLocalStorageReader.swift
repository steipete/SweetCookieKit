import Foundation

#if os(macOS)

/// Decoded Chromium local storage entry for a single origin/key pair.
public struct ChromiumLocalStorageEntry: Sendable {
    public let origin: String
    public let key: String
    public let value: String
    public let rawValueLength: Int

    public init(origin: String, key: String, value: String, rawValueLength: Int) {
        self.origin = origin
        self.key = key
        self.value = value
        self.rawValueLength = rawValueLength
    }
}

/// Best-effort decoded text key/value pair from a Chromium LevelDB store.
public struct ChromiumLevelDBTextEntry: Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Reads Chromium local storage values from the underlying LevelDB store.
public enum ChromiumLocalStorageReader {
    static let blockSize = 32 * 1024
    static let footerSize = 48
    private static let tokenBytes = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-+/=".utf8)

    public static func readEntries(
        for origin: String,
        in levelDBURL: URL,
        logger: ((String) -> Void)? = nil) -> [ChromiumLocalStorageEntry]
    {
        let normalizedOrigin = self.normalizeOrigin(origin)
        let log: (String) -> Void = { message in
            logger?("[chromium-storage] \(message)")
        }

        guard let entries = self.levelDBEntries(in: levelDBURL, logger: log) else {
            return []
        }

        var values: [String: String] = [:]
        var rawLengths: [String: Int] = [:]
        var tombstones = Set<String>()
        var decodedKeys = 0
        for entry in entries {
            guard let localKey = self.decodeLocalStorageKey(entry.key) else { continue }
            decodedKeys += 1
            let entryOrigin = self.normalizeOrigin(localKey.origin)
            guard self.originMatches(entryOrigin, normalizedOrigin) else { continue }
            let storageKey = localKey.key

            if entry.isDeletion {
                tombstones.insert(storageKey)
                values.removeValue(forKey: storageKey)
                continue
            }

            guard !tombstones.contains(storageKey) else { continue }
            // Keep the first seen value per key; LevelDB logs are already newest-first.
            guard values[storageKey] == nil else { continue }
            guard let decoded = self.decodeLocalStorageValue(entry.value) else { continue }
            values[storageKey] = decoded
            rawLengths[storageKey] = entry.value.count
        }

        if decodedKeys == 0 {
            log("No local storage keys decoded in \(levelDBURL.lastPathComponent)")
        } else if values.isEmpty {
            log("No local storage values for origin \(normalizedOrigin)")
        } else {
            log("Local storage values for origin \(normalizedOrigin): \(values.count)")
        }

        return values.map {
            ChromiumLocalStorageEntry(
                origin: normalizedOrigin,
                key: $0.key,
                value: $0.value,
                rawValueLength: rawLengths[$0.key] ?? $0.value.utf8.count)
        }
    }

    /// Convenience wrapper for scanning a LevelDB directory for readable key/value pairs.
    /// Prefer `ChromiumLevelDBReader` for non-local-storage use cases.
    public static func readTextEntries(
        in levelDBURL: URL,
        logger: ((String) -> Void)? = nil) -> [ChromiumLevelDBTextEntry]
    {
        let log: (String) -> Void = { message in
            logger?("[chromium-storage] \(message)")
        }

        guard let entries = self.levelDBEntries(in: levelDBURL, logger: log) else {
            return []
        }

        var results: [ChromiumLevelDBTextEntry] = []
        results.reserveCapacity(entries.count)
        for entry in entries {
            guard let key = self.decodeText(entry.key) else { continue }
            let decoded = self.decodeText(entry.value)
            let stripped = self.decodeLocalStorageValue(entry.value)
            let value = self.pickBestValue(decoded, stripped)
            guard let value else { continue }
            results.append(ChromiumLevelDBTextEntry(key: key, value: value))
        }

        return results
    }

    /// Convenience wrapper for token candidate scanning across LevelDB entries.
    /// Prefer `ChromiumLevelDBReader` when you do not need local storage decoding.
    public static func readTokenCandidates(
        in levelDBURL: URL,
        minimumLength: Int = 60,
        logger: ((String) -> Void)? = nil) -> [String]
    {
        let log: (String) -> Void = { message in
            logger?("[chromium-storage] \(message)")
        }

        guard let entries = self.levelDBEntries(in: levelDBURL, logger: log) else {
            return []
        }

        var tokens = Set<String>()
        for entry in entries {
            tokens.formUnion(self.scanTokens(in: entry.key, minimumLength: minimumLength))
            tokens.formUnion(self.scanTokens(in: entry.value, minimumLength: minimumLength))
        }
        return Array(tokens)
    }

    // MARK: - Local storage decoding

    private struct LocalStorageKey: Sendable {
        let origin: String
        let key: String
    }

    private static func decodeLocalStorageKey(_ data: Data) -> LocalStorageKey? {
        if let decoded = self.decodeLocalStorageKey(data, startIndex: 1, requiresPrefix: true) {
            return decoded
        }
        return self.decodeLocalStorageKey(data, startIndex: 0, requiresPrefix: false)
    }

    private static func decodeLocalStorageKey(
        _ data: Data,
        startIndex: Int,
        requiresPrefix: Bool) -> LocalStorageKey?
    {
        let bytes = [UInt8](data)
        if requiresPrefix, bytes.first != 0x5F {
            return nil
        }

        guard let splitIndex = bytes[startIndex...].firstIndex(of: 0x00) else { return nil }
        guard splitIndex + 1 < bytes.count else { return nil }

        let originData = Data(bytes[startIndex..<splitIndex])
        let keyData = Data(bytes[(splitIndex + 1)..<bytes.count])

        guard let originValue = self.decodeText(originData),
              let key = self.decodePrefixedString(keyData) ?? self.decodeText(keyData)
        else { return nil }

        let origin = self.storageKeyOrigin(from: originValue)
        if !requiresPrefix, !self.looksLikeOrigin(origin) {
            return nil
        }
        return LocalStorageKey(origin: origin, key: key)
    }

    private static func looksLikeOrigin(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.contains("://") { return true }
        if trimmed == "localhost" || trimmed.hasPrefix("localhost:") { return true }
        return trimmed.contains(".")
    }

    private static func decodeLocalStorageValue(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        return self.decodePrefixedString(data) ?? self.decodeText(data)
    }

    private static func decodeText(_ data: Data) -> String? {
        if data.isEmpty { return nil }
        if let decoded = self.decodePrefixedString(data) {
            return decoded.trimmingCharacters(in: .controlCharacters)
        }
        if self.looksLikeUTF16(data),
           let decoded = String(data: data, encoding: .utf16LittleEndian)
        {
            return decoded.trimmingCharacters(in: .controlCharacters)
        }
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded.trimmingCharacters(in: .controlCharacters)
        }
        if let decoded = String(data: data, encoding: .utf16LittleEndian) {
            return decoded.trimmingCharacters(in: .controlCharacters)
        }
        if let decoded = String(data: data, encoding: .isoLatin1) {
            return decoded.trimmingCharacters(in: .controlCharacters)
        }
        return nil
    }

    private static func decodePrefixedString(_ data: Data) -> String? {
        guard data.count > 1, let prefix = data.first else { return nil }
        let payload = data.dropFirst()
        switch prefix {
        case 0:
            return String(data: payload, encoding: .utf16LittleEndian)
        case 1:
            return String(data: payload, encoding: .isoLatin1)
        default:
            return nil
        }
    }

    private static func looksLikeUTF16(_ data: Data) -> Bool {
        guard data.count >= 6, data.count % 2 == 0 else { return false }
        let sample = data.prefix(64)
        var zeroCount = 0
        var checked = 0
        var index = 1
        while index < sample.count {
            checked += 1
            if sample[sample.index(sample.startIndex, offsetBy: index)] == 0 {
                zeroCount += 1
            }
            index += 2
        }
        guard checked >= 4 else { return false }
        return Double(zeroCount) / Double(checked) > 0.6
    }

    private static func pickBestValue(_ first: String?, _ second: String?) -> String? {
        let candidates = [first, second].compactMap(\.self).filter { !$0.isEmpty }
        guard let best = candidates.max(by: { $0.count < $1.count }) else { return nil }
        return best
    }

    private static func normalizeOrigin(_ origin: String) -> String {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") {
            return String(trimmed.dropLast())
        }
        return trimmed
    }

    private static func storageKeyOrigin(from value: String) -> String {
        // Chromium StorageKey::SerializeForLocalStorage uses origin.Serialize or StorageKey::Serialize
        // (caret-suffixed).
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let base: Substring = if let caretIndex = trimmed.firstIndex(of: "^") {
            trimmed[..<caretIndex]
        } else {
            trimmed[...]
        }

        var origin = String(base)
        if let schemeRange = origin.range(of: "://") {
            let afterScheme = origin[schemeRange.upperBound...]
            if let slashIndex = afterScheme.firstIndex(of: "/") {
                origin = String(origin[..<slashIndex])
            }
        } else if let slashIndex = origin.firstIndex(of: "/") {
            origin = String(origin[..<slashIndex])
        }

        if origin.hasSuffix("/") {
            origin.removeLast()
        }
        return origin
    }

    private static func originMatches(_ storageKeyOrigin: String, _ requestedOrigin: String) -> Bool {
        if storageKeyOrigin == requestedOrigin { return true }

        let storageHost = self.originHost(from: storageKeyOrigin)
        let requestedHost = self.originHost(from: requestedOrigin)
        if let storageHost, let requestedHost, storageHost == requestedHost { return true }

        let requestedStripped = self.stripScheme(from: requestedOrigin)
        if storageKeyOrigin == requestedStripped { return true }
        return false
    }

    private static func originHost(from value: String) -> String? {
        if let url = URL(string: value), let host = url.host {
            if let port = url.port {
                return "\(host):\(port)"
            }
            return host
        }
        let stripped = self.stripScheme(from: value)
        let host = stripped.split(separator: "/").first
        return host.map(String.init)
    }

    private static func stripScheme(from value: String) -> String {
        if let range = value.range(of: "://") {
            return String(value[range.upperBound...])
        }
        return value
    }

    private static func scanTokens(in data: Data, minimumLength: Int) -> [String] {
        guard minimumLength > 0 else { return [] }
        var buffer: [UInt8] = []
        var results: [String] = []
        buffer.reserveCapacity(minimumLength)

        func flushBuffer() {
            guard buffer.count >= minimumLength,
                  let string = String(bytes: buffer, encoding: .ascii)
            else {
                buffer.removeAll(keepingCapacity: true)
                return
            }
            let parts = string.split(separator: ".")
            if parts.count >= 3 || string.count >= minimumLength {
                results.append(string)
            }
            buffer.removeAll(keepingCapacity: true)
        }

        for byte in data {
            if self.tokenBytes.contains(byte) {
                buffer.append(byte)
            } else if !buffer.isEmpty {
                flushBuffer()
            }
        }
        if !buffer.isEmpty {
            flushBuffer()
        }

        return results
    }
}

#endif
