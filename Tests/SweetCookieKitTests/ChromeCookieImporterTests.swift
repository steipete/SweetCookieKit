import CommonCrypto
import Foundation
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
}

#endif
