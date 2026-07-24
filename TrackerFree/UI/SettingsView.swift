import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(state)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            RulesSettingsView()
                .environmentObject(state)
                .tabItem {
                    Label("Rules", systemImage: "checklist")
                }

            PrivacySettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
        }
        .frame(width: 660, height: 560)
        .accessibilityIdentifier("tracker-free-settings")
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Automatic Cleaning") {
                Toggle(
                    "Enable automatic cleaning",
                    isOn: Binding(
                        get: { state.requestedEnabled },
                        set: { state.setRequestedEnabled($0) }
                    )
                )

                LabeledContent("Status", value: state.operationalStatusText)

                if state.showsClipboardAccessAction {
                    Button("Review Clipboard Access") {
                        state.showClipboardAccessExplanation()
                    }
                }

                if state.hasClipboardConflict {
                    Button("Resume After Clipboard Conflict") {
                        state.resumeAfterClipboardConflict()
                    }
                }
            }

            Section("Pause") {
                Picker(
                    "Pause automatic cleaning",
                    selection: Binding(
                        get: { state.settingsPauseSelection },
                        set: { state.applySettingsPauseSelection($0) }
                    )
                ) {
                    ForEach(SettingsPauseSelection.allCases) { selection in
                        Text(selection.label).tag(selection)
                    }
                }
            }

            Section("Startup") {
                Toggle(
                    "Launch Tracker Free at login",
                    isOn: Binding(
                        get: { state.launchAtLoginEnabled },
                        set: { state.setLaunchAtLogin($0) }
                    )
                )

                Text(state.launchAtLoginStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if state.showsLoginItemApprovalAction {
                    Button("Open Login Items Settings") {
                        state.openLoginItemsSettings()
                    }
                }
            }

            Section("Keyboard Shortcut") {
                Text(
                    "Tracker Free exposes “Clean Current Clipboard” to Shortcuts. "
                        + "Create a Shortcut and assign a macOS keyboard shortcut there."
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct PrivacySettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Local by design")
                    .font(.title2.bold())

                Text(
                    "Tracker Free does not persist clipboard contents in its own files, "
                        + "database, analytics, or logs."
                )

                Text(
                    "Tracker Free removes known tracking query parameters from qualifying "
                        + "copied links using conservative, user-auditable rules."
                )

                Group {
                    Label(
                        "Rich, custom, multiple-item, remote, and ambiguous clipboard values are skipped.",
                        systemImage: "checkmark.shield"
                    )
                    Label(
                        "Unknown parameters, affiliate identifiers, short links, and nested URLs remain unchanged.",
                        systemImage: "checkmark.shield"
                    )
                    Label(
                        "No analytics, telemetry, updater, remote rules, or network access.",
                        systemImage: "checkmark.shield"
                    )
                }

                Divider()

                Text("Platform limitations")
                    .font(.headline)

                Text(
                    "macOS may retain original and cleaned generations in Clipboard History. "
                        + "The original may also reach Universal Clipboard before Tracker Free "
                        + "rewrites it; the app cannot retract that value. Cleaned and restored "
                        + "generations are written for the current Mac only."
                )

                Text(
                    "Polling cannot guarantee that an immediate paste receives the cleaned value. "
                        + "Undo is memory-only and is lost after another copy, sleep, session loss, "
                        + "crash, or relaunch."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}
