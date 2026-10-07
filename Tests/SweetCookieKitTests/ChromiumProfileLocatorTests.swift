import Foundation
import Testing
@testable import SweetCookieKit

#if os(macOS)

@Suite
struct ChromiumProfileLocatorTests {
    @Test
    func chromiumRelativePath_mapsHelium() {
        #expect(ChromiumProfileLocator.chromiumRelativePath(for: .helium) == "net.imput.helium")
    }

    @Test
    func chromiumRelativePath_returnsNilForNonChromium() {
        #expect(ChromiumProfileLocator.chromiumRelativePath(for: .safari) == nil)
        #expect(ChromiumProfileLocator.chromiumRelativePath(for: .firefox) == nil)
        #expect(ChromiumProfileLocator.chromiumRelativePath(for: .zen) == nil)
    }

    @Test
    func chromiumRelativePath_mapsDia() {
        #expect(ChromiumProfileLocator.chromiumRelativePath(for: .dia) == "Dia/User Data")
    }

    @Test
    func chromiumRelativePath_mapsEgoLite() {
        #expect(ChromiumProfileLocator.chromiumRelativePath(for: .egoLite) == "Citro Labs/ego lite")
    }

    @Test
    func roots_dedupesHomesAndBuildsExpectedPaths() {
        let home = URL(fileURLWithPath: "/Users/test")
        let roots = ChromiumProfileLocator.roots(
            for: [.chrome, .helium],
            homeDirectories: [home, home])

        #expect(roots.count == 2)

        let chromePath = roots.first { $0.browser == .chrome }?.url.path
        #expect(chromePath == "/Users/test/Library/Application Support/Google/Chrome")

        let heliumPath = roots.first { $0.browser == .helium }?.url.path
        #expect(heliumPath == "/Users/test/Library/Application Support/net.imput.helium")
    }
}

#endif
