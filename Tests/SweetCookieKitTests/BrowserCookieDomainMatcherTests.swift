import Foundation
import Testing
@testable import SweetCookieKit

#if os(macOS)

@Suite
struct BrowserCookieDomainMatcherTests {
    @Test
    func normalizeDomain_stripsDotAndWhitespace() {
        #expect(BrowserCookieDomainMatcher.normalizeDomain(" .example.com ") == "example.com")
        #expect(BrowserCookieDomainMatcher.normalizeDomain("example.com") == "example.com")
    }

    @Test
    func matches_contains() {
        #expect(BrowserCookieDomainMatcher.matches(
            domain: "sub.example.com",
            patterns: ["example.com"],
            match: .contains))
        #expect(!BrowserCookieDomainMatcher.matches(
            domain: "sub.example.com",
            patterns: ["nope.com"],
            match: .contains))
    }

    @Test
    func matches_suffix() {
        #expect(BrowserCookieDomainMatcher.matches(
            domain: "sub.example.com",
            patterns: ["example.com"],
            match: .suffix))
        #expect(!BrowserCookieDomainMatcher.matches(
            domain: "sub.example.com",
            patterns: ["example.net"],
            match: .suffix))
    }

    @Test
    func matches_exact_normalizesLeadingDot() {
        #expect(BrowserCookieDomainMatcher.matches(domain: ".example.com", patterns: ["example.com"], match: .exact))
        #expect(!BrowserCookieDomainMatcher.matches(
            domain: "sub.example.com",
            patterns: ["example.com"],
            match: .exact))
    }

    @Test
    func filterExpired_excludesExpiredUnlessRequested() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fresh = BrowserCookieRecord(
            domain: "example.com",
            name: "a",
            path: "/",
            value: "1",
            expires: now.addingTimeInterval(60),
            isSecure: false,
            isHTTPOnly: false)
        let expired = BrowserCookieRecord(
            domain: "example.com",
            name: "b",
            path: "/",
            value: "2",
            expires: now.addingTimeInterval(-60),
            isSecure: false,
            isHTTPOnly: false)

        #expect(BrowserCookieDomainMatcher.filterExpired([fresh, expired], includeExpired: false, now: now)
            .map(\.name) == ["a"])
        #expect(BrowserCookieDomainMatcher.filterExpired([fresh, expired], includeExpired: true, now: now)
            .map(\.name) == [
                "a",
                "b",
            ])
    }

    @Test
    func sqlCondition_escapesQuotes() {
        let sql = BrowserCookieDomainMatcher.sqlCondition(
            column: "host_key",
            patterns: ["exa'mple.com"],
            match: .contains)
        #expect(sql.contains("exa''mple.com"))
    }

    @Test
    func sqlCondition_exactMatchesBothWithAndWithoutDot() {
        let sql = BrowserCookieDomainMatcher.sqlCondition(column: "host_key", patterns: ["example.com"], match: .exact)
        #expect(sql.contains("host_key = 'example.com'"))
        #expect(sql.contains("host_key = '.example.com'"))
    }

    @Test
    func chromeExpiryDate_roundTrips() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let expiresUTC = Int64((date.timeIntervalSince1970 + 11_644_473_600.0) * 1_000_000.0)
        let decoded = BrowserCookieDomainMatcher.chromeExpiryDate(expiresUTC: expiresUTC)
        #expect(decoded == date)
    }

    @Test
    func browserCookieError_mappers() {
        let safari = BrowserCookieError.mapSafariError(.cookieFileNotFound, browser: .safari)
        #expect(safari.browser == .safari)

        let chrome = BrowserCookieError.mapChromeError(.keychainDenied, browser: .chrome)
        let chromeIsAccessDenied = if case .accessDenied = chrome { true } else { false }
        #expect(chromeIsAccessDenied)

        let firefox = BrowserCookieError.mapFirefoxError(
            .cookieDBNotFound(path: "x", browser: .firefox),
            browser: .firefox)
        let firefoxIsNotFound = if case .notFound = firefox { true } else { false }
        #expect(firefoxIsNotFound)
    }
}

#endif
