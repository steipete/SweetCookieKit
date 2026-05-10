import Testing
@testable import SweetCookieKit

#if os(macOS)

struct BrowserCatalogTests {
    @Test
    func `metadata covers all browsers`() {
        #expect(BrowserCatalog.metadataByBrowser.count == Browser.allCases.count)

        for browser in Browser.allCases {
            let metadata = BrowserCatalog.metadata(for: browser)
            #expect(!metadata.displayName.isEmpty)
        }
    }

    @Test
    func `default import order contains all browsers`() {
        let order = BrowserCatalog.defaultImportOrder
        #expect(order.count == Browser.allCases.count)
        #expect(Set(order) == Set(Browser.allCases))
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
        #expect(BrowserCatalog.metadata(for: .zen).geckoProfilesFolder == "zen")
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
    }

    @Test
    func `app bundle name overrides for known browsers`() {
        #expect(Browser.chrome.appBundleName == "Google Chrome")
        #expect(Browser.chromeBeta.appBundleName == "Google Chrome Beta")
        #expect(Browser.chromeCanary.appBundleName == "Google Chrome Canary")
        #expect(Browser.brave.appBundleName == "Brave Browser")
        #expect(Browser.braveNightly.appBundleName == "Brave Browser Nightly")
        #expect(Browser.yandex.appBundleName == "Yandex")
        #expect(Browser.safari.appBundleName == "Safari")
    }

    @Test
    func `browser metadata helpers expose profile roots`() {
        #expect(Browser.chrome.chromiumProfileRelativePath == "Google/Chrome")
        #expect(Browser.yandex.chromiumProfileRelativePath == "Yandex/YandexBrowser")
        #expect(Browser.comet.chromiumProfileRelativePath == "Comet")
        #expect(Browser.firefox.geckoProfilesFolder == "Firefox")
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
}

#endif
