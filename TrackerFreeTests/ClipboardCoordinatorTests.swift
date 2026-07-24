import Foundation
import XCTest
@testable import TrackerFree

final class ClipboardCoordinatorTests: XCTestCase {
    @MainActor
    func testStartupBaselinesExistingGenerationWithoutReadingOrCleaning() {
        let original = content("https://example.test/p?utm_source=x")
        let pasteboard = FakePasteboardClient(
            generation: 7,
            items: [FakePasteboardItem(content: original)]
        )
        var transformCount = 0
        let coordinator = makeCoordinator(
            pasteboard: pasteboard,
            transform: { input, revision in
                transformCount += 1
                return deterministicTransform(input, revision)
            }
        )

        coordinator.pollOnce()

        XCTAssertEqual(transformCount, 0)
        XCTAssertEqual(pasteboard.itemInventoryReadCount, 0)
        XCTAssertEqual(pasteboard.currentHostOnlyPrepareCount, 0)
        XCTAssertNil(coordinator.lastResult)
    }

    @MainActor
    func testAutomaticCleanUsesMarkerCurrentHostOnlyOwnWriteSuppressionAndUndo() {
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)
        let original = content("https://example.test/p?utm_source=x")
        let cleaned = content("https://example.test/p")

        pasteboard.replaceExternally(with: original)
        coordinator.pollOnce()

        XCTAssertEqual(
            coordinator.lastResult,
            .cleaned(removedParameterNames: ["utm_source"])
        )
        XCTAssertEqual(pasteboard.currentHostOnlyPrepareCount, 1)
        XCTAssertEqual(pasteboard.committedWriteCount, 1)
        XCTAssertEqual(pasteboard.items, [
            FakePasteboardItem(
                content: cleaned,
                includesTrackerFreeMarker: true
            ),
        ])
        XCTAssertTrue(coordinator.canRestoreOriginal)

        let readsAfterCommit = pasteboard.representationReadCount
        coordinator.pollOnce()
        XCTAssertEqual(pasteboard.committedWriteCount, 1)
        XCTAssertEqual(pasteboard.representationReadCount, readsAfterCommit)

        XCTAssertEqual(coordinator.restoreOriginal(), .restored)
        XCTAssertEqual(
            pasteboard.items,
            [FakePasteboardItem(content: original)]
        )
        XCTAssertEqual(pasteboard.currentHostOnlyPrepareCount, 2)
        XCTAssertFalse(coordinator.canRestoreOriginal)
    }

    @MainActor
    func testSkipIsConsumedOnlyByStableWouldChangeAutomaticValue() {
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)
        coordinator.armSkipNextQualifyingURL()

        pasteboard.replaceExternally(with: [
            FakePasteboardItem(representations: [
                PasteboardTypeIdentifier.plainText: Data(
                    "https://example.test/p?utm_source=x".utf8
                ),
                "public.html": Data("<a>synthetic</a>".utf8),
            ]),
        ])
        coordinator.pollOnce()
        XCTAssertTrue(coordinator.skipNextIsArmed)
        XCTAssertEqual(pasteboard.committedWriteCount, 0)

        pasteboard.replaceExternally(with: content("https://example.test/p?q=swift"))
        coordinator.pollOnce()
        XCTAssertTrue(coordinator.skipNextIsArmed)
        XCTAssertEqual(pasteboard.committedWriteCount, 0)

        let qualifying = content("https://example.test/p?utm_source=x")
        pasteboard.replaceExternally(with: qualifying)
        coordinator.pollOnce()
        XCTAssertFalse(coordinator.skipNextIsArmed)
        XCTAssertEqual(coordinator.lastResult, .skipped)
        XCTAssertEqual(pasteboard.items, [FakePasteboardItem(content: qualifying)])
        XCTAssertEqual(pasteboard.committedWriteCount, 0)
    }

    @MainActor
    func testDisabledPausedAndPermissionBlockedTicksReadGenerationOnly() {
        let clock = TestClock(
            date: Date(timeIntervalSince1970: 10_000),
            uptime: 0
        )
        let pasteboard = FakePasteboardClient(permissionState: .alwaysAllow)
        let store = InMemoryClipboardCoordinatorStateStore(requestedEnabled: false)
        let coordinator = makeCoordinator(
            pasteboard: pasteboard,
            store: store,
            now: { clock.date },
            uptime: { clock.uptime }
        )

        pasteboard.replaceExternally(
            with: content("https://example.test/p?utm_source=x")
        )
        coordinator.pollOnce()
        XCTAssertEqual(pasteboard.itemInventoryReadCount, 0)

        coordinator.setRequestedEnabled(true)
        coordinator.pause(for: 300)
        pasteboard.replaceExternally(
            with: content("https://example.test/other?utm_source=x")
        )
        coordinator.pollOnce()
        XCTAssertEqual(pasteboard.itemInventoryReadCount, 0)

        clock.date = clock.date.addingTimeInterval(301)
        clock.uptime += 301
        coordinator.pollOnce()
        XCTAssertEqual(coordinator.pauseState, .none)
        XCTAssertEqual(pasteboard.itemInventoryReadCount, 0)

        pasteboard.permissionState = .alwaysDeny
        coordinator.refreshPermissionState()
        pasteboard.replaceExternally(
            with: content("https://example.test/third?utm_source=x")
        )
        coordinator.pollOnce()
        XCTAssertEqual(coordinator.operationalState, .needsClipboardAccess)
        XCTAssertEqual(pasteboard.itemInventoryReadCount, 0)

        pasteboard.permissionState = .alwaysAllow
        coordinator.pollOnce()
        XCTAssertEqual(coordinator.operationalState, .running)
        XCTAssertEqual(pasteboard.itemInventoryReadCount, 0)

        pasteboard.replaceExternally(
            with: content("https://example.test/fourth?utm_source=x")
        )
        coordinator.pollOnce()
        XCTAssertGreaterThan(pasteboard.itemInventoryReadCount, 0)
    }

    @MainActor
    func testLiveTimedPauseUsesMonotonicUptimeAcrossWallClockChanges() throws {
        let clock = TestClock(
            date: Date(timeIntervalSince1970: 10_000),
            uptime: 1_000
        )
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(
            pasteboard: pasteboard,
            now: { clock.date },
            uptime: { clock.uptime }
        )

        coordinator.pause(for: 300)
        clock.date = clock.date.addingTimeInterval(86_400)
        clock.uptime += 299
        coordinator.pollOnce()
        XCTAssertEqual(coordinator.operationalState, .paused)
        XCTAssertEqual(
            try XCTUnwrap(coordinator.pauseTimeRemaining),
            1,
            accuracy: 0.001
        )

        clock.date = clock.date.addingTimeInterval(-172_800)
        clock.uptime += 2
        coordinator.pollOnce()
        XCTAssertEqual(coordinator.pauseState, .none)
        XCTAssertEqual(coordinator.operationalState, .running)
    }

    @MainActor
    func testPermissionPromptAttemptBaselinesNewGenerationBeforeCleaning() {
        let preexisting = content(
            "https://example.test/preexisting?utm_source=x"
        )
        let pasteboard = FakePasteboardClient(
            generation: 7,
            items: [FakePasteboardItem(content: preexisting)],
            permissionState: .defaultBehavior
        )
        let store = InMemoryClipboardCoordinatorStateStore(
            requestedEnabled: true,
            hasPresentedPermissionExplanation: true
        )
        let coordinator = makeCoordinator(
            pasteboard: pasteboard,
            store: store
        )

        coordinator.pollOnce()
        XCTAssertEqual(pasteboard.representationReadCount, 0)

        let promptGeneration = content(
            "https://example.test/prompt?utm_source=x"
        )
        pasteboard.replaceExternally(with: promptGeneration)
        pasteboard.permissionStateAfterNextDataRead = .alwaysAllow
        coordinator.pollOnce()

        XCTAssertGreaterThan(pasteboard.representationReadCount, 0)
        XCTAssertEqual(pasteboard.committedWriteCount, 0)
        XCTAssertEqual(
            pasteboard.items,
            [FakePasteboardItem(content: promptGeneration)]
        )
        XCTAssertEqual(coordinator.operationalState, .running)

        pasteboard.replaceExternally(
            with: content("https://example.test/next?utm_source=x")
        )
        coordinator.pollOnce()
        XCTAssertEqual(pasteboard.committedWriteCount, 1)
    }

    @MainActor
    func testManualCleanBypassesDisabledPausePermissionAndSkip() {
        let original = content("https://example.test/p?utm_source=x")
        let pasteboard = FakePasteboardClient(
            generation: 1,
            items: [FakePasteboardItem(content: original)],
            permissionState: .alwaysDeny
        )
        let store = InMemoryClipboardCoordinatorStateStore(
            requestedEnabled: false,
            pauseIndefinitely: true
        )
        let coordinator = makeCoordinator(pasteboard: pasteboard, store: store)
        coordinator.armSkipNextQualifyingURL()

        XCTAssertEqual(
            coordinator.cleanCurrentClipboard(),
            .cleaned(removedParameterNames: ["utm_source"])
        )
        XCTAssertTrue(coordinator.skipNextIsArmed)
        XCTAssertEqual(
            pasteboard.items,
            [
                FakePasteboardItem(
                    content: content("https://example.test/p"),
                    includesTrackerFreeMarker: true
                ),
            ]
        )
    }

    @MainActor
    func testGenerationRaceLeavesClipboardUnwrittenAndSkipArmed() {
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)
        coordinator.armSkipNextQualifyingURL()

        pasteboard.replaceExternally(
            with: content("https://example.test/p?utm_source=x")
        )
        pasteboard.changeGenerationAfterNextDataRead = true
        coordinator.pollOnce()

        XCTAssertTrue(coordinator.skipNextIsArmed)
        XCTAssertEqual(pasteboard.currentHostOnlyPrepareCount, 0)
        XCTAssertEqual(pasteboard.committedWriteCount, 0)
    }

    @MainActor
    func testUnavailableAllowedRepresentationLeavesClipboardUnchanged() {
        let original = content("https://example.test/p?utm_source=x")
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)
        pasteboard.replaceExternally(with: original)
        pasteboard.failNextDataRead = true

        coordinator.pollOnce()

        XCTAssertEqual(
            pasteboard.items,
            [FakePasteboardItem(content: original)]
        )
        XCTAssertEqual(pasteboard.currentHostOnlyPrepareCount, 0)
        XCTAssertEqual(pasteboard.committedWriteCount, 0)
    }

    @MainActor
    func testRuleRevisionRaceLeavesClipboardUnwrittenAndSkipArmed() {
        let pasteboard = FakePasteboardClient()
        var revision: ClipboardRuleRevision = 1
        let coordinator = makeCoordinator(
            pasteboard: pasteboard,
            transform: { input, capturedRevision in
                revision = 2
                return deterministicTransform(input, capturedRevision)
            },
            revision: { revision }
        )
        coordinator.armSkipNextQualifyingURL()

        pasteboard.replaceExternally(
            with: content("https://example.test/p?utm_source=x")
        )
        coordinator.pollOnce()

        XCTAssertTrue(coordinator.skipNextIsArmed)
        XCTAssertEqual(pasteboard.currentHostOnlyPrepareCount, 0)
        XCTAssertEqual(pasteboard.committedWriteCount, 0)
    }

    @MainActor
    func testFailedWriteRollsBackOnlyWhileAppStillOwnsGeneration() {
        let original = content("https://example.test/p?utm_source=x")
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)
        pasteboard.replaceExternally(with: original)
        pasteboard.failNextCommit = true

        coordinator.pollOnce()

        XCTAssertEqual(coordinator.lastResult, .writeFailed)
        XCTAssertEqual(pasteboard.currentHostOnlyPrepareCount, 2)
        XCTAssertEqual(pasteboard.committedWriteCount, 2)
        XCTAssertEqual(pasteboard.items, [FakePasteboardItem(content: original)])
        XCTAssertFalse(coordinator.canRestoreOriginal)

        let readsAfterRollback = pasteboard.representationReadCount
        coordinator.pollOnce()
        XCTAssertEqual(pasteboard.representationReadCount, readsAfterRollback)
    }

    @MainActor
    func testCorruptReadbackRollsBackOnlyOwnedGeneration() {
        let original = content("https://example.test/p?utm_source=x")
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)
        pasteboard.replaceExternally(with: original)
        pasteboard.corruptNextCommittedWrite = true

        coordinator.pollOnce()

        XCTAssertEqual(coordinator.lastResult, .writeFailed)
        XCTAssertEqual(pasteboard.currentHostOnlyPrepareCount, 2)
        XCTAssertEqual(pasteboard.committedWriteCount, 2)
        XCTAssertEqual(
            pasteboard.items,
            [FakePasteboardItem(content: original)]
        )
        XCTAssertFalse(coordinator.canRestoreOriginal)
    }

    @MainActor
    func testReplacementConstructionFailureNeverClearsClipboard() {
        let original = content("https://example.test/p?utm_source=x")
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)
        pasteboard.replaceExternally(with: original)
        pasteboard.failNextPrepareWrite = true

        coordinator.pollOnce()

        XCTAssertEqual(coordinator.lastResult, .writeFailed)
        XCTAssertEqual(pasteboard.currentHostOnlyPrepareCount, 0)
        XCTAssertEqual(pasteboard.committedWriteCount, 0)
        XCTAssertEqual(pasteboard.items, [FakePasteboardItem(content: original)])
    }

    @MainActor
    func testReadbackOwnershipLossNeverRollsBackOverNewGeneration() {
        let original = content("https://example.test/p?utm_source=x")
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(
            pasteboard: pasteboard,
            transform: { input, revision in
                pasteboard.changeGenerationAfterNextDataRead = true
                return deterministicTransform(input, revision)
            }
        )
        pasteboard.replaceExternally(with: original)

        coordinator.pollOnce()

        XCTAssertEqual(coordinator.lastResult, .writeFailed)
        XCTAssertEqual(pasteboard.currentHostOnlyPrepareCount, 1)
        XCTAssertEqual(pasteboard.committedWriteCount, 1)
        XCTAssertFalse(coordinator.canRestoreOriginal)
    }

    @MainActor
    func testExternalWriteAfterClearIsNeverOverwritten() {
        let original = content("https://example.test/p?utm_source=x")
        let newer = content("https://newer.example.test/value")
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)
        pasteboard.replaceExternally(with: original)
        pasteboard.externalItemsAfterNextPrepare = [
            FakePasteboardItem(content: newer),
        ]

        coordinator.pollOnce()

        XCTAssertEqual(coordinator.lastResult, .writeFailed)
        XCTAssertEqual(
            pasteboard.items,
            [FakePasteboardItem(content: newer)]
        )
        XCTAssertEqual(pasteboard.currentHostOnlyPrepareCount, 1)
        XCTAssertEqual(pasteboard.committedWriteCount, 0)
        XCTAssertFalse(coordinator.canRestoreOriginal)
    }

    @MainActor
    func testExternalWriteAfterCommitIsNeverRolledBackOver() {
        let original = content("https://example.test/p?utm_source=x")
        let newer = content("https://newer.example.test/value")
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)
        pasteboard.replaceExternally(with: original)
        pasteboard.externalItemsAfterNextCommit = [
            FakePasteboardItem(content: newer),
        ]

        coordinator.pollOnce()

        XCTAssertEqual(coordinator.lastResult, .writeFailed)
        XCTAssertEqual(
            pasteboard.items,
            [FakePasteboardItem(content: newer)]
        )
        XCTAssertEqual(pasteboard.currentHostOnlyPrepareCount, 1)
        XCTAssertEqual(pasteboard.committedWriteCount, 1)
        XCTAssertFalse(coordinator.canRestoreOriginal)
    }

    @MainActor
    func testUndoNeverOverwritesNewerExternalGeneration() {
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)
        pasteboard.replaceExternally(
            with: content("https://example.test/p?utm_source=x")
        )
        coordinator.pollOnce()
        XCTAssertTrue(coordinator.canRestoreOriginal)

        let newer = content("https://newer.example.test/value")
        pasteboard.replaceExternally(with: newer)

        XCTAssertEqual(coordinator.restoreOriginal(), .restoreUnavailable)
        XCTAssertEqual(pasteboard.items, [FakePasteboardItem(content: newer)])
        XCTAssertFalse(coordinator.canRestoreOriginal)
    }

    @MainActor
    func testIdenticalExternalTextAtNewGenerationIsProcessedAgain() {
        let original = content("https://example.test/p?utm_source=x")
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)

        pasteboard.replaceExternally(with: original)
        coordinator.pollOnce()
        XCTAssertEqual(pasteboard.committedWriteCount, 1)

        pasteboard.replaceExternally(with: original)
        coordinator.pollOnce()
        XCTAssertEqual(pasteboard.committedWriteCount, 2)
    }

    @MainActor
    func testConflictPausesAfterThreeMatchingPairsAndExplicitResumeBaselines() {
        let clock = TestClock(
            date: Date(timeIntervalSince1970: 0),
            uptime: 100
        )
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(
            pasteboard: pasteboard,
            uptime: { clock.uptime }
        )
        let original = content("https://example.test/p?utm_source=x")

        for _ in 0..<3 {
            pasteboard.replaceExternally(with: original)
            coordinator.pollOnce()
            clock.uptime += 0.5
        }

        guard case .paused = coordinator.conflictState else {
            return XCTFail("Expected conflict pause")
        }
        XCTAssertEqual(coordinator.operationalState, .clipboardConflict)

        coordinator.resumeAutomaticCleaningAfterConflict()
        XCTAssertEqual(coordinator.conflictState, .none)
        XCTAssertEqual(coordinator.operationalState, .running)

        let writesBeforeBaseline = pasteboard.committedWriteCount
        coordinator.pollOnce()
        XCTAssertEqual(pasteboard.committedWriteCount, writesBeforeBaseline)
    }

    @MainActor
    func testConflictRequiresExplicitResumeAndNeverReadsWhilePaused() {
        let clock = TestClock(
            date: Date(timeIntervalSince1970: 0),
            uptime: 200
        )
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(
            pasteboard: pasteboard,
            uptime: { clock.uptime }
        )
        let original = content("https://example.test/p?utm_source=x")

        for _ in 0..<3 {
            pasteboard.replaceExternally(with: original)
            coordinator.pollOnce()
            clock.uptime += 0.5
        }
        guard case .paused = coordinator.conflictState else {
            return XCTFail("Expected conflict pause")
        }

        pasteboard.replaceExternally(
            with: content("https://example.test/quiet?utm_source=x")
        )
        let readsBeforeQuietGeneration = pasteboard.representationReadCount
        coordinator.pollOnce()
        XCTAssertNotEqual(coordinator.conflictState, .none)
        XCTAssertEqual(
            pasteboard.representationReadCount,
            readsBeforeQuietGeneration
        )

        clock.uptime += 2.1
        pasteboard.replaceExternally(
            with: content("https://example.test/distinct?q=1")
        )
        coordinator.pollOnce()
        guard case .paused = coordinator.conflictState else {
            return XCTFail("Generation changes alone must not resume a conflict")
        }
        XCTAssertEqual(coordinator.operationalState, .clipboardConflict)
        XCTAssertEqual(
            pasteboard.representationReadCount,
            readsBeforeQuietGeneration
        )

        coordinator.resumeAutomaticCleaningAfterConflict()
        XCTAssertEqual(coordinator.conflictState, .none)
        XCTAssertEqual(coordinator.operationalState, .running)
    }

    @MainActor
    func testConflictSurvivesSleepAndSessionLifecycleRoundTrips() {
        let lifecyclePairs: [[ClipboardLifecycleEvent]] = [
            [.willSleep, .didWake],
            [.sessionDidResignActive, .sessionDidBecomeActive],
        ]

        for events in lifecyclePairs {
            let clock = TestClock(
                date: Date(timeIntervalSince1970: 0),
                uptime: 300
            )
            let pasteboard = FakePasteboardClient()
            let coordinator = makeCoordinator(
                pasteboard: pasteboard,
                uptime: { clock.uptime }
            )
            let original = content("https://example.test/p?utm_source=x")
            for _ in 0..<3 {
                pasteboard.replaceExternally(with: original)
                coordinator.pollOnce()
                clock.uptime += 0.5
            }
            guard case .paused = coordinator.conflictState else {
                return XCTFail("Expected conflict before \(events)")
            }

            events.forEach(coordinator.clipboardLifecycleDidReceive)

            guard case .paused = coordinator.conflictState else {
                return XCTFail("Lifecycle round-trip silently cleared conflict")
            }
            XCTAssertEqual(coordinator.operationalState, .clipboardConflict)
            let readsBefore = pasteboard.representationReadCount
            pasteboard.replaceExternally(
                with: content("https://example.test/new?utm_source=x")
            )
            coordinator.pollOnce()
            XCTAssertEqual(pasteboard.representationReadCount, readsBefore)
            XCTAssertEqual(coordinator.operationalState, .clipboardConflict)
        }
    }

    @MainActor
    func testLifecycleWipesUndoAndBaselinesContentCopiedWhileInactive() {
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)
        pasteboard.replaceExternally(
            with: content("https://example.test/p?utm_source=x")
        )
        coordinator.pollOnce()
        XCTAssertTrue(coordinator.canRestoreOriginal)

        coordinator.clipboardLifecycleDidReceive(.willSleep)
        XCTAssertEqual(coordinator.operationalState, .lifecycleInactive)
        XCTAssertFalse(coordinator.canRestoreOriginal)

        let readsBeforeSleepCopy = pasteboard.representationReadCount
        pasteboard.replaceExternally(
            with: content("https://example.test/asleep?utm_source=x")
        )
        coordinator.pollOnce()
        XCTAssertEqual(pasteboard.representationReadCount, readsBeforeSleepCopy)

        coordinator.clipboardLifecycleDidReceive(.didWake)
        coordinator.pollOnce()
        XCTAssertEqual(pasteboard.representationReadCount, readsBeforeSleepCopy)
        XCTAssertEqual(coordinator.operationalState, .running)
    }

    @MainActor
    func testSessionLossAndTerminationWipeStateAndPreventReads() {
        let pasteboard = FakePasteboardClient()
        let coordinator = makeCoordinator(pasteboard: pasteboard)
        pasteboard.replaceExternally(
            with: content("https://example.test/p?utm_source=x")
        )
        coordinator.pollOnce()
        XCTAssertTrue(coordinator.canRestoreOriginal)

        coordinator.clipboardLifecycleDidReceive(.sessionDidResignActive)
        XCTAssertEqual(coordinator.operationalState, .lifecycleInactive)
        XCTAssertFalse(coordinator.canRestoreOriginal)

        let readsBeforeInactiveCopy = pasteboard.representationReadCount
        pasteboard.replaceExternally(
            with: content("https://example.test/inactive?utm_source=x")
        )
        coordinator.pollOnce()
        XCTAssertEqual(
            pasteboard.representationReadCount,
            readsBeforeInactiveCopy
        )

        coordinator.clipboardLifecycleDidReceive(.sessionDidBecomeActive)
        XCTAssertEqual(coordinator.operationalState, .running)
        coordinator.clipboardLifecycleDidReceive(.willTerminate)
        XCTAssertEqual(coordinator.operationalState, .lifecycleInactive)

        pasteboard.replaceExternally(
            with: content("https://example.test/terminated?utm_source=x")
        )
        coordinator.pollOnce()
        XCTAssertEqual(
            pasteboard.representationReadCount,
            readsBeforeInactiveCopy
        )
    }

    @MainActor
    func testTimedPausePersistsAcrossRelaunchUsingWallClockBootstrap()
        throws
    {
        let clock = TestClock(
            date: Date(timeIntervalSince1970: 50_000),
            uptime: 1_000
        )
        let store = InMemoryClipboardCoordinatorStateStore(
            requestedEnabled: true
        )
        let first = makeCoordinator(
            pasteboard: FakePasteboardClient(),
            store: store,
            now: { clock.date },
            uptime: { clock.uptime }
        )
        first.pause(for: 300)

        clock.date = clock.date.addingTimeInterval(100)
        clock.uptime = 50
        let relaunched = makeCoordinator(
            pasteboard: FakePasteboardClient(),
            store: store,
            now: { clock.date },
            uptime: { clock.uptime }
        )

        XCTAssertEqual(relaunched.operationalState, .paused)
        XCTAssertEqual(
            try XCTUnwrap(relaunched.pauseTimeRemaining),
            200,
            accuracy: 0.001
        )
    }

    @MainActor
    func testIndefinitePauseAndResumePersistenceAcrossRelaunch() {
        let store = InMemoryClipboardCoordinatorStateStore(
            requestedEnabled: true
        )
        let first = makeCoordinator(
            pasteboard: FakePasteboardClient(),
            store: store
        )
        first.pauseIndefinitely()

        let pausedRelaunch = makeCoordinator(
            pasteboard: FakePasteboardClient(),
            store: store
        )
        XCTAssertEqual(pausedRelaunch.pauseState, .indefinitely)
        pausedRelaunch.resumeNow()

        let resumedRelaunch = makeCoordinator(
            pasteboard: FakePasteboardClient(),
            store: store
        )
        XCTAssertEqual(resumedRelaunch.pauseState, .none)
        XCTAssertEqual(resumedRelaunch.operationalState, .running)
    }

    @MainActor
    func testOperationalTransitionsDuringTransformPreventAutomaticCommit() {
        enum Transition {
            case disable
            case pause
            case sleep
            case sessionResign
        }

        for transition in [
            Transition.disable,
            .pause,
            .sleep,
            .sessionResign,
        ] {
            let pasteboard = FakePasteboardClient()
            var coordinator: ClipboardCoordinator!
            coordinator = makeCoordinator(
                pasteboard: pasteboard,
                transform: { input, revision in
                    switch transition {
                    case .disable:
                        coordinator.setRequestedEnabled(false)
                    case .pause:
                        coordinator.pauseIndefinitely()
                    case .sleep:
                        coordinator.clipboardLifecycleDidReceive(.willSleep)
                    case .sessionResign:
                        coordinator.clipboardLifecycleDidReceive(
                            .sessionDidResignActive
                        )
                    }
                    return deterministicTransform(input, revision)
                }
            )
            pasteboard.replaceExternally(
                with: content("https://example.test/p?utm_source=x")
            )

            coordinator.pollOnce()

            XCTAssertEqual(
                pasteboard.committedWriteCount,
                0,
                "\(transition) must invalidate the in-flight automatic write"
            )
            XCTAssertNotEqual(coordinator.operationalState, .running)
        }
    }

    @MainActor
    func testSnapshotEnforcesExactlyOneItemTypeAllowlistSizeAndDualAgreement() {
        let pasteboard = FakePasteboardClient()

        let matchingDual = PasteboardContent(
            plainText: " \thttps://example.test/p?utm_source=x \r\n",
            url: "https://example.test/p?utm_source=x"
        )
        pasteboard.replaceExternally(with: matchingDual)
        XCTAssertEqual(
            PasteboardSnapshotReader.capture(
                from: pasteboard,
                expectedGeneration: pasteboard.generation
            ),
            .success(PasteboardSnapshot(
                generation: pasteboard.generation,
                content: matchingDual
            ))
        )

        pasteboard.replaceExternally(with: PasteboardContent(
            plainText: "https://example.test/a",
            url: "https://example.test/b"
        ))
        XCTAssertEqual(
            PasteboardSnapshotReader.capture(
                from: pasteboard,
                expectedGeneration: pasteboard.generation
            ),
            .failure(.conflictingRepresentations)
        )

        pasteboard.replaceExternally(with: [
            FakePasteboardItem(content: content("https://example.test/a")),
            FakePasteboardItem(content: content("https://example.test/b")),
        ])
        XCTAssertEqual(
            PasteboardSnapshotReader.capture(
                from: pasteboard,
                expectedGeneration: pasteboard.generation
            ),
            .failure(.requiresExactlyOneItem)
        )

        pasteboard.replaceExternally(with: [
            FakePasteboardItem(representations: [
                PasteboardTypeIdentifier.plainText: Data(
                    "https://example.test/p".utf8
                ),
                "public.rtf": Data("{\\rtf1 synthetic}".utf8),
            ]),
        ])
        XCTAssertEqual(
            PasteboardSnapshotReader.capture(
                from: pasteboard,
                expectedGeneration: pasteboard.generation
            ),
            .failure(.unsupportedType)
        )

        pasteboard.replaceExternally(
            with: content("https://example.test/p?utm_source=x"),
            includesTrackerFreeMarker: true
        )
        XCTAssertEqual(
            PasteboardSnapshotReader.capture(
                from: pasteboard,
                expectedGeneration: pasteboard.generation
            ),
            .failure(.appMarkerFromUnownedGeneration)
        )

        pasteboard.replaceExternally(with: PasteboardContent(
            plainText: String(repeating: "a", count: 65_537)
        ))
        XCTAssertEqual(
            PasteboardSnapshotReader.capture(
                from: pasteboard,
                expectedGeneration: pasteboard.generation
            ),
            .failure(.sizeLimitExceeded)
        )

        pasteboard.replaceExternally(
            with: content("https://example.test/p?utm_source=x")
        )
        pasteboard.delayNextDataRead = 0.11
        XCTAssertEqual(
            PasteboardSnapshotReader.capture(
                from: pasteboard,
                expectedGeneration: pasteboard.generation
            ),
            .failure(.representationUnavailable)
        )
    }
}

@MainActor
private func makeCoordinator(
    pasteboard: FakePasteboardClient,
    store: InMemoryClipboardCoordinatorStateStore =
        InMemoryClipboardCoordinatorStateStore(requestedEnabled: true),
    now: @escaping @MainActor () -> Date = { Date() },
    uptime: @escaping @MainActor () -> TimeInterval = {
        ProcessInfo.processInfo.systemUptime
    },
    transform: @escaping ClipboardTransformClosure = deterministicTransform,
    revision: @escaping ClipboardRuleRevisionProvider = { 1 }
) -> ClipboardCoordinator {
    ClipboardCoordinator(
        pasteboard: pasteboard,
        stateStore: store,
        transform: transform,
        ruleRevision: revision,
        now: now,
        uptime: uptime,
        automaticallyStartsMonitoring: false
    )
}

private func content(_ plainText: String) -> PasteboardContent {
    PasteboardContent(plainText: plainText)
}

@MainActor
private final class TestClock {
    var date: Date
    var uptime: TimeInterval

    init(date: Date, uptime: TimeInterval) {
        self.date = date
        self.uptime = uptime
    }
}

@MainActor
private func deterministicTransform(
    _ input: ClipboardTransformInput,
    _: ClipboardRuleRevision
) -> ClipboardTransformDecision {
    func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "?utm_source=x&", with: "?")
            .replacingOccurrences(of: "&utm_source=x", with: "")
            .replacingOccurrences(of: "?utm_source=x", with: "")
    }

    let output = PasteboardContent(
        plainText: input.content.plainText.map(clean),
        url: input.content.url.map(clean)
    )
    guard output != input.content else {
        return .unchanged(.noKnownTrackingParameters)
    }
    return .changed(ClipboardTransformOutput(
        content: output,
        removedParameterNames: ["utm_source"]
    ))
}
