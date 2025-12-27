import Foundation
import Testing
@testable import SweetCookieKit

#if os(macOS)

@Suite
struct BrowserCookieClientTests {
    @Test
    func makeHTTPCookies_setsExpectedFields() {
        let record = BrowserCookieRecord(
            domain: ".example.com",
            name: "session",
            path: "/",
            value: "abc",
            expires: Date(timeIntervalSince1970: 1_700_000_000),
            isSecure: true,
            isHTTPOnly: true)

        let cookies = BrowserCookieClient.makeHTTPCookies([record])
        #expect(cookies.count == 1)
        guard let cookie = cookies.first else { return }
        #expect(cookie.domain == "example.com")
        #expect(cookie.name == "session")
        #expect(cookie.path == "/")
        #expect(cookie.value == "abc")
        #expect(cookie.isSecure)
        #expect(cookie.isHTTPOnly)
    }

    @Test
    func browserCookieImportOrder_labels() {
        let order = BrowserCookieImportOrder.safariChromeFirefox
        #expect(order.browsers == [.safari, .chrome, .firefox])
        #expect(order.displayLabel == "Safari → Chrome → Firefox")
        #expect(order.shortLabel == "Safari/Chrome/Firefox")
        #expect(order.loginHint == "Safari, Chrome, or Firefox")
    }
}

#endif
