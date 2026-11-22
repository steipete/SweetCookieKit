#if os(macOS)
import Compression
import CoreFoundation
import Foundation

enum GeckoSessionCookieReader {
    private static let maximumSize = 64 * 1024 * 1024
    private static let magic = Data("mozLz40\0".utf8)

    static func readCookies(in profile: URL, expiryDivisor: TimeInterval = 1) -> [GeckoCookieImporter.CookieRecord] {
        let directory = profile.appendingPathComponent("sessionstore-backups")
        // Only fall back when missing; a corrupt current file must not revive older credentials.
        let candidates = [
            directory.appendingPathComponent("recovery.jsonlz4"),
            profile.appendingPathComponent("sessionstore.jsonlz4"),
            directory.appendingPathComponent("recovery.baklz4"),
        ]
        guard let source = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let metadata = try? source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              metadata.isRegularFile == true,
              let size = metadata.fileSize, size <= Self.maximumSize,
              let handle = try? FileHandle(forReadingFrom: source)
        else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumSize + 1),
              data.count <= Self.maximumSize,
              let json = Self.decompress(data),
              let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let cookies = root["cookies"] as? [Any]
        else { return [] }
        return cookies.compactMap { Self.cookieRecord($0, expiryDivisor: expiryDivisor) }
    }

    private static func decompress(_ data: Data) -> Data? {
        guard data.count > 12, data.starts(with: Self.magic) else { return nil }
        let size = (0..<4).reduce(0) { $0 | (Int(data[8 + $1]) << (8 * $1)) }
        guard size > 0, size <= Self.maximumSize else { return nil }
        // The buffer API reports a full buffer for truncated output; one extra byte distinguishes it.
        var output = [UInt8](repeating: 0, count: size + 1)
        let decodedCount = data.withUnsafeBytes { source in
            compression_decode_buffer(
                &output,
                output.count,
                source.bindMemory(to: UInt8.self).baseAddress!.advanced(by: 12),
                data.count - 12,
                nil,
                COMPRESSION_LZ4_RAW)
        }
        guard decodedCount == size else { return nil }
        return Data(output.prefix(size))
    }

    private static func cookieRecord(_ entry: Any, expiryDivisor: TimeInterval) -> GeckoCookieImporter.CookieRecord? {
        guard let cookie = entry as? [String: Any],
              Self.hasDefaultIsolation(cookie),
              let host = cookie["host"] as? String, !host.isEmpty,
              cookie["name"] == nil || cookie["name"] is String,
              cookie["path"] == nil || cookie["path"] is String,
              let value = cookie["value"] as? String
        else { return nil }
        var expires: Date?
        if let rawExpiry = cookie["expiry"] {
            guard let expiry = rawExpiry as? NSNumber,
                  CFGetTypeID(expiry) != CFBooleanGetTypeID(), expiry.doubleValue.isFinite
            else { return nil }
            expires = Date(timeIntervalSince1970: expiry.doubleValue / expiryDivisor)
        }
        let rawSameSite = cookie["sameSite"] ?? 0 // Gecko restores legacy entries as SameSite=None.
        guard let sameSite = rawSameSite as? NSNumber,
              CFGetTypeID(sameSite) != CFBooleanGetTypeID(),
              let sameSitePolicy = GeckoCookieImporter.sameSitePolicy(for: sameSite.int64Value),
              sameSite.doubleValue == Double(sameSite.int64Value)
        else { return nil }
        return GeckoCookieImporter.CookieRecord(
            host: host,
            name: cookie["name"] as? String ?? "",
            path: cookie["path"] as? String ?? "",
            value: value,
            expires: nil,
            sessionExpiry: expires,
            sameSitePolicy: sameSitePolicy,
            isSecure: cookie["secure"] as? Bool ?? false,
            isHTTPOnly: cookie["httponly"] as? Bool ?? false)
    }

    private static func hasDefaultIsolation(_ cookie: [String: Any]) -> Bool {
        if let partitioned = cookie["isPartitioned"] {
            guard let flag = partitioned as? Bool, !flag else { return false }
        }
        guard let rawAttributes = cookie["originAttributes"] else { return true }
        guard let attributes = rawAttributes as? [String: Any] else { return false }
        // The public record cannot carry container or partition identity. Unknown attributes fail closed.
        return attributes.allSatisfy { key, value in
            switch key {
            case "userContextId", "privateBrowsingId":
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
                    return false
                }
                return number.doubleValue == 0
            case "firstPartyDomain", "partitionKey", "geckoViewSessionContextId":
                return (value as? String)?.isEmpty == true
            default:
                return false
            }
        }
    }
}
#endif
