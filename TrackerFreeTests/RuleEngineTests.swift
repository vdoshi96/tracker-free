import Foundation
import XCTest
@testable import TrackerFree

enum TestRuleFactory {
    static func rule(
        id: String,
        enabled: Bool = true,
        origin: RuleOrigin = .builtIn,
        action: RuleAction,
        matcher: RuleMatcher = .exactASCIIName,
        name: String,
        caseSensitivity: RuleCaseSensitivity = .caseSensitive,
        scope: RuleScope = .global,
        hosts: [String] = [],
        includeSubdomains: Bool = false,
        pathConstraint: SafePathConstraint? = nil,
        explanation: String = "VERIFIED: synthetic rule used only by tests.",
        provenanceURL: String = ""
    ) -> CleaningRule {
        CleaningRule(
            id: id,
            enabled: enabled,
            origin: origin,
            action: action,
            matcher: matcher,
            name: name,
            caseSensitivity: caseSensitivity,
            scope: scope,
            hosts: hosts,
            includeSubdomains: includeSubdomains,
            pathConstraint: pathConstraint,
            confidence: .verified,
            explanation: explanation,
            provenanceURL: provenanceURL
        )
    }

    static func snapshot(
        _ rules: [CleaningRule],
        revision: UInt64 = 1
    ) throws -> RuleSetSnapshot {
        try RuleSetSnapshot(
            revision: revision,
            reviewedDate: "2026-07-23",
            rules: rules
        )
    }

    static func builtInSnapshot() throws -> RuleSetSnapshot {
        if let bundledURL = Bundle.main.url(
            forResource: "BuiltInRules",
            withExtension: "json"
        ) {
            return try BuiltInRuleLoader.load(
                data: Data(contentsOf: bundledURL)
            )
        }
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TrackerFree/Resources/BuiltInRules.json")
        return try BuiltInRuleLoader.load(data: Data(contentsOf: sourceURL))
    }

    static func context(
        _ input: String
    ) throws -> (RecognizedURL, TokenizedRawQuery, RawQueryField) {
        let url = try URLRecognizer.recognize(input).get()
        let query = try RawQueryTokenizer.tokenize(
            try XCTUnwrap(url.rawQuery)
        ).get()
        return (url, query, try XCTUnwrap(query.fields.first))
    }
}

final class RuleEngineTests: XCTestCase {
    func testHostPathRemovalOverridesLessSpecificBuiltInPreserve() throws {
        let preserve = TestRuleFactory.rule(
            id: "preserve.s",
            action: .preserveParameter,
            name: "s"
        )
        let remove = TestRuleFactory.rule(
            id: "remove.s.posts",
            action: .removeParameter,
            name: "s",
            scope: .hostPath,
            hosts: ["example.com"],
            includeSubdomains: true,
            pathConstraint: SafePathConstraint(
                kind: .literalPrefix,
                value: "/posts"
            )
        )
        let snapshot = try TestRuleFactory.snapshot([preserve, remove])
        let (url, query, field) = try TestRuleFactory.context(
            "https://sub.example.com/posts/123?s=1"
        )

        XCTAssertEqual(
            RuleEngine(snapshot: snapshot).decision(
                for: field,
                in: url,
                query: query
            ),
            .remove(RuleMatch(rule: remove))
        )
    }

    func testHostMatchingDoesNotUseNaiveSuffixes() throws {
        let remove = TestRuleFactory.rule(
            id: "remove.scoped",
            action: .removeParameter,
            name: "x",
            scope: .host,
            hosts: ["example.com"],
            includeSubdomains: true
        )
        let snapshot = try TestRuleFactory.snapshot([remove])
        let (url, query, field) = try TestRuleFactory.context(
            "https://notexample.com/?x=1"
        )

        XCTAssertEqual(
            RuleEngine(snapshot: snapshot).decision(
                for: field,
                in: url,
                query: query
            ),
            .preserve(nil)
        )
    }

    func testEqualBuiltInSpecificityPreserves() throws {
        let remove = TestRuleFactory.rule(
            id: "remove.x",
            action: .removeParameter,
            name: "x"
        )
        let preserve = TestRuleFactory.rule(
            id: "preserve.x",
            action: .preserveParameter,
            name: "x"
        )
        let snapshot = try TestRuleFactory.snapshot([remove, preserve])
        let (url, query, field) = try TestRuleFactory.context(
            "https://example.com/?x=1"
        )

        XCTAssertEqual(
            RuleEngine(snapshot: snapshot).decision(
                for: field,
                in: url,
                query: query
            ),
            .preserve(RuleMatch(rule: preserve))
        )
    }

    func testExactMatcherWinsOverPrefixAtEqualActionAndScope() throws {
        let prefix = TestRuleFactory.rule(
            id: "remove.prefix",
            action: .removeParameter,
            matcher: .asciiPrefix,
            name: "utm_"
        )
        let exact = TestRuleFactory.rule(
            id: "remove.exact",
            action: .removeParameter,
            name: "utm_source"
        )
        let snapshot = try TestRuleFactory.snapshot([prefix, exact])
        let (url, query, field) = try TestRuleFactory.context(
            "https://example.com/?utm_source=x"
        )

        XCTAssertEqual(
            RuleEngine(snapshot: snapshot).decision(
                for: field,
                in: url,
                query: query
            ),
            .remove(RuleMatch(rule: exact))
        )
    }

    func testUserPreservePrecedesBuiltInRemoval() throws {
        let builtIn = TestRuleFactory.rule(
            id: "builtin.remove.x",
            action: .removeParameter,
            name: "x"
        )
        let user = TestRuleFactory.rule(
            id: "user.preserve.x",
            origin: .user,
            action: .preserveParameter,
            name: "x"
        )
        let snapshot = try TestRuleFactory.snapshot([builtIn, user])
        let (url, query, field) = try TestRuleFactory.context(
            "https://example.com/?x=1"
        )

        XCTAssertEqual(
            RuleEngine(snapshot: snapshot).decision(
                for: field,
                in: url,
                query: query
            ),
            .preserve(RuleMatch(rule: user))
        )
    }

    func testUserRemovalPrecedesBuiltInPreserve() throws {
        let builtIn = TestRuleFactory.rule(
            id: "builtin.preserve.x",
            action: .preserveParameter,
            name: "x"
        )
        let user = TestRuleFactory.rule(
            id: "user.remove.x",
            origin: .user,
            action: .removeParameter,
            name: "x"
        )
        let snapshot = try TestRuleFactory.snapshot([builtIn, user])
        let (url, query, field) = try TestRuleFactory.context(
            "https://example.com/?x=1"
        )

        XCTAssertEqual(
            RuleEngine(snapshot: snapshot).decision(
                for: field,
                in: url,
                query: query
            ),
            .remove(RuleMatch(rule: user))
        )
    }

    func testEncodedPathDoesNotMatchRemovalConstraint() throws {
        let preserve = TestRuleFactory.rule(
            id: "preserve.x",
            action: .preserveParameter,
            name: "x"
        )
        let scopedRemoval = TestRuleFactory.rule(
            id: "remove.path",
            action: .removeParameter,
            name: "x",
            scope: .hostPath,
            hosts: ["example.com"],
            pathConstraint: SafePathConstraint(
                kind: .literalPrefix,
                value: "/post"
            )
        )
        let snapshot = try TestRuleFactory.snapshot([preserve, scopedRemoval])
        let (url, query, field) = try TestRuleFactory.context(
            "https://example.com/post%2Fhidden?x=1"
        )

        XCTAssertEqual(
            RuleEngine(snapshot: snapshot).decision(
                for: field,
                in: url,
                query: query
            ),
            .preserve(RuleMatch(rule: preserve))
        )
    }

    func testContradictoryUserRulesAreRejectedAtomically() {
        let remove = TestRuleFactory.rule(
            id: "user.remove.x",
            origin: .user,
            action: .removeParameter,
            name: "x"
        )
        let preserve = TestRuleFactory.rule(
            id: "user.preserve.x",
            origin: .user,
            action: .preserveParameter,
            name: "x"
        )

        XCTAssertThrowsError(
            try TestRuleFactory.snapshot([remove, preserve])
        ) { error in
            guard case RuleValidationError.contradictoryUserRules = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRuleDocumentsRejectUnknownNonRuleFields() throws {
        let document = """
        {
          "schemaVersion": 1,
          "ruleSetRevision": 1,
          "reviewedDate": "2026-07-23",
          "clipboardSamples": ["must-not-be-accepted"],
          "rules": []
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RuleSetDocument.self,
                from: Data(document.utf8)
            )
        )
    }

    func testBundledRulesDecodeAndContainRequiredConservativeRules() throws {
        let snapshot = try TestRuleFactory.builtInSnapshot()
        let rulesByID = Dictionary(
            uniqueKeysWithValues: snapshot.rules.map { ($0.id, $0) }
        )

        XCTAssertGreaterThanOrEqual(snapshot.rules.count, 50)
        XCTAssertEqual(rulesByID["builtin.remove.utm_source"]?.enabled, true)
        XCTAssertEqual(rulesByID["builtin.remove.utm_prefix.disabled"]?.enabled, false)
        XCTAssertEqual(
            rulesByID["builtin.preserve.t"]?.action,
            .preserveParameter
        )
        XCTAssertEqual(
            rulesByID["builtin.remove.youtube.si"]?.scope,
            .hostPath
        )
    }

    @MainActor
    func testRuleStorePreviewsPersistsAndReloadsUserRules() throws {
        let builtIn = try TestRuleFactory.snapshot([
            TestRuleFactory.rule(
                id: "builtin.remove.utm_source",
                action: .removeParameter,
                name: "utm_source"
            ),
        ], revision: 10)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackerFreeRuleStore-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("CustomRules.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = RuleStore(
            builtInSnapshot: builtIn,
            userRulesFileURL: file
        )
        let userRule = TestRuleFactory.rule(
            id: "user.remove.campaign_id",
            origin: .user,
            action: .removeParameter,
            name: "campaign_id"
        )
        let importDocument = RuleSetDocument(
            schemaVersion: 1,
            ruleSetRevision: 1,
            reviewedDate: "2026-07-23",
            rules: [userRule]
        )
        let data = try JSONEncoder().encode(importDocument)
        let preview = try store.makeImportPreview(data)

        XCTAssertEqual(preview.ruleCount, 1)
        XCTAssertEqual(preview.enabledRemovalCount, 1)
        try store.applyImport(preview)
        XCTAssertEqual(store.userRules, [userRule])
        XCTAssertFalse(try store.exportUserRulesData().isEmpty)

        let reloaded = RuleStore(
            builtInSnapshot: builtIn,
            userRulesFileURL: file
        )
        XCTAssertNil(reloaded.loadIssue)
        XCTAssertEqual(reloaded.userRules, [userRule])
    }

    @MainActor
    func testPersistedUserRuleCollisionWithNewBuiltInIsReported() throws {
        let builtInRule = TestRuleFactory.rule(
            id: "shared.rule.id",
            enabled: false,
            action: .removeParameter,
            name: "utm_source"
        )
        let builtIn = try TestRuleFactory.snapshot([builtInRule])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackerFreeCollision-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("rules.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let collidingUserRule = TestRuleFactory.rule(
            id: builtInRule.id,
            origin: .user,
            action: .hardProtectURL,
            name: "secret"
        )
        let persisted = RuleSetDocument(
            schemaVersion: 1,
            ruleSetRevision: 2,
            reviewedDate: "2026-07-23",
            rules: [collidingUserRule]
        )
        try JSONEncoder().encode(persisted).write(to: file, options: [.atomic])

        let store = RuleStore(
            builtInSnapshot: builtIn,
            userRulesFileURL: file,
            enabledBuiltInRuleIDs: [builtInRule.id]
        )

        XCTAssertEqual(store.loadIssue, .customRuleFileInvalid)
        XCTAssertTrue(store.userRules.isEmpty)
        XCTAssertEqual(store.builtInRules.first?.enabled, true)
    }

    @MainActor
    func testPersistedRemovalThatOverridesBuiltInPreserveIsDisabledForReview()
        throws
    {
        let preserve = TestRuleFactory.rule(
            id: "builtin.preserve.q",
            action: .preserveParameter,
            name: "q"
        )
        let builtIn = try TestRuleFactory.snapshot([preserve])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackerFreeReview-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("rules.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let removal = TestRuleFactory.rule(
            id: "user.remove.q",
            origin: .user,
            action: .removeParameter,
            name: "q"
        )
        try JSONEncoder().encode(RuleSetDocument(
            schemaVersion: 1,
            ruleSetRevision: 2,
            reviewedDate: "2026-07-23",
            rules: [removal]
        )).write(to: file, options: [.atomic])

        let store = RuleStore(
            builtInSnapshot: builtIn,
            userRulesFileURL: file
        )

        XCTAssertEqual(store.loadIssue, .customRuleOverridesNeedReview)
        XCTAssertEqual(store.userRules.first?.enabled, false)
        XCTAssertThrowsError(
            try store.setUserRule(id: removal.id, enabled: true)
        ) {
            XCTAssertEqual(
                $0 as? RuleStoreError,
                .builtInPreserveOverrideRequiresConfirmation(["q"])
            )
        }
        try store.setUserRule(
            id: removal.id,
            enabled: true,
            acknowledgingBuiltInPreserveOverride: true
        )
        XCTAssertEqual(store.userRules.first?.enabled, true)

        let reloaded = RuleStore(
            builtInSnapshot: builtIn,
            userRulesFileURL: file
        )
        XCTAssertNil(reloaded.loadIssue)
        XCTAssertEqual(reloaded.userRules.first?.enabled, true)
    }

    @MainActor
    func testEnablingBuiltInPreserveRejectsUnreviewedUserRemovalOverlap()
        throws
    {
        let disabledPreserve = TestRuleFactory.rule(
            id: "builtin.preserve.q",
            enabled: false,
            action: .preserveParameter,
            name: "q"
        )
        let unrelatedRemoval = TestRuleFactory.rule(
            id: "builtin.remove.utm_source",
            action: .removeParameter,
            name: "utm_source"
        )
        let builtIn = try TestRuleFactory.snapshot([
            disabledPreserve,
            unrelatedRemoval,
        ])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackerFreeEnablePreserve-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleStore(
            builtInSnapshot: builtIn,
            userRulesFileURL: directory.appendingPathComponent("rules.json")
        )
        try store.replaceUserRules([
            TestRuleFactory.rule(
                id: "user.remove.q",
                origin: .user,
                action: .removeParameter,
                name: "q"
            ),
        ])

        XCTAssertNoThrow(
            try store.setBuiltInRule(id: unrelatedRemoval.id, enabled: false)
        )
        XCTAssertEqual(
            store.builtInRules.first(where: { $0.id == unrelatedRemoval.id })?
                .enabled,
            false
        )
        XCTAssertThrowsError(
            try store.setBuiltInRule(id: disabledPreserve.id, enabled: true)
        ) {
            XCTAssertEqual(
                $0 as? RuleStoreError,
                .builtInPreserveOverrideRequiresConfirmation(["q"])
            )
        }
        XCTAssertEqual(store.builtInRules.first?.enabled, false)
    }

    @MainActor
    func testInvalidImportDoesNotReplaceLiveSnapshot() throws {
        let builtIn = try TestRuleFactory.snapshot([
            TestRuleFactory.rule(
                id: "builtin.remove.utm_source",
                action: .removeParameter,
                name: "utm_source"
            ),
        ])
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
            .appendingPathComponent("CustomRules.json")
        let store = RuleStore(
            builtInSnapshot: builtIn,
            userRulesFileURL: file
        )
        let original = store.snapshot

        XCTAssertThrowsError(try store.makeImportPreview(Data("{".utf8)))
        XCTAssertEqual(store.snapshot, original)
    }

    @MainActor
    func testDefaultDisabledRuleCanBeEnabledAndRevisionNeverSaturates() throws {
        let disabledRule = TestRuleFactory.rule(
            id: "builtin.remove.prefix",
            enabled: false,
            action: .removeParameter,
            matcher: .asciiPrefix,
            name: "utm_"
        )
        let builtIn = try TestRuleFactory.snapshot(
            [disabledRule],
            revision: .max
        )
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
            .appendingPathComponent("CustomRules.json")
        let store = RuleStore(
            builtInSnapshot: builtIn,
            userRulesFileURL: file
        )
        let initialRevision = store.snapshot.revision

        try store.setBuiltInRule(id: disabledRule.id, enabled: true)

        XCTAssertNotEqual(store.snapshot.revision, initialRevision)
        XCTAssertEqual(store.builtInRules.first?.enabled, true)
        XCTAssertEqual(store.enabledBuiltInRuleIDs, [disabledRule.id])

        let reloaded = RuleStore(
            builtInSnapshot: builtIn,
            userRulesFileURL: file,
            enabledBuiltInRuleIDs: store.enabledBuiltInRuleIDs
        )
        XCTAssertEqual(reloaded.builtInRules.first?.enabled, true)
    }

    @MainActor
    func testDisabledUserRemovalRequiresAcknowledgementBeforeOverridingPreserve()
        throws
    {
        let preserve = TestRuleFactory.rule(
            id: "builtin.preserve.q",
            action: .preserveParameter,
            name: "q"
        )
        let disabledRemoval = TestRuleFactory.rule(
            id: "user.remove.q",
            enabled: false,
            origin: .user,
            action: .removeParameter,
            name: "q"
        )
        let builtIn = try TestRuleFactory.snapshot([preserve])
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("CustomRules.json")
        let store = RuleStore(
            builtInSnapshot: builtIn,
            userRulesFileURL: file
        )
        try store.replaceUserRules([disabledRemoval])

        XCTAssertEqual(
            try store.builtInPreserveOverrides(
                ifEnablingUserRuleID: disabledRemoval.id
            ),
            ["q"]
        )
        XCTAssertThrowsError(
            try store.setUserRule(id: disabledRemoval.id, enabled: true)
        ) { error in
            XCTAssertEqual(
                error as? RuleStoreError,
                .builtInPreserveOverrideRequiresConfirmation(["q"])
            )
        }
        XCTAssertEqual(store.userRules.first?.enabled, false)

        try store.setUserRule(
            id: disabledRemoval.id,
            enabled: true,
            acknowledgingBuiltInPreserveOverride: true
        )
        XCTAssertEqual(store.userRules.first?.enabled, true)
    }

    @MainActor
    func testRuleImportBoundariesAreFailClosed() throws {
        let builtIn = try TestRuleFactory.snapshot([])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackerFreeImportBounds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleStore(
            builtInSnapshot: builtIn,
            userRulesFileURL: directory.appendingPathComponent("rules.json")
        )
        let encoder = JSONEncoder()

        func encoded(
            _ rules: [CleaningRule],
            reviewedDate: String = "2026-07-23"
        ) throws -> Data {
            try encoder.encode(RuleSetDocument(
                schemaVersion: 1,
                ruleSetRevision: 1,
                reviewedDate: reviewedDate,
                rules: rules
            ))
        }

        let minimalRule = TestRuleFactory.rule(
            id: "user.minimum",
            enabled: false,
            origin: .user,
            action: .removeParameter,
            name: "x"
        )
        var exactByteLimit = try encoded([minimalRule])
        exactByteLimit.append(
            Data(
                repeating: 0x20,
                count: RuleStore.maximumImportByteCount - exactByteLimit.count
            )
        )
        XCTAssertEqual(
            try store.makeImportPreview(exactByteLimit).ruleCount,
            1
        )
        var overByteLimit = exactByteLimit
        overByteLimit.append(0x20)
        XCTAssertThrowsError(try store.makeImportPreview(overByteLimit)) {
            XCTAssertEqual($0 as? RuleStoreError, .importTooLarge)
        }

        let maximumRules = (0..<RuleSetSnapshot.maximumUserRuleCount).map {
            TestRuleFactory.rule(
                id: "user.bound.\($0)",
                enabled: false,
                origin: .user,
                action: .removeParameter,
                name: "p\($0)"
            )
        }
        XCTAssertEqual(
            try store.makeImportPreview(encoded(maximumRules)).ruleCount,
            RuleSetSnapshot.maximumUserRuleCount
        )
        let tooManyRules = maximumRules + [
            TestRuleFactory.rule(
                id: "user.bound.overflow",
                enabled: false,
                origin: .user,
                action: .removeParameter,
                name: "overflow"
            ),
        ]
        XCTAssertThrowsError(
            try store.makeImportPreview(encoded(tooManyRules))
        ) {
            XCTAssertEqual(
                $0 as? RuleStoreError,
                .validation(.tooManyRules)
            )
        }

        let identifierAtLimit = String(repeating: "i", count: 128)
        let nameAtLimit = String(repeating: "n", count: 128)
        let hostsAtLimit = (0..<64).map { "h\($0).example.com" }
        let pathAtLimit = "/" + String(repeating: "p", count: 511)
        let validBoundaryRules = [
            TestRuleFactory.rule(
                id: identifierAtLimit,
                enabled: false,
                origin: .user,
                action: .removeParameter,
                name: nameAtLimit,
                explanation: String(repeating: "e", count: 1_024)
            ),
            TestRuleFactory.rule(
                id: "user.host-boundary",
                enabled: false,
                origin: .user,
                action: .removeParameter,
                name: "host-boundary",
                scope: .host,
                hosts: hostsAtLimit
            ),
            TestRuleFactory.rule(
                id: "user.path-boundary",
                enabled: false,
                origin: .user,
                action: .removeParameter,
                name: "path-boundary",
                scope: .hostPath,
                hosts: ["example.com"],
                pathConstraint: SafePathConstraint(
                    kind: .literalPrefix,
                    value: pathAtLimit
                )
            ),
        ]
        XCTAssertEqual(
            try store.makeImportPreview(encoded(validBoundaryRules)).ruleCount,
            validBoundaryRules.count
        )

        let invalidID = TestRuleFactory.rule(
            id: String(repeating: "i", count: 129),
            enabled: false,
            origin: .user,
            action: .removeParameter,
            name: "x"
        )
        XCTAssertThrowsError(
            try store.makeImportPreview(encoded([invalidID]))
        ) {
            XCTAssertEqual(
                $0 as? RuleStoreError,
                .validation(.invalidID(invalidID.id))
            )
        }

        let invalidName = TestRuleFactory.rule(
            id: "user.invalid-name",
            enabled: false,
            origin: .user,
            action: .removeParameter,
            name: String(repeating: "n", count: 129)
        )
        XCTAssertThrowsError(
            try store.makeImportPreview(encoded([invalidName]))
        ) {
            XCTAssertEqual(
                $0 as? RuleStoreError,
                .validation(.invalidName(invalidName.id))
            )
        }

        let tooManyHosts = TestRuleFactory.rule(
            id: "user.too-many-hosts",
            enabled: false,
            origin: .user,
            action: .removeParameter,
            name: "x",
            scope: .host,
            hosts: hostsAtLimit + ["overflow.example.com"]
        )
        XCTAssertThrowsError(
            try store.makeImportPreview(encoded([tooManyHosts]))
        ) {
            XCTAssertEqual(
                $0 as? RuleStoreError,
                .validation(.invalidScope(tooManyHosts.id))
            )
        }

        let oversizedPath = TestRuleFactory.rule(
            id: "user.oversized-path",
            enabled: false,
            origin: .user,
            action: .removeParameter,
            name: "x",
            scope: .hostPath,
            hosts: ["example.com"],
            pathConstraint: SafePathConstraint(
                kind: .literalPrefix,
                value: "/" + String(repeating: "p", count: 512)
            )
        )
        XCTAssertThrowsError(
            try store.makeImportPreview(encoded([oversizedPath]))
        ) {
            XCTAssertEqual(
                $0 as? RuleStoreError,
                .validation(.invalidPathConstraint(oversizedPath.id))
            )
        }

        XCTAssertNoThrow(
            try store.makeImportPreview(
                encoded([minimalRule], reviewedDate: "2024-02-29")
            )
        )
        XCTAssertThrowsError(
            try store.makeImportPreview(
                encoded([minimalRule], reviewedDate: "2026-02-29")
            )
        ) {
            XCTAssertEqual(
                $0 as? RuleStoreError,
                .validation(.invalidReviewedDate)
            )
        }
        XCTAssertThrowsError(
            try store.makeImportPreview(
                encoded([minimalRule], reviewedDate: "2026-02-31")
            )
        ) {
            XCTAssertEqual(
                $0 as? RuleStoreError,
                .validation(.invalidReviewedDate)
            )
        }
    }

    @MainActor
    func testImportedUserHardProtectionIsAdditiveToBuiltIns() throws {
        let builtInRemoval = TestRuleFactory.rule(
            id: "builtin.remove.x",
            action: .removeParameter,
            name: "x"
        )
        let builtIn = try TestRuleFactory.snapshot([builtInRemoval])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackerFreeHardGuard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleStore(
            builtInSnapshot: builtIn,
            userRulesFileURL: directory.appendingPathComponent("rules.json")
        )
        let userGuard = TestRuleFactory.rule(
            id: "user.protect.x",
            origin: .user,
            action: .hardProtectURL,
            name: "x"
        )
        let data = try JSONEncoder().encode(RuleSetDocument(
            schemaVersion: 1,
            ruleSetRevision: 1,
            reviewedDate: "2026-07-23",
            rules: [userGuard]
        ))

        try store.applyImport(store.makeImportPreview(data))

        XCTAssertEqual(store.snapshot.builtInRules, [builtInRemoval])
        XCTAssertEqual(store.snapshot.userRules, [userGuard])
        let result = URLCleaner.clean(
            "https://example.test/?x=1",
            using: store.snapshot
        )
        XCTAssertEqual(result.decision, .protected)
        XCTAssertEqual(result.reason, .hardProtectionRule)
    }

    @MainActor
    func testBootstrapFailureBlocksPersistedUserRemovalForEveryCaller() throws {
        let emptyBuiltIns = try TestRuleFactory.snapshot([])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackerFreeBootstrapFail-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleStore(
            builtInSnapshot: emptyBuiltIns,
            userRulesFileURL: directory.appendingPathComponent("rules.json")
        )
        try store.replaceUserRules([
            TestRuleFactory.rule(
                id: "user.remove.x",
                origin: .user,
                action: .removeParameter,
                name: "x"
            ),
        ])
        let transform = AppState.makeClipboardTransform(
            ruleStore: store,
            rulesBootstrapFailed: true
        )

        XCTAssertEqual(
            transform(
                ClipboardTransformInput(
                    content: PasteboardContent(
                        plainText: "https://example.test/?x=1"
                    )
                ),
                store.snapshot.revision
            ),
            .unchanged(.protectedOrUnsupported)
        )
    }
}
