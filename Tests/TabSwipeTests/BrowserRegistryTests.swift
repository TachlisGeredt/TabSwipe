import XCTest
@testable import TabSwipeCore

final class BrowserRegistryTests: XCTestCase {
    func testMajorBrowsersAreSupported() {
        let expectedSupported = [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.brave.Browser",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser",
            "com.vivaldi.Vivaldi",
            "com.operasoftware.Opera",
            "com.kagi.kagimacOS",
            "app.zen-browser.zen",
            "org.chromium.Chromium",
        ]

        for bundleID in expectedSupported {
            XCTAssertTrue(
                BrowserRegistry.isSupportedBrowser(bundleID),
                "Expected \(bundleID) to be recognized as a supported browser"
            )
        }
    }

    func testCaseInsensitiveLookup() {
        XCTAssertEqual(
            BrowserRegistry.shortcuts(for: "COM.APPLE.SAFARI"),
            .standard
        )
    }

    func testArcUsesSidebarShortcuts() {
        XCTAssertEqual(
            BrowserRegistry.shortcuts(for: "company.thebrowser.Browser"),
            .arc
        )
    }

    func testNonBrowsersAreRejected() {
        XCTAssertFalse(BrowserRegistry.isSupportedBrowser("com.apple.finder"))
        XCTAssertFalse(BrowserRegistry.isSupportedBrowser("com.apple.Terminal"))
        XCTAssertFalse(BrowserRegistry.isSupportedBrowser("com.microsoft.VSCode"))
        XCTAssertFalse(BrowserRegistry.isSupportedBrowser(nil))
    }
}
