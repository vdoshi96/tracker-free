import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum PauseOption {
    case fiveMinutes
    case thirtyMinutes
    case indefinite
}

enum SettingsPauseSelection: String, CaseIterable, Identifiable {
    case resumed
    case fiveMinutes
    case thirtyMinutes
    case indefinite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .resumed:
            "Resume now"
        case .fiveMinutes:
            "5 minutes"
        case .thirtyMinutes:
            "30 minutes"
        case .indefinite:
            "Until resumed"
        }
    }
}

struct RuleDisplayRow: Identifiable, Equatable {
    let id: String
    let displayName: String
    let detail: String
    let enabled: Bool
    let isHardGuard: Bool
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var successPulse = false
    @Published private(set) var rulesStatusText = "Rules ready."

    private let preferences: AppPreferences
    private let ruleStore: RuleStore
    private let coordinator: ClipboardCoordinator
    private let loginItemService: LoginItemService
    private var cancellables: Set<AnyCancellable> = []
    private var successPulseTask: Task<Void, Never>?
    private var started = false
    private var rulesBootstrapFailed = false

    private init() {
        let isIsolatedTestProcess = Self.isIsolatedTestProcess
        let defaults: UserDefaults
        if isIsolatedTestProcess,
           let isolatedDefaults = UserDefaults(
               suiteName: "com.vishal.TrackerFree.tests.\(UUID().uuidString)"
           )
        {
            defaults = isolatedDefaults
        } else {
            defaults = .standard
        }

        let preferences = AppPreferences(defaults: defaults)
        self.preferences = preferences

        let builtInSnapshot: RuleSetSnapshot
        let bootstrapFailed: Bool
        do {
            builtInSnapshot = try BuiltInRuleLoader.load()
            bootstrapFailed = false
        } catch {
            // RECOMMENDATION: a missing/invalid bundled rule set disables all
            // removal rather than substituting unreviewed rules.
            builtInSnapshot = try! RuleSetSnapshot(
                revision: 1,
                reviewedDate: "2026-07-23",
                rules: []
            )
            bootstrapFailed = true
        }

        let userRulesURL: URL
        if isIsolatedTestProcess {
            userRulesURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "TrackerFreeTests-\(UUID().uuidString)",
                    isDirectory: true
                )
                .appendingPathComponent("user-rules.json", isDirectory: false)
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            userRulesURL = applicationSupport
                .appendingPathComponent("Tracker Free", isDirectory: true)
                .appendingPathComponent("user-rules.json", isDirectory: false)
        }

        let ruleStore = RuleStore(
            builtInSnapshot: builtInSnapshot,
            userRulesFileURL: userRulesURL,
            disabledBuiltInRuleIDs: preferences.disabledBuiltInRuleIDs,
            enabledBuiltInRuleIDs: preferences.enabledBuiltInRuleIDs
        )
        self.ruleStore = ruleStore

        let pasteboard: any PasteboardClient =
            isIsolatedTestProcess ? FakePasteboardClient() : GeneralPasteboardClient()
        let stateStore: any ClipboardCoordinatorStateStoring =
            isIsolatedTestProcess
                ? InMemoryClipboardCoordinatorStateStore()
                : UserDefaultsClipboardCoordinatorStateStore(defaults: defaults)
        if bootstrapFailed {
            stateStore.requestedEnabled = false
        }

        let coordinator = ClipboardCoordinator(
            pasteboard: pasteboard,
            stateStore: stateStore,
            transform: Self.makeClipboardTransform(
                ruleStore: ruleStore,
                rulesBootstrapFailed: bootstrapFailed
            ),
            ruleRevision: {
                ruleStore.snapshot.revision
            },
            automaticallyStartsMonitoring: false
        )
        self.coordinator = coordinator
        loginItemService = LoginItemService()
        rulesBootstrapFailed = bootstrapFailed

        if bootstrapFailed {
            rulesStatusText = "Built-in rules unavailable — cleaning is safely inactive."
        } else if let issue = ruleStore.loadIssue {
            rulesStatusText = Self.ruleLoadIssueText(issue)
        }

        coordinator.objectWillChange
            .sink(receiveValue: { [weak self] (_: Void) in
                self?.objectWillChange.send()
            })
            .store(in: &cancellables)

        coordinator.$lastResult
            .compactMap { $0 }
            .sink { [weak self] result in
                self?.handleResultFeedback(result)
            }
            .store(in: &cancellables)

        loginItemService.objectWillChange
            .sink(receiveValue: { [weak self] (_: Void) in
                self?.objectWillChange.send()
            })
            .store(in: &cancellables)

        Timer.publish(every: 1, tolerance: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.loginItemService.refresh()
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        if preferences.isTrueFirstLaunch {
            preferences.markLaunched()
        }
    }

    static func makeClipboardTransform(
        ruleStore: RuleStore,
        rulesBootstrapFailed: Bool
    ) -> ClipboardTransformClosure {
        { input, revision in
            guard !rulesBootstrapFailed else {
                return .unchanged(.protectedOrUnsupported)
            }
            guard revision == ruleStore.snapshot.revision else {
                return .unchanged(.ruleConflict)
            }
            return ClipboardContentTransformer.transform(
                input,
                using: ruleStore.snapshot
            )
        }
    }

    var requestedEnabled: Bool {
        coordinator.requestedEnabled
    }

    var skipNextArmed: Bool {
        coordinator.skipNextIsArmed
    }

    var canRestoreOriginal: Bool {
        coordinator.canRestoreOriginal
    }

    var isPaused: Bool {
        coordinator.pauseState != .none
    }

    var hasClipboardConflict: Bool {
        coordinator.conflictState != .none
    }

    var operationalStatusText: String {
        switch coordinator.operationalState {
        case .disabled:
            "Automatic cleaning: Off"
        case .paused:
            if let remaining = coordinator.pauseTimeRemaining {
                "Paused — \(Self.formattedDuration(remaining)) remaining"
            } else {
                "Paused — until resumed"
            }
        case .needsClipboardAccess:
            switch coordinator.permissionState {
            case .alwaysDeny:
                "Clipboard access denied — review System Settings"
            case .defaultBehavior, .ask:
                "Needs Clipboard Access — choose Always Allow"
            case .unknown:
                "Clipboard access state is unavailable"
            case .notRequired, .alwaysAllow:
                "Needs Clipboard Access"
            }
        case .clipboardConflict:
            "Clipboard conflict — automatic cleaning paused"
        case .lifecycleInactive:
            "Automatic cleaning: Inactive"
        case .running:
            "Automatic cleaning: On"
        }
    }

    var menuBarSystemImage: String {
        switch coordinator.operationalState {
        case .running:
            "link.circle.fill"
        case .disabled:
            "link.circle"
        case .paused:
            "pause.circle"
        case .needsClipboardAccess:
            "lock.trianglebadge.exclamationmark"
        case .clipboardConflict:
            "exclamationmark.triangle.fill"
        case .lifecycleInactive:
            "moon.zzz"
        }
    }

    var showsClipboardAccessAction: Bool {
        switch coordinator.permissionState {
        case .notRequired, .alwaysAllow:
            false
        case .defaultBehavior, .ask, .alwaysDeny, .unknown:
            true
        }
    }

    var lastResultText: String {
        guard let result = coordinator.lastResult else {
            return "No clipboard result yet."
        }
        return Self.resultText(result)
    }

    var launchAtLoginEnabled: Bool {
        switch loginItemService.status {
        case .enabled, .requiresApproval:
            true
        case .notRegistered, .notFound, .operationFailed:
            false
        }
    }

    var launchAtLoginStatusText: String {
        switch loginItemService.status {
        case .notRegistered:
            "Not registered."
        case .enabled:
            "Registered and enabled."
        case .requiresApproval:
            "Registered — approval is required in Login Items."
        case .notFound:
            "The installed app could not be found by the login-item service."
        case .operationFailed:
            "The login-item operation failed. The prior system state was not assumed."
        }
    }

    var showsLoginItemApprovalAction: Bool {
        loginItemService.status == .requiresApproval
    }

    var settingsPauseSelection: SettingsPauseSelection {
        switch coordinator.pauseState {
        case .none:
            .resumed
        case .indefinitely:
            .indefinite
        case .until:
            if (coordinator.pauseTimeRemaining ?? 0) > 5 * 60 {
                .thirtyMinutes
            } else {
                .fiveMinutes
            }
        }
    }

    var builtInRuleRows: [RuleDisplayRow] {
        ruleStore.builtInRules
            .map(Self.displayRow)
            .sorted { lhs, rhs in
                if lhs.displayName == rhs.displayName {
                    return lhs.id < rhs.id
                }
                return lhs.displayName.localizedStandardCompare(rhs.displayName)
                    == .orderedAscending
            }
    }

    var userRuleRows: [RuleDisplayRow] {
        ruleStore.userRules
            .map(Self.displayRow)
            .sorted { $0.id < $1.id }
    }

    func startIfNeeded() {
        guard !started else {
            return
        }
        started = true
        coordinator.startMonitoring()
        loginItemService.refresh()
    }

    func prepareForTermination() {
        successPulseTask?.cancel()
        coordinator.stopMonitoring(wipeClipboardDerivedMemory: true)
    }

    func setRequestedEnabled(_ enabled: Bool) {
        if enabled, coordinator.shouldPresentPermissionExplanation {
            let alert = NSAlert()
            alert.messageText = "Allow conservative clipboard cleaning?"
            alert.informativeText =
                "Tracker Free checks one qualifying copied link at a time. On current "
                + "macOS, automatic background cleaning needs Always Allow clipboard "
                + "access. Rich, ambiguous, and protected values remain unchanged."
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Cancel")

            coordinator.markPermissionExplanationPresented()
            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
        }

        coordinator.setRequestedEnabled(enabled && !rulesBootstrapFailed)
        if enabled, rulesBootstrapFailed {
            rulesStatusText = "Cannot enable cleaning because bundled rules failed validation."
        }
    }

    func showClipboardAccessExplanation() {
        let alert = NSAlert()
        coordinator.markPermissionExplanationPresented()

        if coordinator.permissionState == .alwaysDeny {
            alert.messageText = "Clipboard access is denied"
            alert.informativeText =
                "Open System Settings, search for the clipboard access settings, "
                + "select Tracker Free, and choose Always Allow. Apple documents "
                + "that a denied app remains listed in the corresponding settings "
                + "pane. Tracker Free does not use an undocumented deep link."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Clean Clipboard Now")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                openSystemSettingsRoot()
            case .alertSecondButtonReturn:
                cleanClipboardNow()
            default:
                break
            }
        } else {
            alert.messageText =
                "Clipboard access is required for automatic cleaning"
            alert.informativeText =
                "After enabling, copy a synthetic link. macOS may ask when "
                + "Tracker Free reads that new General-pasteboard generation; "
                + "choose Always Allow for background cleaning. The prompt-trigger "
                + "generation is never rewritten. Clean Clipboard Now remains an "
                + "explicit action."
            alert.addButton(withTitle: "Clean Clipboard Now")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                cleanClipboardNow()
            }
        }
        coordinator.refreshPermissionState()
    }

    private func openSystemSettingsRoot() {
        let settingsURL = URL(
            fileURLWithPath: "/System/Applications/System Settings.app"
        )
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: settingsURL,
            configuration: configuration
        )
    }

    func toggleSkipNext() {
        if coordinator.skipNextIsArmed {
            coordinator.cancelSkipNext()
        } else {
            coordinator.armSkipNextQualifyingURL()
        }
    }

    func pause(for option: PauseOption) {
        switch option {
        case .fiveMinutes:
            coordinator.pause(for: 5 * 60)
        case .thirtyMinutes:
            coordinator.pause(for: 30 * 60)
        case .indefinite:
            coordinator.pauseIndefinitely()
        }
    }

    func resume() {
        coordinator.resumeNow()
    }

    func resumeAfterClipboardConflict() {
        coordinator.resumeAutomaticCleaningAfterConflict()
    }

    func applySettingsPauseSelection(_ selection: SettingsPauseSelection) {
        switch selection {
        case .resumed:
            resume()
        case .fiveMinutes:
            pause(for: .fiveMinutes)
        case .thirtyMinutes:
            pause(for: .thirtyMinutes)
        case .indefinite:
            pause(for: .indefinite)
        }
    }

    func cleanClipboardNow() {
        _ = coordinator.cleanCurrentClipboard()
    }

    func cleanClipboardForIntent() -> String {
        Self.resultText(coordinator.cleanCurrentClipboard())
    }

    func restoreOriginal() {
        _ = coordinator.restoreOriginal()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        _ = loginItemService.setEnabled(enabled)
    }

    func openLoginItemsSettings() {
        loginItemService.openSystemSettings()
    }

    func setBuiltInRule(_ id: String, enabled: Bool) {
        do {
            try ruleStore.setBuiltInRule(id: id, enabled: enabled)
            preferences.disabledBuiltInRuleIDs = ruleStore.disabledBuiltInRuleIDs
            preferences.enabledBuiltInRuleIDs = ruleStore.enabledBuiltInRuleIDs
            rulesStatusText = "Built-in rule preference updated."
            objectWillChange.send()
        } catch {
            rulesStatusText = "The built-in rule preference was left unchanged."
        }
    }

    func setUserRule(_ id: String, enabled: Bool) {
        do {
            var acknowledgedOverride = false
            if enabled {
                let overrides = try ruleStore.builtInPreserveOverrides(
                    ifEnablingUserRuleID: id
                )
                if !overrides.isEmpty {
                    let alert = NSAlert()
                    alert.messageText =
                        "Enable a removal that overrides built-in preservation?"
                    let displayed = overrides.prefix(8).joined(separator: ", ")
                    let remainder = overrides.count - min(8, overrides.count)
                    alert.informativeText =
                        "This rule can remove parameters Tracker Free normally "
                        + "preserves as potentially functional: \(displayed)"
                        + (remainder > 0 ? " and \(remainder) more." : ".")
                        + "\n\nOnly enable it if you have reviewed the affected links."
                    alert.addButton(withTitle: "Enable Rule")
                    alert.addButton(withTitle: "Cancel")
                    guard alert.runModal() == .alertFirstButtonReturn else {
                        rulesStatusText = "The user rule was left disabled."
                        return
                    }
                    acknowledgedOverride = true
                }
            }

            try ruleStore.setUserRule(
                id: id,
                enabled: enabled,
                acknowledgingBuiltInPreserveOverride: acknowledgedOverride
            )
            rulesStatusText = "User rule preference updated."
            objectWillChange.send()
        } catch RuleStoreError.userRuleNotFound {
            rulesStatusText = "The user rule no longer exists."
        } catch {
            rulesStatusText = "The user rule preference was left unchanged."
        }
    }

    func importRules() {
        let panel = NSOpenPanel()
        panel.title = "Import Tracker Free Rules"
        panel.message = "Choose a validated Tracker Free user-rule JSON file."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let resourceValues = try url.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard resourceValues.isRegularFile == true,
                  resourceValues.isSymbolicLink != true,
                  let fileSize = resourceValues.fileSize,
                  fileSize <= RuleStore.maximumImportByteCount
            else {
                throw RuleStoreError.importTooLarge
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(
                upToCount: RuleStore.maximumImportByteCount + 1
            ) ?? Data()
            guard data.count <= RuleStore.maximumImportByteCount else {
                throw RuleStoreError.importTooLarge
            }
            let preview = try ruleStore.makeImportPreview(data)

            let alert = NSAlert()
            alert.messageText = "Replace user rules?"
            var summary =
                "\(preview.ruleCount) rules: \(preview.enabledRemovalCount) removals, "
                + "\(preview.enabledPreservationCount) preserves, "
                + "\(preview.enabledHardProtectionCount) protections."
            if !preview.builtInPreserveOverrides.isEmpty {
                summary +=
                    "\n\nWarning: enabled user removals may override built-in preserve "
                    + "rules for \(preview.builtInPreserveOverrides.count) configured names."
            }
            alert.informativeText = summary
            alert.addButton(withTitle: "Replace Rules")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }

            try ruleStore.applyImport(preview)
            rulesStatusText = "Imported \(preview.ruleCount) validated user rules."
            objectWillChange.send()
        } catch {
            rulesStatusText = "Import rejected — the existing rules were left unchanged."
        }
    }

    func exportRules() {
        let panel = NSSavePanel()
        panel.title = "Export Tracker Free Rules"
        panel.nameFieldStringValue = "Tracker-Free-Rules.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = try ruleStore.exportUserRulesData()
            try data.write(to: url, options: [.atomic])
            rulesStatusText = "Exported user rules only."
        } catch {
            rulesStatusText = "Export failed — no clipboard data was written."
        }
    }

    func resetBuiltInRuleEnablement() {
        let alert = NSAlert()
        alert.messageText = "Reset built-in rule enablement?"
        alert.informativeText =
            "This restores the reviewed defaults. User rules remain unchanged."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try ruleStore.resetBuiltInEnablement()
            preferences.disabledBuiltInRuleIDs = []
            preferences.enabledBuiltInRuleIDs = []
            rulesStatusText = "Built-in rule defaults restored."
            objectWillChange.send()
        } catch {
            rulesStatusText = "Built-in rules were left unchanged."
        }
    }

    func resetUserRules() {
        let alert = NSAlert()
        alert.messageText = "Remove all user rules?"
        alert.informativeText =
            "Built-in rules and their enablement remain unchanged."
        alert.addButton(withTitle: "Remove User Rules")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try ruleStore.resetUserRules()
            rulesStatusText = "User rules removed."
            objectWillChange.send()
        } catch {
            rulesStatusText = "User rules were left unchanged."
        }
    }

    private func handleResultFeedback(_ result: ClipboardActionResult) {
        guard case .cleaned = result else {
            return
        }
        successPulseTask?.cancel()
        successPulse = true
        successPulseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else {
                return
            }
            self?.successPulse = false
        }
    }

    private static func resultText(_ result: ClipboardActionResult) -> String {
        switch result {
        case let .cleaned(names):
            let safeNames = Array(names.prefix(3))
            var summary = "Removed \(names.count)"
            if !safeNames.isEmpty {
                summary += ": " + safeNames.joined(separator: ", ")
            }
            if names.count > safeNames.count {
                summary += ", and \(names.count - safeNames.count) more"
            }
            return summary + "."
        case let .unchanged(reason):
            switch reason {
            case .noKnownTrackingParameters:
                return "No known tracking parameters."
            case .protectedOrUnsupported, .invalidInput:
                return "Clipboard left unchanged — protected or unsupported."
            case .ruleConflict:
                return "Clipboard left unchanged — rule conflict."
            }
        case .skipped:
            return "Skipped the next qualifying URL."
        case .clipboardChanged:
            return "Clipboard changed — try again."
        case .ruleRevisionChanged:
            return "Rules changed — try again."
        case .writeFailed:
            return "Clipboard left unchanged — write could not be verified."
        case .restored:
            return "Original restored."
        case .restoreUnavailable:
            return "Restore unavailable — the clipboard changed."
        }
    }

    private static func displayRow(_ rule: CleaningRule) -> RuleDisplayRow {
        let action: String
        switch rule.action {
        case .removeParameter:
            action = "Remove"
        case .preserveParameter:
            action = "Preserve"
        case .hardProtectURL:
            action = "Protect whole URL"
        }

        let scope: String
        switch rule.scope {
        case .global:
            scope = "Global"
        case .host:
            scope = "Host scoped"
        case .hostPath:
            scope = "Host + path scoped"
        }

        return RuleDisplayRow(
            id: rule.id,
            displayName: rule.name,
            detail: "\(action) · \(scope) · \(rule.confidence.rawValue) — \(rule.explanation)",
            enabled: rule.enabled,
            isHardGuard: rule.origin == .builtIn && rule.action == .hardProtectURL
        )
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.up)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private static func ruleLoadIssueText(_ issue: RuleStoreLoadIssue) -> String {
        switch issue {
        case .customRuleFileTooLarge:
            "Stored user rules were too large and were not loaded."
        case .customRuleFileUnreadable:
            "Stored user rules could not be read; built-in rules remain active."
        case .customRuleFileInvalid:
            "Stored user rules failed validation; built-in rules remain active."
        case .customRuleOverridesNeedReview:
            "Stored removal rules that override built-in preservation were disabled; "
                + "review and enable them individually."
        }
    }

    static var isIsolatedTestProcess: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("--ui-testing-open-settings")
    }
}
