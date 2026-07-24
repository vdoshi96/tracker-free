import AppKit
import SwiftUI

@main
struct TrackerFreeApp: App {
    @NSApplicationDelegateAdaptor(TrackerFreeApplicationDelegate.self)
    private var applicationDelegate

    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
                .environmentObject(state)
                .task {
                    state.startIfNeeded()
                }
        } label: {
            Label(
                "Tracker Free",
                systemImage: state.successPulse ? "checkmark.circle.fill" : state.menuBarSystemImage
            )
            .accessibilityIdentifier("tracker-free-menu-extra")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(state)
                .task {
                    state.startIfNeeded()
                }
        }
    }
}

@MainActor
final class TrackerFreeApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.startIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.prepareForTermination()
    }
}
