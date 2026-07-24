import AppIntents

struct CleanCurrentClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Current Clipboard"
    static let description = IntentDescription(
        "Removes known tracking query parameters from one qualifying copied link using the same conservative rules as Tracker Free."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = AppState.shared.cleanClipboardForIntent()
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct TrackerFreeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CleanCurrentClipboardIntent(),
            phrases: [
                "Clean my clipboard with \(.applicationName)",
                "Remove link tracking with \(.applicationName)"
            ],
            shortTitle: "Clean Clipboard",
            systemImageName: "link.badge.plus"
        )
    }
}
