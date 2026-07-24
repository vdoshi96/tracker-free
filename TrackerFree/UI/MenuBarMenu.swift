import AppKit
import SwiftUI

struct MenuBarMenu: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Text(state.operationalStatusText)
            .accessibilityIdentifier("operational-status")

        Toggle(
            "Enabled",
            isOn: Binding(
                get: { state.requestedEnabled },
                set: { state.setRequestedEnabled($0) }
            )
        )
        .accessibilityIdentifier("enabled-toggle")

        if state.showsClipboardAccessAction {
            Button("Clipboard Access…") {
                state.showClipboardAccessExplanation()
            }
            .accessibilityIdentifier("clipboard-access-action")
        }

        if state.hasClipboardConflict {
            Button("Resume After Clipboard Conflict") {
                state.resumeAfterClipboardConflict()
            }
            .accessibilityIdentifier("resume-conflict-action")
        }

        Divider()

        Button {
            state.toggleSkipNext()
        } label: {
            if state.skipNextArmed {
                Label("Skip Next Qualifying URL", systemImage: "checkmark")
            } else {
                Text("Skip Next Qualifying URL")
            }
        }
        .accessibilityIdentifier("skip-next-action")

        Menu("Pause") {
            Button("Pause 5 Minutes") {
                state.pause(for: .fiveMinutes)
            }
            Button("Pause 30 Minutes") {
                state.pause(for: .thirtyMinutes)
            }
            Button("Pause Until Resumed") {
                state.pause(for: .indefinite)
            }
            Divider()
            Button("Resume Now") {
                state.resume()
            }
            .disabled(!state.isPaused)
        }

        Divider()

        Button("Clean Clipboard Now") {
            state.cleanClipboardNow()
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])
        .accessibilityIdentifier("clean-now-action")

        Button("Restore Original") {
            state.restoreOriginal()
        }
        .disabled(!state.canRestoreOriginal)
        .accessibilityIdentifier("restore-original-action")

        Text(state.lastResultText)
            .accessibilityIdentifier("last-result")

        Divider()

        Toggle(
            "Launch at Login",
            isOn: Binding(
                get: { state.launchAtLoginEnabled },
                set: { state.setLaunchAtLogin($0) }
            )
        )
        .accessibilityIdentifier("launch-at-login-toggle")

        if state.showsLoginItemApprovalAction {
            Button("Open Login Items Settings…") {
                state.openLoginItemsSettings()
            }
        }

        Divider()

        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",", modifiers: .command)
        } else {
            Button("Settings…") {
                SettingsWindowOpener.openLegacy()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        Button("About Tracker Free") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        }

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

@MainActor
enum SettingsWindowOpener {
    static func openLegacy() {
        NSApp.activate(ignoringOtherApps: true)

        // VERIFIED: SettingsLink is unavailable on macOS 13, where SwiftUI's
        // Settings scene is opened through the legacy AppKit action.
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
