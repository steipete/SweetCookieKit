import Foundation

#if os(macOS)

struct BrowserMetadata: Sendable {
    let browser: Browser
    let displayName: String
    let engine: BrowserEngine
    let defaultImportOrderRank: Int
    let chromiumProfileRelativePath: String?
    let geckoProfilesFolder: String?
    let safeStorageLabels: [(service: String, account: String)]
    let appBundleName: String?

    init(
        browser: Browser,
        displayName: String,
        engine: BrowserEngine,
        defaultImportOrderRank: Int,
        chromiumProfileRelativePath: String?,
        geckoProfilesFolder: String?,
        safeStorageLabels: [(service: String, account: String)],
        appBundleName: String? = nil)
    {
        self.browser = browser
        self.displayName = displayName
        self.engine = engine
        self.defaultImportOrderRank = defaultImportOrderRank
        self.chromiumProfileRelativePath = chromiumProfileRelativePath
        self.geckoProfilesFolder = geckoProfilesFolder
        self.safeStorageLabels = safeStorageLabels
        self.appBundleName = appBundleName
    }
}

enum BrowserCatalog {
    static let metadataByBrowser: [Browser: BrowserMetadata] = {
        let entries: [BrowserMetadata] = [
            BrowserMetadata(
                browser: .safari,
                displayName: "Safari",
                engine: .webkit,
                defaultImportOrderRank: 0,
                chromiumProfileRelativePath: nil,
                geckoProfilesFolder: nil,
                safeStorageLabels: []),
            BrowserMetadata(
                browser: .chrome,
                displayName: "Chrome",
                engine: .chromium,
                defaultImportOrderRank: 1,
                chromiumProfileRelativePath: "Google/Chrome",
                geckoProfilesFolder: nil,
                safeStorageLabels: [("Chrome Safe Storage", "Chrome")],
                appBundleName: "Google Chrome"),
            BrowserMetadata(
                browser: .edge,
                displayName: "Microsoft Edge",
                engine: .chromium,
                defaultImportOrderRank: 2,
                chromiumProfileRelativePath: "Microsoft Edge",
                geckoProfilesFolder: nil,
                safeStorageLabels: [("Microsoft Edge Safe Storage", "Microsoft Edge")]),
            BrowserMetadata(
                browser: .brave,
                displayName: "Brave",
                engine: .chromium,
                defaultImportOrderRank: 3,
                chromiumProfileRelativePath: "BraveSoftware/Brave-Browser",
                geckoProfilesFolder: nil,
                safeStorageLabels: [("Brave Safe Storage", "Brave")],
                appBundleName: "Brave Browser"),
            BrowserMetadata(
                browser: .arc,
                displayName: "Arc",
                engine: .chromium,
                defaultImportOrderRank: 4,
                chromiumProfileRelativePath: "Arc/User Data",
                geckoProfilesFolder: nil,
                safeStorageLabels: [("Arc Safe Storage", "Arc")]),
            BrowserMetadata(
                browser: .dia,
                displayName: "Dia",
                engine: .chromium,
                defaultImportOrderRank: 5,
                chromiumProfileRelativePath: "Dia/User Data",
                geckoProfilesFolder: nil,
                safeStorageLabels: [("Dia Safe Storage", "Dia")]),
            BrowserMetadata(
                browser: .chatgptAtlas,
                displayName: "ChatGPT Atlas",
                engine: .chromium,
                defaultImportOrderRank: 6,
                chromiumProfileRelativePath: "com.openai.atlas/browser-data/host",
                geckoProfilesFolder: nil,
                safeStorageLabels: [
                    ("ChatGPT Atlas Safe Storage", "ChatGPT Atlas"),
                    ("ChatGPT Atlas Safe Storage", "com.openai.atlas"),
                    ("com.openai.atlas Safe Storage", "com.openai.atlas"),
                ]),
            BrowserMetadata(
                browser: .chromium,
                displayName: "Chromium",
                engine: .chromium,
                defaultImportOrderRank: 7,
                chromiumProfileRelativePath: "Chromium",
                geckoProfilesFolder: nil,
                safeStorageLabels: [("Chromium Safe Storage", "Chromium")]),
            BrowserMetadata(
                browser: .helium,
                displayName: "Helium",
                engine: .chromium,
                defaultImportOrderRank: 8,
                chromiumProfileRelativePath: "net.imput.helium",
                geckoProfilesFolder: nil,
                safeStorageLabels: [
                    ("Helium Safe Storage", "Helium"),
                    ("net.imput.helium Safe Storage", "net.imput.helium"),
                ]),
            BrowserMetadata(
                browser: .vivaldi,
                displayName: "Vivaldi",
                engine: .chromium,
                defaultImportOrderRank: 9,
                chromiumProfileRelativePath: "Vivaldi",
                geckoProfilesFolder: nil,
                safeStorageLabels: [("Vivaldi Safe Storage", "Vivaldi")]),
            BrowserMetadata(
                browser: .firefox,
                displayName: "Firefox",
                engine: .gecko,
                defaultImportOrderRank: 10,
                chromiumProfileRelativePath: nil,
                geckoProfilesFolder: "Firefox",
                safeStorageLabels: []),
            BrowserMetadata(
                browser: .zen,
                displayName: "Zen",
                engine: .gecko,
                defaultImportOrderRank: 11,
                chromiumProfileRelativePath: nil,
                geckoProfilesFolder: "zen",
                safeStorageLabels: []),
            BrowserMetadata(
                browser: .chromeBeta,
                displayName: "Chrome Beta",
                engine: .chromium,
                defaultImportOrderRank: 12,
                chromiumProfileRelativePath: "Google/Chrome Beta",
                geckoProfilesFolder: nil,
                safeStorageLabels: [],
                appBundleName: "Google Chrome Beta"),
            BrowserMetadata(
                browser: .chromeCanary,
                displayName: "Chrome Canary",
                engine: .chromium,
                defaultImportOrderRank: 13,
                chromiumProfileRelativePath: "Google/Chrome Canary",
                geckoProfilesFolder: nil,
                safeStorageLabels: [],
                appBundleName: "Google Chrome Canary"),
            BrowserMetadata(
                browser: .arcBeta,
                displayName: "Arc Beta",
                engine: .chromium,
                defaultImportOrderRank: 14,
                chromiumProfileRelativePath: "Arc Beta/User Data",
                geckoProfilesFolder: nil,
                safeStorageLabels: [("Arc Safe Storage", "Arc Beta")]),
            BrowserMetadata(
                browser: .arcCanary,
                displayName: "Arc Canary",
                engine: .chromium,
                defaultImportOrderRank: 15,
                chromiumProfileRelativePath: "Arc Canary/User Data",
                geckoProfilesFolder: nil,
                safeStorageLabels: [("Arc Safe Storage", "Arc Canary")]),
            BrowserMetadata(
                browser: .braveBeta,
                displayName: "Brave Beta",
                engine: .chromium,
                defaultImportOrderRank: 16,
                chromiumProfileRelativePath: "BraveSoftware/Brave-Browser-Beta",
                geckoProfilesFolder: nil,
                safeStorageLabels: [],
                appBundleName: "Brave Browser Beta"),
            BrowserMetadata(
                browser: .braveNightly,
                displayName: "Brave Nightly",
                engine: .chromium,
                defaultImportOrderRank: 17,
                chromiumProfileRelativePath: "BraveSoftware/Brave-Browser-Nightly",
                geckoProfilesFolder: nil,
                safeStorageLabels: [],
                appBundleName: "Brave Browser Nightly"),
            BrowserMetadata(
                browser: .edgeBeta,
                displayName: "Microsoft Edge Beta",
                engine: .chromium,
                defaultImportOrderRank: 18,
                chromiumProfileRelativePath: "Microsoft Edge Beta",
                geckoProfilesFolder: nil,
                safeStorageLabels: []),
            BrowserMetadata(
                browser: .edgeCanary,
                displayName: "Microsoft Edge Canary",
                engine: .chromium,
                defaultImportOrderRank: 19,
                chromiumProfileRelativePath: "Microsoft Edge Canary",
                geckoProfilesFolder: nil,
                safeStorageLabels: []),
        ]

        var map: [Browser: BrowserMetadata] = [:]
        map.reserveCapacity(entries.count)
        for entry in entries {
            map[entry.browser] = entry
        }
        return map
    }()

    static func metadata(for browser: Browser) -> BrowserMetadata {
        guard let metadata = metadataByBrowser[browser] else {
            preconditionFailure("Missing metadata for \(browser)")
        }
        return metadata
    }

    static let defaultImportOrder: [Browser] = {
        let entries = metadataByBrowser.values.sorted { $0.defaultImportOrderRank < $1.defaultImportOrderRank }
        precondition(entries.count == Browser.allCases.count, "Default import order missing browsers")
        let ranks = Set(entries.map(\.defaultImportOrderRank))
        precondition(ranks.count == entries.count, "Default import order has duplicate ranks")
        return entries.map(\.browser)
    }()

    static let safeStorageLabels: [(service: String, account: String)] = {
        let labelOrder: [Browser] = [
            .chrome,
            .chromium,
            .brave,
            .arc,
            .arcBeta,
            .arcCanary,
            .chatgptAtlas,
            .helium,
            .edge,
            .vivaldi,
            .dia,
        ]
        return labelOrder.flatMap { metadata(for: $0).safeStorageLabels }
    }()
}

#endif
