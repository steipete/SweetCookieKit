import CommonCrypto
import Foundation
import Security
import Testing
@testable import SweetCookieKit

#if os(macOS)

@Suite(.serialized)
struct ChromeCookieImporterTests {
    @Test
    func `decrypt chromium value strips mac OSV 10 prefix`() {
        let key = Data(repeating: 0x11, count: kCCKeySizeAES128)
        let prefix = Data((0..<32).map { UInt8($0) })
        let value = Data([0x00]) + Data("hello".utf8)
        let plaintext = prefix + value

        let encrypted = Self.encryptAES128CBCPKCS7(plaintext: plaintext, key: key)
        let encoded = Data("v10".utf8) + encrypted

        let decrypted = ChromeCookieImporter.decryptChromiumValue(encoded, key: key)
        #expect(decrypted == "hello")
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

    private static func encryptAES128CBCPKCS7(plaintext: Data, key: Data) -> Data {
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
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
