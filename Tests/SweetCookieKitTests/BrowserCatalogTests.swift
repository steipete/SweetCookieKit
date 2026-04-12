import Testing
@testable import SweetCookieKit

#if os(macOS)

@Suite
struct BrowserCatalogTests {
    @Test
    func metadata_coversAllBrowsers() {
        #expect(BrowserCatalog.metadataByBrowser.count == Browser.allCases.count)

        for browser in Browser.allCases {
            let metadata = BrowserCatalog.metadata(for: browser)
            #expect(!metadata.displayName.isEmpty)
        }
    }

    @Test
    func defaultImportOrder_containsAllBrowsers() {
        let order = BrowserCatalog.defaultImportOrder
        #expect(order.count == Browser.allCases.count)
        #expect(Set(order) == Set(Browser.allCases))
        #expect(Set(order).count == order.count)
    }

    @Test
    func chromiumProfileRelativePath_presentForChromium() {
        for browser in Browser.allCases where browser.engine == .chromium {
            let path = BrowserCatalog.metadata(for: browser).chromiumProfileRelativePath
            #expect(path != nil)
        }
    }

    @Test
    func geckoProfilesFolder_presentForGecko() {
        for browser in Browser.allCases where browser.engine == .gecko {
            let folder = BrowserCatalog.metadata(for: browser).geckoProfilesFolder
            #expect(folder != nil)
        }
    }

    @Test
    func geckoProfilesFolder_expectedNames() {
        #expect(BrowserCatalog.metadata(for: .firefox).geckoProfilesFolder == "Firefox")
        #expect(BrowserCatalog.metadata(for: .zen).geckoProfilesFolder == "zen")
    }

    @Test
    func safeStorageLabels_includeKnownServices() {
        let labels = BrowserCatalog.safeStorageLabels.map { "\($0.service)|\($0.account)" }
        #expect(labels.contains("Chrome Safe Storage|Chrome"))
        #expect(labels.contains("Dia Safe Storage|Dia"))
        #expect(labels.contains("ChatGPT Atlas Safe Storage|ChatGPT Atlas"))
        #expect(labels.contains("Yandex Safe Storage|Yandex"))
    }

    @Test
    func appBundleName_overridesForKnownBrowsers() {
        #expect(Browser.chrome.appBundleName == "Google Chrome")
        #expect(Browser.chromeBeta.appBundleName == "Google Chrome Beta")
        #expect(Browser.chromeCanary.appBundleName == "Google Chrome Canary")
        #expect(Browser.brave.appBundleName == "Brave Browser")
        #expect(Browser.braveNightly.appBundleName == "Brave Browser Nightly")
        #expect(Browser.yandex.appBundleName == "Yandex")
        #expect(Browser.safari.appBundleName == "Safari")
    }

    @Test
    func browserMetadata_helpersExposeProfileRoots() {
        #expect(Browser.chrome.chromiumProfileRelativePath == "Google/Chrome")
        #expect(Browser.yandex.chromiumProfileRelativePath == "Yandex/YandexBrowser")
        #expect(Browser.firefox.geckoProfilesFolder == "Firefox")
        #expect(Browser.zen.geckoProfilesFolder == "zen")
        #expect(Browser.safari.chromiumProfileRelativePath == nil)
    }

    @Test
    func browserMetadata_helpersExposeSafeStorageLabels() {
        let chromeLabels = Browser.chrome.safeStorageLabels.map { "\($0.service)|\($0.account)" }
        #expect(chromeLabels.contains("Chrome Safe Storage|Chrome"))
        let yandexLabels = Browser.yandex.safeStorageLabels.map { "\($0.service)|\($0.account)" }
        #expect(yandexLabels.contains("Yandex Safe Storage|Yandex"))
        #expect(Browser.safari.safeStorageLabels.isEmpty)
    }
}

#endif
