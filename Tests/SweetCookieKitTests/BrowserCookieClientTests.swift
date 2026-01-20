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
        let order = Browser.defaultImportOrder
        #expect(order.first == .safari)
        #expect(order.contains(.chrome))
        #expect(order.contains(.firefox))
        #expect(order.contains(.zen))
        #expect(Set(order).count == order.count)

        let shortList: [Browser] = [.safari, .chrome, .firefox]
        #expect(shortList.displayLabel == "Safari → Chrome → Firefox")
        #expect(shortList.shortLabel == "Safari/Chrome/Firefox")
        #expect(shortList.loginHint == "Safari, Chrome, or Firefox")
    }

    @Test
    func browserCookieQuery_defaults() {
        let query = BrowserCookieQuery()
        #expect(query.domains.isEmpty)
        #expect(query.domainMatch == .contains)
        #expect(query.includeExpired == false)
    }
}

#endif
