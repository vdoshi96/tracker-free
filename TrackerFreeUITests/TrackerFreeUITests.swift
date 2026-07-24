import XCTest

final class TrackerFreeUITests: XCTestCase {
    @MainActor
    func testSettingsSceneCanOpenForDocklessApp() throws {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-testing-open-settings"]
        application.launch()

        let statusItem = application.statusItems["tracker-free-menu-extra"]
        XCTAssertTrue(
            statusItem.waitForExistence(timeout: 5),
            "Tracker Free status item was absent"
        )

        let statusMenu = statusItem.menus.firstMatch
        for title in [
            "Enabled",
            "Skip Next Qualifying URL",
            "Clean Clipboard Now",
            "Restore Original",
            "Launch at Login",
            "Settings…",
        ] {
            XCTAssertTrue(
                statusMenu.menuItems[title].exists,
                "\(title) was absent from the status-item menu"
            )
        }
        application.typeKey(",", modifierFlags: .command)

        let settings = application.scrollViews["tracker-free-settings"]
        XCTAssertTrue(
            settings.waitForExistence(timeout: 5),
            "Settings accessibility element was absent"
        )
    }
}
