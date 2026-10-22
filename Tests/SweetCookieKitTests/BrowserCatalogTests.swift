import Foundation
import Testing
@testable import SweetCookieKit

#if os(macOS)

struct BrowserCatalogTests {
    @Test(arguments: [
        ("aside", "Aside", "Aside", ("Aside Safe Storage", "Aside")),
        ("opera", "Opera", "com.operasoftware.Opera", ("Opera Safe Storage", "Opera")),
        ("operaNeon", "Opera Neon", "com.operasoftware.OperaNeon", ("Opera Safe Storage", "Opera")),
    ])
    func `additional Chromium browsers expose metadata and synthetic profile stores`(
        fixture: (String, String, String, (String, String))) throws
    {
        let (id, name, path, (service, account)) = fixture
        let browser = try #require(Browser(rawValue: id))
        #expect(browser.displayName == name)
        #expect(browser.appBundleName == name)
        #expect(browser.chromiumProfileRelativePath == path)
        #expect(browser.safeStorageLabels.map(\.service) == [service])
        #expect(browser.safeStorageLabels.map(\.account) == [account])
        #expect(Browser.defaultImportOrder.contains(browser))
        #expect(Browser.safeStorageLabels.contains { $0.service == service && $0.account == account })

        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = try #require(ChromiumProfileLocator.roots(for: [browser], homeDirectories: [home]).first)
        #expect(root.url == home.appendingPathComponent("Library/Application Support/\(path)"))
        for profile in ["Default", "Profile 1"] {
            let directory = root.url.appendingPathComponent(profile)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent("Cookies"))
        }
        let stores = BrowserCookieClient(configuration: .init(homeDirectories: [home])).stores(for: browser)
        #expect(Set(stores.map(\.profile.name)) == Set(["Default", "Profile 1"]))
        #expect(stores.allSatisfy { $0.browser == browser })
    }

    @Test
    func `metadata covers all browsers`() {
        #expect(BrowserCatalog.metadataByBrowser.count == Browser.allCases.count)

        for browser in Browser.allCases {
            let metadata = BrowserCatalog.metadata(for: browser)
            #expect(!metadata.displayName.isEmpty)
        }
    }

    @Test
    func `default import order contains browsers but not opt-in desktop applications`() {
        let order = BrowserCatalog.defaultImportOrder
        #expect(order.count == Browser.allCases.count - 1)
        #expect(Set(order) == Set(Browser.allCases.filter { $0 != .claudeDesktop }))
        #expect(Set(order).count == order.count)
    }

    @Test
    func `chromium profile relative path present for chromium`() {
        for browser in Browser.allCases where browser.engine == .chromium {
            let path = BrowserCatalog.metadata(for: browser).chromiumProfileRelativePath
            #expect(path != nil)
        }
    }

    @Test
    func `gecko profiles folder present for gecko`() {
        for browser in Browser.allCases where browser.engine == .gecko {
            let folder = BrowserCatalog.metadata(for: browser).geckoProfilesFolder
            #expect(folder != nil)
        }
    }

    @Test
    func `gecko profiles folder expected names`() {
        #expect(BrowserCatalog.metadata(for: .firefox).geckoProfilesFolder == "Firefox")
        #expect(BrowserCatalog.metadata(for: .firefoxBeta).geckoProfilesFolder == "Firefox")
        #expect(BrowserCatalog.metadata(for: .firefoxDeveloperEdition).geckoProfilesFolder == "Firefox")
        #expect(BrowserCatalog.metadata(for: .firefoxNightly).geckoProfilesFolder == "Firefox")
        #expect(BrowserCatalog.metadata(for: .zen).geckoProfilesFolder == "zen")
    }

    @Test
    func `firefox channels select profiles by remoting name`() {
        #expect(BrowserCatalog.metadata(for: .firefox).geckoProfileSelection ==
            .remotingNames(["firefox", "firefox-esr"], includeUnidentified: true))
        #expect(BrowserCatalog.metadata(for: .firefoxBeta).geckoProfileSelection ==
            .remotingNames(["firefox-beta"], includeUnidentified: false))
        #expect(BrowserCatalog.metadata(for: .firefoxDeveloperEdition).geckoProfileSelection ==
            .remotingNames(["firefox-dev"], includeUnidentified: false))
        #expect(BrowserCatalog.metadata(for: .firefoxNightly).geckoProfileSelection ==
            .remotingNames(["firefox-nightly"], includeUnidentified: false))
        #expect(BrowserCatalog.metadata(for: .zen).geckoProfileSelection == .all)
    }

    @Test
    func `safe storage labels include known services`() {
        let labels = BrowserCatalog.safeStorageLabels.map { "\($0.service)|\($0.account)" }
        #expect(labels.contains("Chrome Safe Storage|Chrome"))
        #expect(labels.contains("Helium Storage Key|Helium"))
        #expect(labels.contains("Dia Safe Storage|Dia"))
        #expect(labels.contains("ChatGPT Atlas Safe Storage|ChatGPT Atlas"))
        #expect(labels.contains("Yandex Safe Storage|Yandex"))
        #expect(labels.contains("Comet Safe Storage|Comet"))
        #expect(labels.contains("ego safe storage|ego"))
    }

    @Test
    func `ego lite metadata points at Chromium profile and safe storage`() {
        #expect(Browser.egoLite.displayName == "Ego Lite")
        #expect(Browser.egoLite.appBundleName == "ego lite")
        #expect(Browser.egoLite.chromiumProfileRelativePath == "Citro Labs/ego lite")
        #expect(Browser.egoLite.usesChromiumProfileStore)
        let labels = Browser.egoLite.safeStorageLabels.map { "\($0.service)|\($0.account)" }
        #expect(labels == ["ego safe storage|ego"])
    }

    @Test
    func `app bundle name overrides for known browsers`() {
        #expect(Browser.chrome.appBundleName == "Google Chrome")
        #expect(Browser.chromeBeta.appBundleName == "Google Chrome Beta")
        #expect(Browser.chromeCanary.appBundleName == "Google Chrome Canary")
        #expect(Browser.brave.appBundleName == "Brave Browser")
        #expect(Browser.braveNightly.appBundleName == "Brave Browser Nightly")
        #expect(Browser.yandex.appBundleName == "Yandex")
        #expect(Browser.firefoxBeta.appBundleName == "Firefox")
        #expect(Browser.firefoxDeveloperEdition.appBundleName == "Firefox Developer Edition")
        #expect(Browser.firefoxNightly.appBundleName == "Firefox Nightly")
        #expect(Browser.safari.appBundleName == "Safari")
    }

    @Test
    func `browser metadata helpers expose profile roots`() {
        #expect(Browser.chrome.chromiumProfileRelativePath == "Google/Chrome")
        #expect(Browser.yandex.chromiumProfileRelativePath == "Yandex/YandexBrowser")
        #expect(Browser.comet.chromiumProfileRelativePath == "Comet")
        #expect(Browser.firefox.geckoProfilesFolder == "Firefox")
        #expect(Browser.firefoxBeta.geckoProfilesFolder == "Firefox")
        #expect(Browser.firefoxDeveloperEdition.geckoProfilesFolder == "Firefox")
        #expect(Browser.firefoxNightly.geckoProfilesFolder == "Firefox")
        #expect(Browser.zen.geckoProfilesFolder == "zen")
        #expect(Browser.safari.chromiumProfileRelativePath == nil)
    }

    @Test
    func `browser metadata helpers expose safe storage labels`() {
        let chromeLabels = Browser.chrome.safeStorageLabels.map { "\($0.service)|\($0.account)" }
        #expect(chromeLabels.contains("Chrome Safe Storage|Chrome"))
        #expect(Browser.helium.safeStorageLabels.first?.service == "Helium Storage Key")
        let yandexLabels = Browser.yandex.safeStorageLabels.map { "\($0.service)|\($0.account)" }
        #expect(yandexLabels.contains("Yandex Safe Storage|Yandex"))
        #expect(Browser.safari.safeStorageLabels.isEmpty)
    }

    @Test
    func `chrome dev joins the chrome channel group after the principal browsers`() throws {
        #expect(Browser.chromeDev.displayName == "Chrome Dev")
        #expect(Browser.chromeDev.appBundleName == "Google Chrome Dev")
        #expect(Browser.chromeDev.chromiumProfileRelativePath == "Google/Chrome Dev")
        #expect(Browser.chromeDev.usesChromiumProfileStore)
        let labels = Browser.chromeDev.safeStorageLabels.map { "\($0.service)|\($0.account)" }
        #expect(labels == ["Chrome Safe Storage|Chrome"])

        let order = Browser.defaultImportOrder
        let devIndex = try #require(order.firstIndex(of: .chromeDev))
        let canaryIndex = try #require(order.firstIndex(of: .chromeCanary))
        let betaIndex = try #require(order.firstIndex(of: .chromeBeta))
        let edgeIndex = try #require(order.firstIndex(of: .edge))
        // Chrome Dev sits with the other Chrome channels, after the principal browsers.
        #expect(betaIndex < canaryIndex && canaryIndex + 1 == devIndex)
        #expect(edgeIndex < betaIndex)
    }

    @Test
    func `chrome dev discovers synthetic chromium profile stores`() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = try #require(
            ChromiumProfileLocator.roots(for: [.chromeDev], homeDirectories: [home]).first)
        #expect(root.url == home.appendingPathComponent("Library/Application Support/Google/Chrome Dev"))
        for profile in ["Default", "Profile 1"] {
            let directory = root.url.appendingPathComponent(profile)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent("Cookies"))
        }
        let stores = BrowserCookieClient(configuration: .init(homeDirectories: [home])).stores(for: .chromeDev)
        #expect(Set(stores.map(\.profile.name)) == Set(["Default", "Profile 1"]))
        #expect(stores.allSatisfy { $0.browser == .chromeDev })
    }

    @Test
    func `explicit browser selection by rawValue is retained after chrome dev upgrade`() throws {
        // Simulate a downstream consumer (e.g., CodexBar) that stored an explicit
        // browser selection as a rawValue string before Chrome Dev existed.
        let storedBrowserID = "chrome"

        // After upgrading to a version with Chrome Dev, filtering the default order
        // by the stored rawValue should still yield only Chrome.
        let order = Browser.defaultImportOrder
        let filtered = order.filter { $0.rawValue == storedBrowserID }
        #expect(filtered == [.chrome])
        #expect(!filtered.contains(.chromeDev))

        // Chrome Dev should be present in the unfiltered order (proving it was added).
        #expect(order.contains(.chromeDev))

        // And grouped with other Chrome channels after the principal browsers.
        let chromeIndex = try #require(order.firstIndex(of: .chrome))
        let betaIndex = try #require(order.firstIndex(of: .chromeBeta))
        let canaryIndex = try #require(order.firstIndex(of: .chromeCanary))
        let devIndex = try #require(order.firstIndex(of: .chromeDev))
        #expect(chromeIndex < betaIndex)
        #expect(betaIndex < canaryIndex)
        #expect(canaryIndex < devIndex)
    }
}

#endif
