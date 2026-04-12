import CommonCrypto
import Foundation
import Security
import Testing
@testable import SweetCookieKit

#if os(macOS)

@Suite
struct ChromeCookieImporterTests {
    @Test
    func decryptChromiumValue_stripsMacOSV10Prefix() {
        let key = Data(repeating: 0x11, count: kCCKeySizeAES128)
        let prefix = Data((0..<32).map { UInt8($0) })
        let value = Data([0x00]) + Data("hello".utf8)
        let plaintext = prefix + value

        let encrypted = Self.encryptAES128CBCPKCS7(plaintext: plaintext, key: key)
        let encoded = Data("v10".utf8) + encrypted

        let decrypted = ChromeCookieImporter.decryptChromiumValue(encoded, key: key)
        #expect(decrypted == "hello")
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

    @Test
    func chromeSafeStorageKey_usesBrowserSpecificLabels() throws {
        let recorder = LabelRecorder()
        let key = try ChromeCookieImporter.chromeSafeStorageKey(
            for: .yandex,
            passwordLookup: { service, account, allowInteraction in
                recorder.record(service: service, account: account, allowInteraction: allowInteraction)
                return (status: errSecSuccess, password: "dummy-safe-storage-password")
            })

        #expect(key.count == kCCKeySizeAES128)
        #expect(recorder.snapshot().map { "\($0.service)|\($0.account)|\($0.allowInteraction)" } == [
            "Yandex Safe Storage|Yandex|false",
            "Yandex Safe Storage|Yandex|true",
        ])
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
