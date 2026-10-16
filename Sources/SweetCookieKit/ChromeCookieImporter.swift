#if os(macOS)
import CommonCrypto
import CryptoKit
import Darwin
import Foundation
import LocalAuthentication
import Security
import SQLite3

/// Reads cookies from a local Chromium cookie DB (macOS).
///
/// Notes:
/// - Chromium stores cookie values in an SQLite DB, and most values are encrypted (`encrypted_value` starts
///   with `v10` on macOS). Decryption uses the "Chrome Safe Storage" password from the macOS Keychain and
///   AES-CBC + PBKDF2. This is inherently brittle across Chromium changes; keep it best-effort.
enum ChromeCookieImporter {
    private static let chromeSafeStorageKeyLock = NSLock()
    private nonisolated(unsafe) static var cachedChromeSafeStorageKeys: [Browser: Data] = [:]

    enum ImportError: LocalizedError {
        case cookieDBNotFound(path: String)
        case keychainDenied
        case sqliteFailed(message: String)

        var errorDescription: String? {
            switch self {
            case let .cookieDBNotFound(path): "Chromium Cookies DB not found at \(path)."
            case .keychainDenied: "macOS Keychain denied access to Chrome Safe Storage."
            case let .sqliteFailed(message): "Failed to read Chromium cookies: \(message)"
            }
        }
    }

    struct CookieRecord {
        let hostKey: String
        let name: String
        let path: String
        let expiresUTC: Int64
        let isSecure: Bool
        let isHTTPOnly: Bool
        let value: String
    }

    static func availableStores(for browser: Browser, homeDirectories: [URL]) -> [BrowserCookieStore] {
        guard browser.engine == .chromium else { return [] }
        let labelPrefix = browser.displayName
        let roots = ChromiumProfileLocator
            .roots(for: [browser], homeDirectories: homeDirectories)
            .map(\.url)

        var candidates: [ChromeProfileCandidate] = []
        for root in roots {
            candidates.append(contentsOf: Self.chromeProfileCookieDBs(
                root: root,
                labelPrefix: labelPrefix,
                browser: browser))
        }
        return candidates
            .filter { FileManager.default.fileExists(atPath: $0.cookiesDB.path) }
            .map { candidate in
                BrowserCookieStore(
                    browser: candidate.browser,
                    profile: candidate.profile,
                    kind: candidate.kind,
                    label: candidate.label,
                    databaseURL: candidate.cookiesDB)
            }
    }

    static func loadCookies(
        from store: BrowserCookieStore,
        matchingDomains domains: [String],
        domainMatch: BrowserCookieDomainMatch,
        safeStorageKey: (Browser) throws -> Data = ChromeCookieImporter.chromeSafeStorageKey) throws -> [CookieRecord]
    {
        guard let sourceDB = store.databaseURL else {
            throw ImportError.cookieDBNotFound(path: "Missing cookie DB for \(store.label)")
        }
        return try Self.readCookiesFromLockedChromeDB(
            sourceDB: sourceDB,
            keyProvider: { try safeStorageKey(store.browser) },
            matchingDomains: domains,
            domainMatch: domainMatch)
    }

    // MARK: - DB copy helper

    private static func readCookiesFromLockedChromeDB(
        sourceDB: URL,
        keyProvider: () throws -> Data,
        matchingDomains: [String],
        domainMatch: BrowserCookieDomainMatch) throws -> [CookieRecord]
    {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweet-cookie-kit-chrome-cookies-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let copiedDB = tempDir.appendingPathComponent("Cookies")
        try FileManager.default.copyItem(at: sourceDB, to: copiedDB)

        for suffix in ["-wal", "-shm"] {
            let src = URL(fileURLWithPath: sourceDB.path + suffix)
            if FileManager.default.fileExists(atPath: src.path) {
                let dst = URL(fileURLWithPath: copiedDB.path + suffix)
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }

        defer { try? FileManager.default.removeItem(at: tempDir) }

        return try Self.readCookies(
            fromDB: copiedDB.path,
            keyProvider: keyProvider,
            matchingDomains: matchingDomains,
            domainMatch: domainMatch)
    }

    // MARK: - SQLite read

    private static func readCookies(
        fromDB path: String,
        keyProvider: () throws -> Data,
        matchingDomains: [String],
        domainMatch: BrowserCookieDomainMatch) throws -> [CookieRecord]
    {
        var db: OpaquePointer?
        // Only the disposable copy is writable, so SQLite can recreate missing WAL sidecars.
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
            throw ImportError.sqliteFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_close(db) }

        let databaseVersion = try Self.cookieDatabaseVersion(db)

        let conditions = BrowserCookieDomainMatcher.sqlCondition(
            column: "host_key",
            patterns: matchingDomains,
            match: domainMatch)
        let sql = """
        SELECT host_key, name, path, expires_utc, is_secure, is_httponly, value, encrypted_value
        FROM cookies
        WHERE \(conditions)
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw ImportError.sqliteFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var key: Data?
        var out: [CookieRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let hostKey = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let path = String(cString: sqlite3_column_text(stmt, 2))
            let expires = sqlite3_column_int64(stmt, 3)
            let isSecure = sqlite3_column_int(stmt, 4) != 0
            let isHTTPOnly = sqlite3_column_int(stmt, 5) != 0

            let plain = Self.readTextColumn(stmt, index: 6)
            let enc = Self.readBlobColumn(stmt, index: 7)

            let value: String
            if let plain, !plain.isEmpty {
                value = plain
            } else if let enc, !enc.isEmpty {
                // Only request Safe Storage after host filtering finds a value that needs decryption.
                let decryptionKey = try key ?? keyProvider()
                key = decryptionKey
                guard let decrypted = Self.decryptChromiumValue(
                    enc,
                    key: decryptionKey,
                    hostKey: hostKey,
                    databaseVersion: databaseVersion)
                else { continue }
                value = decrypted
            } else {
                continue
            }

            out.append(CookieRecord(
                hostKey: hostKey,
                name: name,
                path: path,
                expiresUTC: expires,
                isSecure: isSecure,
                isHTTPOnly: isHTTPOnly,
                value: value))
        }
        return out
    }

    private static func cookieDatabaseVersion(_ db: OpaquePointer?) throws -> Int {
        let sql = "SELECT value FROM meta WHERE key = 'version'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ImportError.sqliteFailed(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw ImportError.sqliteFailed(message: "Chromium cookie database version is missing.")
        }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private static func readTextColumn(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    private static func readBlobColumn(_ stmt: OpaquePointer?, index: Int32) -> Data? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: bytes, count: count)
    }

    // MARK: - Keychain + crypto

    static func chromeSafeStorageKey(for browser: Browser) throws -> Data {
        try self.chromeSafeStorageKey(for: browser, passwordLookup: self.findGenericPassword)
    }

    typealias SafeStoragePasswordLookup =
        @Sendable (_ service: String, _ account: String, _ allowInteraction: Bool) -> (
            status: OSStatus,
            password: String?)

    static func chromeSafeStorageKey(
        for browser: Browser,
        labels overrideLabels: [(service: String, account: String)]? = nil,
        passwordLookup rawLookup: @escaping SafeStoragePasswordLookup) throws -> Data
    {
        if BrowserCookieKeychainAccessGate.isDisabled {
            throw ImportError.keychainDenied
        }

        self.chromeSafeStorageKeyLock.lock()
        if let cached = self.cachedChromeSafeStorageKeys[browser] {
            self.chromeSafeStorageKeyLock.unlock()
            return cached
        }
        self.chromeSafeStorageKeyLock.unlock()

        let selection = Self.selectSafeStorageLabel(
            overrideLabels ?? Self.safeStorageLabels(for: browser),
            passwordLookup: rawLookup)
        let labels = selection.labels
        if let context = selection.promptContext {
            BrowserCookieKeychainPromptHandler.handler?(context)
        }

        func passwordLookup(
            _ service: String,
            _ account: String,
            _: Bool) -> (status: OSStatus, password: String?)
        {
            rawLookup(service, account, selection.allowInteraction)
        }

        var password: String?
        for label in labels {
            let result = passwordLookup(label.service, label.account, true)
            if let p = result.password {
                password = p
                break
            }
        }
        guard let password else { throw ImportError.keychainDenied }

        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let keyLength = key.count
        let result = key.withUnsafeMutableBytes { keyBytes in
            password.utf8CString.withUnsafeBytes { passBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.bindMemory(to: Int8.self).baseAddress,
                        passBytes.count - 1,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength)
                }
            }
        }
        guard result == kCCSuccess else {
            throw ImportError.keychainDenied
        }

        self.chromeSafeStorageKeyLock.lock()
        self.cachedChromeSafeStorageKeys[browser] = key
        self.chromeSafeStorageKeyLock.unlock()
        return key
    }

    static func resetSafeStorageKeyCacheForTesting() {
        self.chromeSafeStorageKeyLock.lock()
        self.cachedChromeSafeStorageKeys = [:]
        self.chromeSafeStorageKeyLock.unlock()
    }

    /// Exposed for tests.
    static func decryptChromiumValue(
        _ encryptedValue: Data,
        key: Data,
        hostKey: String,
        databaseVersion: Int) -> String?
    {
        guard encryptedValue.count > 3 else { return nil }
        let prefix = encryptedValue.prefix(3)
        guard String(data: prefix, encoding: .utf8) == "v10" else { return nil }
        let payload = Data(encryptedValue.dropFirst(3))

        let legacyIV = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        guard let decrypted = Self.decryptCBC(payload, iv: legacyIV, key: key) else {
            return nil
        }

        let value: Data
        if databaseVersion >= 24 {
            let expectedDomainHash = Data(SHA256.hash(data: Data(hostKey.utf8)))
            guard decrypted.starts(with: expectedDomainHash) else { return nil }
            value = Data(decrypted.dropFirst(expectedDomainHash.count))
        } else {
            value = decrypted
        }

        return String(data: value, encoding: .utf8)
    }

    private static func decryptCBC(_ ciphertext: Data, iv: Data, key: Data) -> Data? {
        guard !ciphertext.isEmpty, ciphertext.count.isMultiple(of: kCCBlockSizeAES128) else {
            return nil
        }
        var out = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var outLength: size_t = 0
        let outCapacity = out.count
        let status = out.withUnsafeMutableBytes { outBytes in
            ciphertext.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inBytes.baseAddress,
                            ciphertext.count,
                            outBytes.baseAddress,
                            outCapacity,
                            &outLength)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.count = outLength
        return out
    }

    private struct SafeStorageSelection {
        let labels: [(service: String, account: String)]
        let allowInteraction: Bool
        let promptContext: BrowserCookieKeychainPromptContext?
    }

    private static func selectSafeStorageLabel(
        _ labels: [(service: String, account: String)],
        passwordLookup: SafeStoragePasswordLookup) -> SafeStorageSelection
    {
        var interactionRequired: (service: String, account: String)?
        for label in labels {
            let result = passwordLookup(label.service, label.account, false)
            if result.password != nil {
                return SafeStorageSelection(labels: [label], allowInteraction: false, promptContext: nil)
            }
            if result.status == errSecInteractionNotAllowed, interactionRequired == nil {
                interactionRequired = label
            }
        }

        guard !BrowserCookieKeychainAccessGate.isUserInteractionDisallowed,
              let interactionRequired
        else {
            return SafeStorageSelection(labels: [], allowInteraction: false, promptContext: nil)
        }
        // Trying another gated alias after any failure could open a second authorization prompt.
        return SafeStorageSelection(
            labels: [interactionRequired],
            allowInteraction: true,
            promptContext: BrowserCookieKeychainPromptContext(
                service: interactionRequired.service,
                account: interactionRequired.account,
                label: interactionRequired.service))
    }

    private static func safeStorageLabels(for browser: Browser) -> [(service: String, account: String)] {
        let labels = browser.safeStorageLabels
        if !labels.isEmpty {
            return labels
        }
        return BrowserCatalog.safeStorageLabels
    }

    private static func findGenericPassword(
        service: String,
        account: String,
        allowInteraction: Bool) -> (status: OSStatus, password: String?)
    {
        let query = self.makeGenericPasswordQuery(
            service: service,
            account: account,
            allowInteraction: allowInteraction)

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return (status, nil) }
        guard let data = result as? Data else { return (status, nil) }
        let password = String(data: data, encoding: .utf8)
        return (status, password)
    }

    static func makeGenericPasswordQuery(
        service: String,
        account: String,
        allowInteraction: Bool) -> [String: Any]
    {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        if !allowInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
            query[kSecUseAuthenticationUI as String] = self.authenticationUIFailPolicy as CFString
        }
        return query
    }

    private static let authenticationUIFailPolicy: String = {
        let securityPath = "/System/Library/Frameworks/Security.framework/Security"
        guard let handle = dlopen(securityPath, RTLD_NOW) else {
            return "u_AuthUIF"
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "kSecUseAuthenticationUIFail") else {
            return "u_AuthUIF"
        }
        let valuePointer = symbol.assumingMemoryBound(to: CFString?.self)
        return (valuePointer.pointee as String?) ?? "u_AuthUIF"
    }()

    // MARK: - Profile discovery

    private struct ChromeProfileCandidate {
        let browser: Browser
        let profile: BrowserProfile
        let kind: BrowserCookieStoreKind
        let label: String
        let cookiesDB: URL
    }

    private static func chromeProfileCookieDBs(
        root: URL,
        labelPrefix: String,
        browser: Browser) -> [ChromeProfileCandidate]
    {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        var profileDirs = entries.filter { url in
            guard let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory), isDir else {
                return false
            }
            let name = url.lastPathComponent
            return name == "Default" || name.hasPrefix("Profile ") || name.hasPrefix("user-")
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        // Electron keeps its single cookie store directly in the application support root.
        if browser == .claudeDesktop {
            profileDirs = [root]
        }

        return profileDirs.flatMap { dir in
            let profileName = dir.lastPathComponent
            let profile = BrowserProfile(id: dir.path, name: profileName)
            let labelBase = "\(labelPrefix) \(profileName)"
            let cookiesDB = dir.appendingPathComponent("Cookies")
            let networkCookiesDB = dir.appendingPathComponent("Network").appendingPathComponent("Cookies")
            return [
                ChromeProfileCandidate(
                    browser: browser,
                    profile: profile,
                    kind: .network,
                    label: "\(labelBase) (Network)",
                    cookiesDB: networkCookiesDB),
                ChromeProfileCandidate(
                    browser: browser,
                    profile: profile,
                    kind: .primary,
                    label: labelBase,
                    cookiesDB: cookiesDB),
            ]
        }
    }
}
#endif
