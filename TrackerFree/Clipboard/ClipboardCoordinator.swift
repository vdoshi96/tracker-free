import Combine
import Foundation

public enum PauseState: Equatable, Sendable {
    case none
    case until(Date)
    case indefinitely
}

public enum ConflictState: Equatable, Sendable {
    case none
    case paused(sinceUptime: TimeInterval)
}

public enum OperationalState: Equatable, Sendable {
    case disabled
    case paused
    case needsClipboardAccess
    case clipboardConflict
    case lifecycleInactive
    case running
}

public enum ClipboardActionResult: Equatable, Sendable {
    case cleaned(removedParameterNames: [String])
    case unchanged(ClipboardTransformNoChangeReason)
    case skipped
    case clipboardChanged
    case ruleRevisionChanged
    case writeFailed
    case restored
    case restoreUnavailable
}

private enum ClipboardProcessingMode {
    case automatic
    case manual
}

private struct ClipboardUndoToken {
    let original: PasteboardContent
    let cleaned: PasteboardContent
    var cleanedGeneration: PasteboardGeneration
}

private struct RecentWritePair {
    let original: PasteboardContent
    let output: PasteboardContent
    let uptime: TimeInterval
}

private enum CommitOutcome {
    case success(PasteboardGeneration)
    case failure(appOwnedGeneration: PasteboardGeneration?, rollbackSucceeded: Bool)
}

@MainActor
public final class ClipboardCoordinator: ObservableObject {
    private static let activePollDelay = Duration.milliseconds(250)
    private static let activePollTolerance = Duration.milliseconds(40)
    private static let inactivePollDelay = Duration.seconds(1)
    private static let inactivePollTolerance = Duration.milliseconds(50)
    private static let conflictWindow: TimeInterval = 2
    private static let maximumRecentPairs = 12
    private static let maximumRemovedNames = 128
    private static let maximumRemovedNameBytes = 128

    @Published public private(set) var requestedEnabled: Bool
    @Published public private(set) var pauseState: PauseState
    @Published public private(set) var skipNextIsArmed = false
    @Published public private(set) var permissionState: ClipboardPermissionState
    @Published public private(set) var conflictState: ConflictState = .none
    @Published public private(set) var operationalState: OperationalState = .disabled
    @Published public private(set) var canRestoreOriginal = false
    @Published public private(set) var lastResult: ClipboardActionResult?
    @Published public private(set) var hasPresentedPermissionExplanation: Bool

    private let pasteboard: any PasteboardClient
    private let stateStore: any ClipboardCoordinatorStateStoring
    private let transform: ClipboardTransformClosure
    private let ruleRevisionProvider: ClipboardRuleRevisionProvider
    private let now: @MainActor () -> Date
    private let uptime: @MainActor () -> TimeInterval
    private let lifecycle: ClipboardLifecycle
    private let logger: PrivacySafeLogger

    private var pollingTask: Task<Void, Never>?
    private var lastObservedGeneration: PasteboardGeneration
    private var ownedGeneration: PasteboardGeneration?
    private var undoToken: ClipboardUndoToken?
    private var recentWritePairs: [RecentWritePair] = []
    private var pauseDeadlineUptime: TimeInterval?
    private var isAwake = true
    private var isSessionActive = true

    public init(
        pasteboard: any PasteboardClient,
        stateStore: any ClipboardCoordinatorStateStoring,
        transform: @escaping ClipboardTransformClosure,
        ruleRevision: @escaping ClipboardRuleRevisionProvider,
        lifecycle: ClipboardLifecycle? = nil,
        logger: PrivacySafeLogger = PrivacySafeLogger(),
        now: @escaping @MainActor () -> Date = { Date() },
        uptime: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        automaticallyStartsMonitoring: Bool = true
    ) {
        self.pasteboard = pasteboard
        self.stateStore = stateStore
        self.transform = transform
        ruleRevisionProvider = ruleRevision
        self.lifecycle = lifecycle ?? ClipboardLifecycle()
        self.logger = logger
        self.now = now
        self.uptime = uptime

        requestedEnabled = stateStore.requestedEnabled
        permissionState = pasteboard.permissionState
        hasPresentedPermissionExplanation = stateStore.hasPresentedPermissionExplanation
        lastObservedGeneration = pasteboard.generation

        let currentDate = now()
        if stateStore.pauseIndefinitely {
            pauseState = .indefinitely
        } else if let pauseUntil = stateStore.pauseUntil, pauseUntil > currentDate {
            pauseState = .until(pauseUntil)
            pauseDeadlineUptime =
                uptime() + pauseUntil.timeIntervalSince(currentDate)
        } else {
            pauseState = .none
            stateStore.pauseUntil = nil
            stateStore.pauseIndefinitely = false
        }

        self.lifecycle.delegate = self
        updateOperationalState()

        if automaticallyStartsMonitoring {
            startMonitoring()
        }
    }

    public var shouldPresentPermissionExplanation: Bool {
        guard !hasPresentedPermissionExplanation else {
            return false
        }
        switch permissionState {
        case .notRequired, .alwaysAllow:
            return false
        case .defaultBehavior, .ask, .alwaysDeny, .unknown:
            return true
        }
    }

    public var pauseTimeRemaining: TimeInterval? {
        guard case .until = pauseState,
              let pauseDeadlineUptime
        else {
            return nil
        }
        return max(0, pauseDeadlineUptime - uptime())
    }

    public func startMonitoring() {
        guard pollingTask == nil else {
            return
        }
        lifecycle.start()
        logger.record(.started)

        pollingTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            while !Task.isCancelled {
                guard let timing = self?.pollAndReturnTiming() else {
                    return
                }
                do {
                    try await clock.sleep(
                        for: timing.delay,
                        tolerance: timing.tolerance
                    )
                } catch {
                    return
                }
            }
        }
    }

    public func stopMonitoring(wipeClipboardDerivedMemory: Bool = false) {
        pollingTask?.cancel()
        pollingTask = nil
        lifecycle.stop()
        if wipeClipboardDerivedMemory {
            wipeSensitiveMemory()
        }
        logger.record(.stopped)
    }

    public func setRequestedEnabled(_ isEnabled: Bool) {
        guard requestedEnabled != isEnabled else {
            return
        }
        requestedEnabled = isEnabled
        stateStore.requestedEnabled = isEnabled
        baselineCurrentGeneration()
        updateOperationalState()
    }

    public func markPermissionExplanationPresented() {
        guard !hasPresentedPermissionExplanation else {
            return
        }
        hasPresentedPermissionExplanation = true
        stateStore.hasPresentedPermissionExplanation = true
    }

    public func refreshPermissionState() {
        _ = refreshPermissionAndBaselineIfChanged()
    }

    public func pause(for duration: TimeInterval) {
        guard duration > 0 else {
            resumeNow()
            return
        }
        let endDate = now().addingTimeInterval(duration)
        pauseState = .until(endDate)
        pauseDeadlineUptime = uptime() + duration
        stateStore.pauseUntil = endDate
        stateStore.pauseIndefinitely = false
        baselineCurrentGeneration()
        updateOperationalState()
    }

    public func pauseIndefinitely() {
        pauseState = .indefinitely
        pauseDeadlineUptime = nil
        stateStore.pauseUntil = nil
        stateStore.pauseIndefinitely = true
        baselineCurrentGeneration()
        updateOperationalState()
    }

    public func resumeNow() {
        pauseState = .none
        pauseDeadlineUptime = nil
        stateStore.pauseUntil = nil
        stateStore.pauseIndefinitely = false
        baselineCurrentGeneration()
        updateOperationalState()
    }

    public func armSkipNextQualifyingURL() {
        skipNextIsArmed = true
    }

    public func cancelSkipNext() {
        skipNextIsArmed = false
    }

    public func resumeAutomaticCleaningAfterConflict() {
        guard conflictState != .none else {
            return
        }
        conflictState = .none
        recentWritePairs.removeAll(keepingCapacity: true)
        baselineCurrentGeneration()
        updateOperationalState()
        logger.record(.conflictResumed)
    }

    public func pollOnce() {
        if refreshPermissionAndBaselineIfChanged() || expirePauseAndBaselineIfNeeded() {
            return
        }
        pruneExpiredRecentPairs()

        let generation = pasteboard.generation
        guard generation != lastObservedGeneration else {
            return
        }
        lastObservedGeneration = generation

        if generation == ownedGeneration {
            return
        }

        ownedGeneration = nil
        invalidateUndo()

        if case .paused = conflictState {
            // A generation number alone cannot prove that a clipboard manager
            // stopped replaying the same content. Remain fail-closed and do not
            // read while conflict-paused; only an explicit user action resumes.
            return
        }

        if operationalState == .needsClipboardAccess,
           requestedEnabled,
           hasPresentedPermissionExplanation,
           (
               permissionState == .defaultBehavior
                   || permissionState == .ask
           )
        {
            // A new external generation is the first safe point at which a
            // contextual, programmatic access prompt can occur without
            // inspecting or rewriting the clipboard that predated enablement.
            // This generation is always baselined, even if access changes to
            // Always Allow during the read.
            _ = PasteboardSnapshotReader.capture(
                from: pasteboard,
                expectedGeneration: generation
            )
            permissionState = pasteboard.permissionState
            updateOperationalState()
            return
        }

        guard operationalState == .running else {
            return
        }
        _ = process(generation: generation, mode: .automatic)
    }

    @discardableResult
    public func cleanCurrentClipboard() -> ClipboardActionResult {
        pruneExpiredRecentPairs()
        if conflictState != .none {
            conflictState = .none
            recentWritePairs.removeAll(keepingCapacity: true)
            updateOperationalState()
            logger.record(.conflictResumed)
        }

        guard isAwake, isSessionActive else {
            let result = ClipboardActionResult.unchanged(.protectedOrUnsupported)
            lastResult = result
            return result
        }

        let generation = pasteboard.generation
        if generation != lastObservedGeneration {
            lastObservedGeneration = generation
            if generation != ownedGeneration {
                ownedGeneration = nil
                invalidateUndo()
            }
        }
        return process(generation: generation, mode: .manual)
    }

    @discardableResult
    public func restoreOriginal() -> ClipboardActionResult {
        guard var token = undoToken,
              pasteboard.generation == token.cleanedGeneration,
              PasteboardSnapshotReader.verify(
                  token.cleaned,
                  includesMarker: true,
                  in: pasteboard,
                  generation: token.cleanedGeneration
              ),
              pasteboard.generation == token.cleanedGeneration
        else {
            invalidateUndo()
            let result = ClipboardActionResult.restoreUnavailable
            lastResult = result
            return result
        }

        let outcome = commit(
            expectedGeneration: token.cleanedGeneration,
            replacement: PasteboardWriteRequest(
                content: token.original,
                includesTrackerFreeMarker: false
            ),
            rollback: PasteboardWriteRequest(
                content: token.cleaned,
                includesTrackerFreeMarker: true
            ),
            ruleRevision: ruleRevisionProvider()
        )

        switch outcome {
        case let .success(restoredGeneration):
            ownedGeneration = restoredGeneration
            invalidateUndo()
            recentWritePairs.removeAll(keepingCapacity: true)
            conflictState = .none
            updateOperationalState()
            lastResult = .restored
            logger.record(.restoreSucceeded)
            return .restored

        case let .failure(appOwnedGeneration, rollbackSucceeded):
            ownedGeneration = appOwnedGeneration
            if rollbackSucceeded, let appOwnedGeneration {
                token.cleanedGeneration = appOwnedGeneration
                undoToken = token
                canRestoreOriginal = true
            } else {
                invalidateUndo()
            }
            lastResult = .writeFailed
            return .writeFailed
        }
    }

    private func process(
        generation: PasteboardGeneration,
        mode: ClipboardProcessingMode
    ) -> ClipboardActionResult {
        let ruleRevision = ruleRevisionProvider()
        let snapshotResult = PasteboardSnapshotReader.capture(
            from: pasteboard,
            expectedGeneration: generation
        )

        let snapshot: PasteboardSnapshot
        switch snapshotResult {
        case let .success(value):
            snapshot = value
        case let .failure(failure):
            if failure == .generationChanged {
                logger.record(.generationChanged, ruleRevision: ruleRevision)
                return publishIfManual(.clipboardChanged, mode: mode)
            }
            logger.record(.snapshotRejected, ruleRevision: ruleRevision)
            return publishIfManual(
                .unchanged(.protectedOrUnsupported),
                mode: mode
            )
        }

        let decision = transform(
            ClipboardTransformInput(content: snapshot.content),
            ruleRevision
        )

        let output: ClipboardTransformOutput
        switch decision {
        case let .unchanged(reason):
            return publishIfManual(.unchanged(reason), mode: mode)
        case let .changed(value):
            guard isValidTransform(value, for: snapshot.content) else {
                return publishIfManual(.unchanged(.invalidInput), mode: mode)
            }
            output = value
        }

        guard pasteboard.generation == generation else {
            logger.record(.generationChanged, ruleRevision: ruleRevision)
            return publishIfManual(.clipboardChanged, mode: mode)
        }
        guard ruleRevisionProvider() == ruleRevision else {
            logger.record(.ruleRevisionChanged, ruleRevision: ruleRevision)
            return publishIfManual(.ruleRevisionChanged, mode: mode)
        }
        if mode == .automatic {
            guard operationalState == .running else {
                return .unchanged(.protectedOrUnsupported)
            }
            if skipNextIsArmed {
                skipNextIsArmed = false
                lastResult = .skipped
                return .skipped
            }
        }

        let outcome = commit(
            expectedGeneration: generation,
            replacement: PasteboardWriteRequest(
                content: output.content,
                includesTrackerFreeMarker: true
            ),
            rollback: PasteboardWriteRequest(
                content: snapshot.content,
                includesTrackerFreeMarker: false
            ),
            ruleRevision: ruleRevision
        )

        switch outcome {
        case let .success(writtenGeneration):
            ownedGeneration = writtenGeneration
            undoToken = ClipboardUndoToken(
                original: snapshot.content,
                cleaned: output.content,
                cleanedGeneration: writtenGeneration
            )
            canRestoreOriginal = true
            registerSuccessfulWrite(original: snapshot.content, output: output.content)
            let result = ClipboardActionResult.cleaned(
                removedParameterNames: output.removedParameterNames
            )
            lastResult = result
            return result

        case let .failure(appOwnedGeneration, _):
            ownedGeneration = appOwnedGeneration
            invalidateUndo()
            lastResult = .writeFailed
            return .writeFailed
        }
    }

    private func commit(
        expectedGeneration: PasteboardGeneration,
        replacement: PasteboardWriteRequest,
        rollback: PasteboardWriteRequest,
        ruleRevision: ClipboardRuleRevision
    ) -> CommitOutcome {
        guard let preparedReplacement = pasteboard.prepareWrite(replacement),
              let preparedRollback = pasteboard.prepareWrite(rollback),
              pasteboard.generation == expectedGeneration
        else {
            return .failure(appOwnedGeneration: nil, rollbackSucceeded: false)
        }

        // The irreducible AppKit micro-race starts after this final check. No await,
        // logging, callback, rule lookup, or allocation belongs in the mutation window.
        let clearGeneration = pasteboard.prepareForNewContentsCurrentHostOnly()
        guard pasteboard.generation == clearGeneration else {
            logger.record(.writeFailed, ruleRevision: ruleRevision)
            return .failure(appOwnedGeneration: nil, rollbackSucceeded: false)
        }

        let didWrite = pasteboard.writePrepared(preparedReplacement)
        guard pasteboard.generation == clearGeneration else {
            logger.record(.writeFailed, ruleRevision: ruleRevision)
            return .failure(appOwnedGeneration: nil, rollbackSucceeded: false)
        }

        if didWrite,
           PasteboardSnapshotReader.verify(
               replacement.content,
               includesMarker: replacement.includesTrackerFreeMarker,
               in: pasteboard,
               generation: clearGeneration
           )
        {
            logger.record(.writeSucceeded, ruleRevision: ruleRevision)
            return .success(clearGeneration)
        }

        logger.record(.writeFailed, ruleRevision: ruleRevision)
        guard pasteboard.generation == clearGeneration else {
            return .failure(appOwnedGeneration: nil, rollbackSucceeded: false)
        }

        let rollbackClearGeneration =
            pasteboard.prepareForNewContentsCurrentHostOnly()
        guard pasteboard.generation == rollbackClearGeneration else {
            return .failure(appOwnedGeneration: nil, rollbackSucceeded: false)
        }

        let didRollback = pasteboard.writePrepared(preparedRollback)
        guard pasteboard.generation == rollbackClearGeneration else {
            return .failure(appOwnedGeneration: nil, rollbackSucceeded: false)
        }

        let rollbackVerified = didRollback && PasteboardSnapshotReader.verify(
            rollback.content,
            includesMarker: rollback.includesTrackerFreeMarker,
            in: pasteboard,
            generation: rollbackClearGeneration
        )

        if rollbackVerified {
            logger.record(.rollbackSucceeded, ruleRevision: ruleRevision)
            return .failure(
                appOwnedGeneration: rollbackClearGeneration,
                rollbackSucceeded: true
            )
        }

        logger.record(.rollbackFailed, ruleRevision: ruleRevision)
        let appOwnedGeneration =
            pasteboard.generation == rollbackClearGeneration
                ? rollbackClearGeneration
                : nil
        return .failure(
            appOwnedGeneration: appOwnedGeneration,
            rollbackSucceeded: false
        )
    }

    private func isValidTransform(
        _ output: ClipboardTransformOutput,
        for input: PasteboardContent
    ) -> Bool {
        guard !output.content.isEmpty,
              output.content != input,
              output.content.combinedUTF8ByteCount <=
                  PasteboardSnapshotReader.maximumCombinedBytes,
              output.removedParameterNames.indices.count > 0,
              output.removedParameterNames.indices.count <= Self.maximumRemovedNames,
              (input.plainText != nil) == (output.content.plainText != nil),
              (input.url != nil) == (output.content.url != nil)
        else {
            return false
        }

        if let inputPlainText = input.plainText,
           let outputPlainText = output.content.plainText,
           outputPlainText.utf8.count > inputPlainText.utf8.count
        {
            return false
        }
        if let inputURL = input.url,
           let outputURL = output.content.url,
           outputURL.utf8.count > inputURL.utf8.count
        {
            return false
        }
        if let outputPlainText = output.content.plainText,
           let outputURL = output.content.url
        {
            guard PlainTextEnvelope.core(from: outputPlainText) == outputURL else {
                return false
            }
        }

        return output.removedParameterNames.allSatisfy { name in
            guard !name.isEmpty, name.utf8.count <= Self.maximumRemovedNameBytes else {
                return false
            }
            return !name.unicodeScalars.contains { scalar in
                CharacterSet.controlCharacters.contains(scalar)
            }
        }
    }

    private func registerSuccessfulWrite(
        original: PasteboardContent,
        output: PasteboardContent
    ) {
        let currentUptime = uptime()
        if let previousUptime = recentWritePairs.last?.uptime,
           currentUptime < previousUptime
        {
            recentWritePairs.removeAll(keepingCapacity: true)
        }

        recentWritePairs.removeAll {
            currentUptime - $0.uptime > Self.conflictWindow
        }
        recentWritePairs.append(RecentWritePair(
            original: original,
            output: output,
            uptime: currentUptime
        ))
        if recentWritePairs.count > Self.maximumRecentPairs {
            recentWritePairs.removeFirst(
                recentWritePairs.count - Self.maximumRecentPairs
            )
        }

        let repeatedPairCount = recentWritePairs.lazy.filter {
            $0.original == original && $0.output == output
        }.count
        if repeatedPairCount >= 3 {
            conflictState = .paused(sinceUptime: currentUptime)
            updateOperationalState()
            logger.record(.conflictPaused, count: repeatedPairCount)
        }
    }

    private func pruneExpiredRecentPairs() {
        guard let latestUptime = recentWritePairs.last?.uptime else {
            return
        }
        let currentUptime = uptime()
        if currentUptime < latestUptime {
            recentWritePairs.removeAll(keepingCapacity: true)
            return
        }
        recentWritePairs.removeAll {
            currentUptime - $0.uptime > Self.conflictWindow
        }
    }

    private func refreshPermissionAndBaselineIfChanged() -> Bool {
        let currentPermissionState = pasteboard.permissionState
        guard currentPermissionState != permissionState else {
            return false
        }
        permissionState = currentPermissionState
        baselineCurrentGeneration()
        updateOperationalState()
        return true
    }

    private func expirePauseAndBaselineIfNeeded() -> Bool {
        guard case .until = pauseState,
              let pauseDeadlineUptime,
              uptime() >= pauseDeadlineUptime
        else {
            return false
        }
        pauseState = .none
        self.pauseDeadlineUptime = nil
        stateStore.pauseUntil = nil
        stateStore.pauseIndefinitely = false
        baselineCurrentGeneration()
        updateOperationalState()
        return true
    }

    private func baselineCurrentGeneration() {
        let generation = pasteboard.generation
        if generation != lastObservedGeneration, generation != ownedGeneration {
            invalidateUndo()
        }
        lastObservedGeneration = generation
    }

    private func invalidateUndo() {
        undoToken = nil
        canRestoreOriginal = false
    }

    private func wipeSensitiveMemory(preservingConflict: Bool = false) {
        invalidateUndo()
        recentWritePairs.removeAll(keepingCapacity: false)
        ownedGeneration = nil
        if !preservingConflict {
            conflictState = .none
        }
        lastResult = nil
    }

    private func updateOperationalState() {
        if !requestedEnabled {
            operationalState = .disabled
        } else if !isAwake || !isSessionActive {
            operationalState = .lifecycleInactive
        } else if pauseState != .none {
            operationalState = .paused
        } else if conflictState != .none {
            operationalState = .clipboardConflict
        } else if !permissionState.permitsAutomaticReads {
            operationalState = .needsClipboardAccess
        } else {
            operationalState = .running
        }
    }

    private func publishIfManual(
        _ result: ClipboardActionResult,
        mode: ClipboardProcessingMode
    ) -> ClipboardActionResult {
        if mode == .manual {
            lastResult = result
        }
        return result
    }

    private func pollAndReturnTiming() -> (delay: Duration, tolerance: Duration) {
        pollOnce()
        if operationalState == .running {
            return (Self.activePollDelay, Self.activePollTolerance)
        }
        return (Self.inactivePollDelay, Self.inactivePollTolerance)
    }
}

extension ClipboardCoordinator: ClipboardLifecycleDelegate {
    public func clipboardLifecycleDidReceive(_ event: ClipboardLifecycleEvent) {
        switch event {
        case .willSleep:
            isAwake = false
            wipeSensitiveMemory(preservingConflict: true)
            updateOperationalState()
            logger.record(.lifecycleReset)

        case .didWake:
            isAwake = true
            wipeSensitiveMemory(preservingConflict: true)
            baselineCurrentGeneration()
            updateOperationalState()
            logger.record(.lifecycleReset)

        case .sessionDidResignActive:
            isSessionActive = false
            wipeSensitiveMemory(preservingConflict: true)
            updateOperationalState()
            logger.record(.lifecycleReset)

        case .sessionDidBecomeActive:
            isSessionActive = true
            wipeSensitiveMemory(preservingConflict: true)
            baselineCurrentGeneration()
            updateOperationalState()
            logger.record(.lifecycleReset)

        case .willTerminate:
            isAwake = false
            isSessionActive = false
            stopMonitoring(wipeClipboardDerivedMemory: true)
            updateOperationalState()
            logger.record(.lifecycleReset)
        }
    }
}
