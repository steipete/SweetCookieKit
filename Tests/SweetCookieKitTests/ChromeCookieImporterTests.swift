import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import Security
import SQLite3
import Testing
@testable import SweetCookieKit

#if os(macOS)

@Suite(.serialized)
struct ChromeCookieImporterTests {
    @Test
    func egoLitePublicClientDiscoversProfilesAndDecryptsCookies() throws {
        ChromeCookieImporter.resetSafeStorageKeyCacheForTesting()
        let wasDisabled = BrowserCookieKeychainAccessGate.isDisabled
        BrowserCookieKeychainAccessGate.isDisabled = false
        defer {
            ChromeCookieImporter.resetSafeStorageKeyCacheForTesting()
            BrowserCookieKeychainAccessGate.isDisabled = wasDisabled
        }

        let recorder = LabelRecorder()
        // Seed the existing cache through the injected lookup; never access the user's Keychain.
        let key = try ChromeCookieImporter.chromeSafeStorageKey(for: .egoLite) { service, account, allowInteraction in
            recorder.record(service: service, account: account, allowInteraction: allowInteraction)
            guard service == "ego safe storage", account == "ego", !allowInteraction else {
                return (status: errSecItemNotFound, password: nil)
            }
            return (status: errSecSuccess, password: "synthetic-ego-password")
        }
        #expect(recorder.snapshot().map { "\($0.service)|\($0.account)|\($0.allowInteraction)" } == [
            "ego safe storage|ego|false",
            "ego safe storage|ego|false",
        ])

        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Library/Application Support/Citro Labs/ego lite")
        let profiles = ["Default", "Profile 1", "Profile 2", "Profile 3", "Profile 4", "Profile 5"]
        let hostKey = ".example.com"
        let plaintext = Data(SHA256.hash(data: Data(hostKey.utf8))) + Data("synthetic-session".utf8)
        let encrypted = Data("v10".utf8) + Self.encryptAES128CBCPKCS7(plaintext: plaintext, key: key)
        for (index, profile) in profiles.enumerated() {
            let relativePath = index.isMultiple(of: 2) ? "Cookies" : "Network/Cookies"
            try Self.writeChromiumCookieDatabase(
                at: root.appendingPathComponent(profile).appendingPathComponent(relativePath),
                encryptedValue: encrypted)
        }

        let client = BrowserCookieClient(configuration: .init(homeDirectories: [home]))
        let stores = client.stores(for: .egoLite)
        #expect(stores.count == profiles.count)
        #expect(Set(stores.map(\.profile.name)) == Set(profiles))
        #expect(stores.allSatisfy { $0.browser == .egoLite })
        #expect(stores.filter { $0.kind == .primary }.count == 3)
        #expect(stores.filter { $0.kind == .network }.count == 3)
        #expect(Browser.defaultImportOrder.contains(.egoLite))

        try BrowserCookieKeychainAccessGate.withUserInteractionDisallowed {
            for store in stores {
                let records = try client.records(
                    matching: .init(domains: ["example.com"], domainMatch: .suffix), in: store)
                #expect(records.count == 1)
                let record = try #require(records.first)
                #expect(record.domain == "example.com")
                #expect(record.scope == .domain)
                #expect(record.name == "session")
                #expect(record.value == "synthetic-session")
                #expect(record.isSecure && record.isHTTPOnly)
                #expect(try client.records(matching: .init(domains: ["other.example"]), in: store).isEmpty)
            }
        }
    }

    @Test
    func `noninteractive safe storage query explicitly fails authentication UI`() {
        let query = ChromeCookieImporter.makeGenericPasswordQuery(
            service: "Comet Safe Storage",
            account: "Comet",
            allowInteraction: false)
        let interactiveQuery = ChromeCookieImporter.makeGenericPasswordQuery(
            service: "Comet Safe Storage",
            account: "Comet",
            allowInteraction: true)

        let context = query[kSecUseAuthenticationContext as String] as? LAContext
        #expect(context?.interactionNotAllowed == true)
        #expect((query[kSecUseAuthenticationUI as String] as? String) == "u_AuthUIF")
        #expect(interactiveQuery[kSecUseAuthenticationContext as String] == nil)
        #expect(interactiveQuery[kSecUseAuthenticationUI as String] == nil)
    }

    @Test
    func `version 24 values validate and strip the domain hash`() {
        let key = Data(repeating: 0x11, count: kCCKeySizeAES128)
        let hostKey = ".example.com"
        let domainHash = Data(SHA256.hash(data: Data(hostKey.utf8)))
        let plaintext = domainHash + Data("hello".utf8)

        let encrypted = Self.encryptAES128CBCPKCS7(plaintext: plaintext, key: key)
        let encoded = Data("v10".utf8) + encrypted

        let decrypted = ChromeCookieImporter.decryptChromiumValue(
            encoded,
            key: key,
            hostKey: hostKey,
            databaseVersion: 24)
        #expect(decrypted == "hello")
    }

    @Test
    func `version 24 values reject a mismatched domain hash`() {
        let key = Data(repeating: 0x22, count: kCCKeySizeAES128)
        let storedHostKey = ".example.com"
        let domainHash = Data(SHA256.hash(data: Data(storedHostKey.utf8)))
        let plaintext = domainHash + Data("session-value".utf8)

        let encrypted = Self.encryptAES128CBCPKCS7(plaintext: plaintext, key: key)
        let encoded = Data("v10".utf8) + encrypted

        let decrypted = ChromeCookieImporter.decryptChromiumValue(
            encoded,
            key: key,
            hostKey: ".other.example",
            databaseVersion: 24)
        #expect(decrypted == nil)
    }

    @Test
    func `pre version 24 values longer than 32 bytes are not truncated`() {
        let key = Data(repeating: 0x33, count: kCCKeySizeAES128)
        let plaintext = Data(String(repeating: "a", count: 60).utf8)

        let encrypted = Self.encryptAES128CBCPKCS7(plaintext: plaintext, key: key)
        let encoded = Data("v10".utf8) + encrypted

        let decrypted = ChromeCookieImporter.decryptChromiumValue(
            encoded,
            key: key,
            hostKey: ".example.com",
            databaseVersion: 23)
        #expect(decrypted == String(data: plaintext, encoding: .utf8))
    }

    @Test
    func `pre version 24 short values still decrypt`() {
        let key = Data(repeating: 0x44, count: kCCKeySizeAES128)
        let plaintext = Data("yes".utf8)

        let encrypted = Self.encryptAES128CBCPKCS7(plaintext: plaintext, key: key)
        let encoded = Data("v10".utf8) + encrypted

        let decrypted = ChromeCookieImporter.decryptChromiumValue(
            encoded,
            key: key,
            hostKey: ".example.com",
            databaseVersion: 23)
        #expect(decrypted == "yes")
    }

    @Test
    func `pre version 24 unicode values still decrypt`() {
        let key = Data(repeating: 0x45, count: kCCKeySizeAES128)
        let plaintext = Data("登录成功🍪".utf8)

        let encrypted = Self.encryptAES128CBCPKCS7(plaintext: plaintext, key: key)
        let encoded = Data("v10".utf8) + encrypted

        let decrypted = ChromeCookieImporter.decryptChromiumValue(
            encoded,
            key: key,
            hostKey: ".example.com",
            databaseVersion: 23)
        #expect(decrypted == String(data: plaintext, encoding: .utf8))
    }

    @Test
    func `version 24 unicode values still decrypt`() {
        let key = Data(repeating: 0x46, count: kCCKeySizeAES128)
        let hostKey = ".example.com"
        let value = Data("登录成功🍪".utf8)
        let domainHash = Data(SHA256.hash(data: Data(hostKey.utf8)))
        let plaintext = domainHash + value

        let encrypted = Self.encryptAES128CBCPKCS7(plaintext: plaintext, key: key)
        let encoded = Data("v10".utf8) + encrypted

        let decrypted = ChromeCookieImporter.decryptChromiumValue(
            encoded,
            key: key,
            hostKey: hostKey,
            databaseVersion: 24)
        #expect(decrypted == String(data: value, encoding: .utf8))
    }

    @Test
    func `version 24 domain hash is stripped without truncating a long value`() {
        let key = Data(repeating: 0x55, count: kCCKeySizeAES128)
        let hostKey = ".example.com"
        let domainHash = Data(SHA256.hash(data: Data(hostKey.utf8)))
        let value = Data("session-token-abcdefghijklmnopqrstuvwxyz-0123456789".utf8)
        let plaintext = domainHash + value

        let encrypted = Self.encryptAES128CBCPKCS7(plaintext: plaintext, key: key)
        let encoded = Data("v10".utf8) + encrypted

        let decrypted = ChromeCookieImporter.decryptChromiumValue(
            encoded,
            key: key,
            hostKey: hostKey,
            databaseVersion: 24)
        #expect(decrypted == String(data: value, encoding: .utf8))
    }

    @Test
    func `chrome safe storage key caches noninteractive reads per browser`() throws {
        ChromeCookieImporter.resetSafeStorageKeyCacheForTesting()
        BrowserCookieKeychainAccessGate.isDisabled = false
        let recorder = LabelRecorder()

        let lookup: ChromeCookieImporter.SafeStoragePasswordLookup = { service, account, allowInteraction in
            recorder.record(service: service, account: account, allowInteraction: allowInteraction)
            let password = switch account {
            case "Helium":
                "helium-password"
            case "Yandex":
                "yandex-password"
            default:
                "chrome-password"
            }
            return (status: errSecSuccess, password: password)
        }

        let yandexKey = try ChromeCookieImporter.chromeSafeStorageKey(for: .yandex, passwordLookup: lookup)
        let chromeKey = try ChromeCookieImporter.chromeSafeStorageKey(for: .chrome, passwordLookup: lookup)
        let heliumKey = try ChromeCookieImporter.chromeSafeStorageKey(for: .helium, passwordLookup: lookup)
        let cachedChromeKey = try ChromeCookieImporter.chromeSafeStorageKey(for: .chrome, passwordLookup: lookup)

        #expect(yandexKey.count == kCCKeySizeAES128)
        #expect(chromeKey == cachedChromeKey)
        #expect(yandexKey != chromeKey)
        #expect(chromeKey != heliumKey)
        #expect(recorder.snapshot().map { "\($0.service)|\($0.account)|\($0.allowInteraction)" } == [
            "Yandex Safe Storage|Yandex|false",
            "Yandex Safe Storage|Yandex|false",
            "Chrome Safe Storage|Chrome|false",
            "Chrome Safe Storage|Chrome|false",
            "Helium Storage Key|Helium|false",
            "Helium Storage Key|Helium|false",
        ])
    }

    @Test
    func `chrome safe storage key never upgrades a no interaction scope to interactive`() {
        ChromeCookieImporter.resetSafeStorageKeyCacheForTesting()
        BrowserCookieKeychainAccessGate.isDisabled = false
        let recorder = LabelRecorder()

        let lookup: ChromeCookieImporter.SafeStoragePasswordLookup = { service, account, allowInteraction in
            recorder.record(service: service, account: account, allowInteraction: allowInteraction)
            return (status: errSecInteractionNotAllowed, password: nil)
        }

        #expect(throws: ChromeCookieImporter.ImportError.self) {
            try BrowserCookieKeychainAccessGate.withUserInteractionDisallowed {
                try ChromeCookieImporter.chromeSafeStorageKey(for: .chrome, passwordLookup: lookup)
            }
        }
        #expect(recorder.snapshot().map(\.allowInteraction) == [false])
    }

    @Test
    func `chrome safe storage key finds a later noninteractive alias`() throws {
        ChromeCookieImporter.resetSafeStorageKeyCacheForTesting()
        BrowserCookieKeychainAccessGate.isDisabled = false
        let recorder = LabelRecorder()

        let lookup: ChromeCookieImporter.SafeStoragePasswordLookup = { service, account, allowInteraction in
            recorder.record(service: service, account: account, allowInteraction: allowInteraction)
            if service == "Second Safe Storage" {
                return (status: errSecSuccess, password: "second")
            }
            return (status: errSecInteractionNotAllowed, password: nil)
        }

        let key = try BrowserCookieKeychainAccessGate.withUserInteractionDisallowed {
            try ChromeCookieImporter.chromeSafeStorageKey(
                for: .chrome,
                labels: [
                    (service: "First Safe Storage", account: "First"),
                    (service: "Second Safe Storage", account: "Second"),
                ],
                passwordLookup: lookup)
        }

        #expect(key.count == kCCKeySizeAES128)
        #expect(recorder.snapshot().map(\.allowInteraction) == [false, false, false])
    }

    @Test
    func `no interaction scope accepts a later alias readable without UI`() throws {
        ChromeCookieImporter.resetSafeStorageKeyCacheForTesting()
        BrowserCookieKeychainAccessGate.isDisabled = false
        let recorder = LabelRecorder()

        let lookup: ChromeCookieImporter.SafeStoragePasswordLookup = { service, account, allowInteraction in
            recorder.record(service: service, account: account, allowInteraction: allowInteraction)
            guard !allowInteraction, service == "Second Safe Storage" else {
                return (status: errSecInteractionNotAllowed, password: nil)
            }
            return (status: errSecSuccess, password: "second")
        }

        let key = try BrowserCookieKeychainAccessGate.withUserInteractionDisallowed {
            try ChromeCookieImporter.chromeSafeStorageKey(
                for: .chrome,
                labels: [
                    (service: "First Safe Storage", account: "First"),
                    (service: "Second Safe Storage", account: "Second"),
                ],
                passwordLookup: lookup)
        }

        #expect(key.count == kCCKeySizeAES128)
        #expect(recorder.snapshot().map(\.service) == [
            "First Safe Storage",
            "Second Safe Storage",
            "Second Safe Storage",
        ])
        #expect(recorder.snapshot().map(\.allowInteraction) == [false, false, false])
    }

    @Test
    func `silently readable safe storage does not invoke the prompt handler`() throws {
        ChromeCookieImporter.resetSafeStorageKeyCacheForTesting()
        BrowserCookieKeychainAccessGate.isDisabled = false
        let promptRecorder = LabelRecorder()
        let originalHandler = BrowserCookieKeychainPromptHandler.handler
        BrowserCookieKeychainPromptHandler.handler = { _ in
            promptRecorder.record(service: "prompt", account: "handler")
        }
        defer { BrowserCookieKeychainPromptHandler.handler = originalHandler }

        let lookup: ChromeCookieImporter.SafeStoragePasswordLookup = { _, _, allowInteraction in
            #expect(!allowInteraction)
            return (status: errSecSuccess, password: "chrome")
        }

        let key = try ChromeCookieImporter.chromeSafeStorageKey(for: .chrome, passwordLookup: lookup)

        #expect(key.count == kCCKeySizeAES128)
        #expect(promptRecorder.snapshot().isEmpty)
    }

    @Test
    func `chrome safe storage key preserves interactive recovery by default`() throws {
        ChromeCookieImporter.resetSafeStorageKeyCacheForTesting()
        BrowserCookieKeychainAccessGate.isDisabled = false
        let recorder = LabelRecorder()

        let lookup: ChromeCookieImporter.SafeStoragePasswordLookup = { service, account, allowInteraction in
            recorder.record(service: service, account: account, allowInteraction: allowInteraction)
            if allowInteraction {
                return (status: errSecSuccess, password: "chrome")
            }
            return (status: errSecInteractionNotAllowed, password: nil)
        }

        let key = try ChromeCookieImporter.chromeSafeStorageKey(for: .chrome, passwordLookup: lookup)

        #expect(key.count == kCCKeySizeAES128)
        #expect(recorder.snapshot().map(\.allowInteraction) == [false, true])
    }

    @Test
    func `chrome safe storage key stops after one cancelled interactive lookup`() {
        ChromeCookieImporter.resetSafeStorageKeyCacheForTesting()
        BrowserCookieKeychainAccessGate.isDisabled = false
        let recorder = LabelRecorder()

        let lookup: ChromeCookieImporter.SafeStoragePasswordLookup = { service, account, allowInteraction in
            recorder.record(service: service, account: account, allowInteraction: allowInteraction)
            return allowInteraction
                ? (status: errSecUserCanceled, password: nil)
                : (status: errSecInteractionNotAllowed, password: nil)
        }

        #expect(throws: ChromeCookieImporter.ImportError.self) {
            _ = try ChromeCookieImporter.chromeSafeStorageKey(
                for: .chrome,
                labels: [
                    (service: "Chrome Safe Storage", account: "Chrome"),
                    (service: "Second Safe Storage", account: "Second"),
                ],
                passwordLookup: lookup)
        }
        #expect(recorder.snapshot().map(\.allowInteraction) == [false, false, true])
    }

    @Test
    func `chrome safe storage key stops after one failed interactive lookup`() {
        ChromeCookieImporter.resetSafeStorageKeyCacheForTesting()
        BrowserCookieKeychainAccessGate.isDisabled = false
        let recorder = LabelRecorder()

        let lookup: ChromeCookieImporter.SafeStoragePasswordLookup = { service, account, allowInteraction in
            recorder.record(service: service, account: account, allowInteraction: allowInteraction)
            if allowInteraction, service == "Second Safe Storage" {
                return (status: errSecSuccess, password: "ok")
            }
            return allowInteraction
                ? (status: errSecAuthFailed, password: nil)
                : (status: errSecInteractionNotAllowed, password: nil)
        }

        #expect(throws: ChromeCookieImporter.ImportError.self) {
            _ = try ChromeCookieImporter.chromeSafeStorageKey(
                for: .chrome,
                labels: [
                    (service: "Chrome Safe Storage", account: "Chrome"),
                    (service: "Second Safe Storage", account: "Second"),
                ],
                passwordLookup: lookup)
        }
        #expect(recorder.snapshot().map(\.service) == [
            "Chrome Safe Storage",
            "Second Safe Storage",
            "Chrome Safe Storage",
        ])
        #expect(recorder.snapshot().map(\.allowInteraction) == [false, false, true])
    }

    private static func writeChromiumCookieDatabase(at url: URL, encryptedValue: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        let result = sqlite3_open(url.path, &database)
        defer { sqlite3_close(database) }
        try #require(result == SQLITE_OK)
        let encryptedHex = encryptedValue.map { String(format: "%02x", $0) }.joined()
        let sql = """
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        INSERT INTO meta VALUES ('version', '24');
        CREATE TABLE cookies (
            host_key TEXT, name TEXT, path TEXT, expires_utc INTEGER,
            is_secure INTEGER, is_httponly INTEGER, value TEXT, encrypted_value BLOB);
        INSERT INTO cookies VALUES ('.example.com', 'session', '/', 0, 1, 1, '', X'\(encryptedHex)');
        """
        try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    }

    private static func encryptAES128CBCPKCS7(plaintext: Data, key: Data) -> Data {
        self.encryptAES128CBCPKCS7(plaintext: plaintext, key: key, iv: Data(repeating: 0x20, count: kCCBlockSizeAES128))
    }

    private static func encryptAES128CBCPKCS7(plaintext: Data, key: Data, iv: Data) -> Data {
        var out = Data(count: plaintext.count + kCCBlockSizeAES128)
        let outCapacity = out.count
        var outLength: size_t = 0

        let status = out.withUnsafeMutableBytes { outBytes in
            plaintext.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inBytes.baseAddress,
                            plaintext.count,
                            outBytes.baseAddress,
                            outCapacity,
                            &outLength)
                    }
                }
            }
        }

        #expect(status == kCCSuccess)
        out.count = outLength
        return out
    }
}

private final class LabelRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var labels: [(service: String, account: String, allowInteraction: Bool)] = []

    func record(service: String, account: String, allowInteraction: Bool = true) {
        self.lock.lock()
        self.labels.append((service: service, account: account, allowInteraction: allowInteraction))
        self.lock.unlock()
    }

    func snapshot() -> [(service: String, account: String, allowInteraction: Bool)] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.labels
    }
}

#endif
