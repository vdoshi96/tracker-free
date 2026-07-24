import Foundation

public enum RuleStoreError: Error, Sendable, Equatable {
    case importTooLarge
    case exportTooLarge
    case invalidDocument
    case validation(RuleValidationError)
    case builtInRuleNotFound
    case userRuleNotFound
    case hardProtectionCannotBeDisabled
    case builtInPreserveOverrideRequiresConfirmation([String])
    case persistenceFailed
}

public enum RuleStoreLoadIssue: String, Sendable, Equatable {
    case customRuleFileTooLarge
    case customRuleFileUnreadable
    case customRuleFileInvalid
    case customRuleOverridesNeedReview
}

public struct RuleImportPreview: Sendable, Equatable {
    public let document: RuleSetDocument
    public let ruleCount: Int
    public let enabledRemovalCount: Int
    public let enabledPreservationCount: Int
    public let enabledHardProtectionCount: Int
    public let builtInPreserveOverrides: [String]

    public init(
        document: RuleSetDocument,
        builtInPreserveOverrides: [String]
    ) {
        self.document = document
        ruleCount = document.rules.count
        enabledRemovalCount = document.rules.filter {
            $0.enabled && $0.action == .removeParameter
        }.count
        enabledPreservationCount = document.rules.filter {
            $0.enabled && $0.action == .preserveParameter
        }.count
        enabledHardProtectionCount = document.rules.filter {
            $0.enabled && $0.action == .hardProtectURL
        }.count
        self.builtInPreserveOverrides = builtInPreserveOverrides
    }
}

/// Main-actor ownership makes revision changes atomic from the coordinator's
/// perspective. Cleaning always receives an immutable `RuleSetSnapshot`.
@MainActor
public final class RuleStore {
    public static let maximumImportByteCount = 256 * 1024

    public private(set) var snapshot: RuleSetSnapshot
    public private(set) var disabledBuiltInRuleIDs: Set<String>
    public private(set) var enabledBuiltInRuleIDs: Set<String>
    public private(set) var loadIssue: RuleStoreLoadIssue?

    public var rules: [CleaningRule] {
        snapshot.rules
    }

    public var builtInRules: [CleaningRule] {
        snapshot.builtInRules
    }

    public var userRules: [CleaningRule] {
        snapshot.userRules
    }

    private let originalBuiltInSnapshot: RuleSetSnapshot
    private let userRulesFileURL: URL
    private var nextRevision: UInt64

    public init(
        builtInSnapshot: RuleSetSnapshot,
        userRulesFileURL: URL,
        disabledBuiltInRuleIDs: Set<String> = [],
        enabledBuiltInRuleIDs: Set<String> = []
    ) {
        originalBuiltInSnapshot = builtInSnapshot
        self.userRulesFileURL = userRulesFileURL
        self.disabledBuiltInRuleIDs = Set(
            disabledBuiltInRuleIDs.filter { id in
                builtInSnapshot.builtInRules.contains {
                    $0.id == id && $0.enabled && $0.action != .hardProtectURL
                }
            }
        )
        self.enabledBuiltInRuleIDs = Set(
            enabledBuiltInRuleIDs.filter { id in
                builtInSnapshot.builtInRules.contains {
                    $0.id == id && !$0.enabled
                }
            }
        )
        nextRevision = builtInSnapshot.revision

        let adjustedBuiltIns = Self.applyingEnablementOverrides(
            self.disabledBuiltInRuleIDs,
            enabledIDs: self.enabledBuiltInRuleIDs,
            to: builtInSnapshot.builtInRules
        )
        var loadedUserRules: [CleaningRule] = []
        var reviewedBuiltInRevision: UInt64?
        var issue: RuleStoreLoadIssue?

        if FileManager.default.fileExists(atPath: userRulesFileURL.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(
                    atPath: userRulesFileURL.path
                )
                let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                guard size <= Self.maximumImportByteCount else {
                    throw RuleStoreLoadIssue.customRuleFileTooLarge
                }
                let data = try Data(
                    contentsOf: userRulesFileURL,
                    options: [.mappedIfSafe]
                )
                guard data.count <= Self.maximumImportByteCount else {
                    throw RuleStoreLoadIssue.customRuleFileTooLarge
                }
                let document = try JSONDecoder().decode(
                    RuleSetDocument.self,
                    from: data
                )
                try RuleValidator.validateUserImport(document)
                loadedUserRules = document.rules
                reviewedBuiltInRevision =
                    document.reviewedBuiltInRuleSetRevision
                nextRevision = max(nextRevision, document.ruleSetRevision)
            } catch let caught as RuleStoreLoadIssue {
                issue = caught
            } catch is DecodingError {
                issue = .customRuleFileInvalid
            } catch is RuleValidationError {
                issue = .customRuleFileInvalid
            } catch {
                issue = .customRuleFileUnreadable
            }
        }

        let startupOverrideRuleIDs = Self.builtInPreserveOverrideRuleIDs(
            in: loadedUserRules,
            builtInRules: adjustedBuiltIns
        )
        if !startupOverrideRuleIDs.isEmpty,
           reviewedBuiltInRevision != builtInSnapshot.revision
        {
            loadedUserRules = loadedUserRules.map { rule in
                startupOverrideRuleIDs.contains(rule.id)
                    ? rule.withEnabled(false)
                    : rule
            }
            issue = .customRuleOverridesNeedReview
        }

        nextRevision = Self.incremented(nextRevision)
        do {
            snapshot = try RuleSetSnapshot(
                schemaVersion: builtInSnapshot.schemaVersion,
                revision: nextRevision,
                reviewedDate: builtInSnapshot.reviewedDate,
                rules: adjustedBuiltIns + loadedUserRules
            )
        } catch {
            // A persisted document can become incompatible with a newer
            // built-in bundle (for example, after an ID is added upstream).
            // Keep adjusted built-ins active, discard the incompatible user
            // set, and surface the load failure instead of dropping it silently.
            snapshot = (
                try? RuleSetSnapshot(
                    schemaVersion: builtInSnapshot.schemaVersion,
                    revision: nextRevision,
                    reviewedDate: builtInSnapshot.reviewedDate,
                    rules: adjustedBuiltIns
                )
            ) ?? builtInSnapshot
            issue = .customRuleFileInvalid
        }
        loadIssue = issue
    }

    public func makeImportPreview(_ data: Data) throws -> RuleImportPreview {
        guard data.count <= Self.maximumImportByteCount else {
            throw RuleStoreError.importTooLarge
        }
        let document: RuleSetDocument
        do {
            document = try JSONDecoder().decode(RuleSetDocument.self, from: data)
        } catch {
            throw RuleStoreError.invalidDocument
        }
        do {
            try RuleValidator.validateUserImport(document)
        } catch let error as RuleValidationError {
            throw RuleStoreError.validation(error)
        } catch {
            throw RuleStoreError.invalidDocument
        }

        return RuleImportPreview(
            document: document,
            builtInPreserveOverrides: builtInPreserveOverrides(
                in: document.rules
            )
        )
    }

    /// Applies a previously previewed import only after revalidation and a
    /// successful atomic disk write.
    public func applyImport(_ preview: RuleImportPreview) throws {
        try replaceUserRules(preview.document.rules)
    }

    public func replaceUserRules(_ rules: [CleaningRule]) throws {
        guard rules.count <= RuleSetSnapshot.maximumUserRuleCount else {
            throw RuleStoreError.validation(.tooManyRules)
        }

        let candidateRevision = Self.incremented(nextRevision)
        let document = RuleSetDocument(
            schemaVersion: snapshot.schemaVersion,
            ruleSetRevision: candidateRevision,
            reviewedDate: snapshot.reviewedDate,
            reviewedBuiltInRuleSetRevision:
                originalBuiltInSnapshot.revision,
            rules: rules
        )
        do {
            try RuleValidator.validateUserImport(document)
        } catch let error as RuleValidationError {
            throw RuleStoreError.validation(error)
        } catch {
            throw RuleStoreError.invalidDocument
        }

        let candidate: RuleSetSnapshot
        do {
            candidate = try RuleSetSnapshot(
                schemaVersion: snapshot.schemaVersion,
                revision: candidateRevision,
                reviewedDate: snapshot.reviewedDate,
                rules: snapshot.builtInRules + rules
            )
        } catch let error as RuleValidationError {
            throw RuleStoreError.validation(error)
        } catch {
            throw RuleStoreError.invalidDocument
        }

        try persist(document)
        nextRevision = candidateRevision
        snapshot = candidate
        loadIssue = nil
    }

    public func resetUserRules() throws {
        try replaceUserRules([])
    }

    public func builtInPreserveOverrides(
        ifEnablingUserRuleID id: String
    ) throws -> [String] {
        guard let rule = snapshot.userRules.first(where: { $0.id == id }) else {
            throw RuleStoreError.userRuleNotFound
        }
        guard rule.action == .removeParameter else {
            return []
        }
        return builtInPreserveOverrides(in: [rule.withEnabled(true)])
    }

    public func setUserRule(
        id: String,
        enabled: Bool,
        acknowledgingBuiltInPreserveOverride: Bool = false
    ) throws {
        guard let rule = snapshot.userRules.first(where: { $0.id == id }) else {
            throw RuleStoreError.userRuleNotFound
        }

        if enabled, !rule.enabled {
            let overrides = builtInPreserveOverrides(
                in: [rule.withEnabled(true)]
            )
            guard overrides.isEmpty
                    || acknowledgingBuiltInPreserveOverride
            else {
                throw RuleStoreError
                    .builtInPreserveOverrideRequiresConfirmation(overrides)
            }
        }

        try replaceUserRules(
            snapshot.userRules.map {
                $0.id == id ? $0.withEnabled(enabled) : $0
            }
        )
    }

    public func setBuiltInRule(
        id: String,
        enabled: Bool
    ) throws {
        guard let rule = originalBuiltInSnapshot.builtInRules.first(
            where: { $0.id == id }
        ) else {
            throw RuleStoreError.builtInRuleNotFound
        }
        if rule.action == .hardProtectURL, !enabled {
            throw RuleStoreError.hardProtectionCannotBeDisabled
        }

        var disabled = disabledBuiltInRuleIDs
        var enabledOverrides = enabledBuiltInRuleIDs
        if enabled {
            disabled.remove(id)
            if rule.enabled {
                enabledOverrides.remove(id)
            } else {
                enabledOverrides.insert(id)
            }
        } else {
            enabledOverrides.remove(id)
            if rule.enabled {
                disabled.insert(id)
            } else {
                disabled.remove(id)
            }
        }
        try recompileBuiltIns(
            disabledIDs: disabled,
            enabledIDs: enabledOverrides
        )
    }

    public func resetBuiltInEnablement() throws {
        try recompileBuiltIns(disabledIDs: [], enabledIDs: [])
    }

    public func exportUserRulesData() throws -> Data {
        let document = RuleSetDocument(
            schemaVersion: snapshot.schemaVersion,
            ruleSetRevision: snapshot.revision,
            reviewedDate: snapshot.reviewedDate,
            reviewedBuiltInRuleSetRevision:
                originalBuiltInSnapshot.revision,
            rules: snapshot.userRules
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw RuleStoreError.invalidDocument
        }
        guard data.count <= Self.maximumImportByteCount else {
            throw RuleStoreError.exportTooLarge
        }
        return data
    }

    private func recompileBuiltIns(
        disabledIDs: Set<String>,
        enabledIDs: Set<String>
    ) throws {
        let candidateRevision = Self.incremented(nextRevision)
        let candidateRules = Self.applyingEnablementOverrides(
            disabledIDs,
            enabledIDs: enabledIDs,
            to: originalBuiltInSnapshot.builtInRules
        )
        let currentlyEnabledPreserveIDs = Set(
            snapshot.builtInRules.lazy.filter {
                $0.enabled && $0.action == .preserveParameter
            }.map(\.id)
        )
        let newlyEnabledPreserves = candidateRules.filter {
            $0.enabled
                && $0.action == .preserveParameter
                && !currentlyEnabledPreserveIDs.contains($0.id)
        }
        let preserveOverrides = Self.builtInPreserveOverrides(
            in: snapshot.userRules,
            builtInRules: newlyEnabledPreserves
        )
        guard preserveOverrides.isEmpty else {
            throw RuleStoreError
                .builtInPreserveOverrideRequiresConfirmation(preserveOverrides)
        }
        let mergedCandidateRules = candidateRules + snapshot.userRules
        let candidate: RuleSetSnapshot
        do {
            candidate = try RuleSetSnapshot(
                schemaVersion: snapshot.schemaVersion,
                revision: candidateRevision,
                reviewedDate: snapshot.reviewedDate,
                rules: mergedCandidateRules
            )
        } catch let error as RuleValidationError {
            throw RuleStoreError.validation(error)
        } catch {
            throw RuleStoreError.invalidDocument
        }

        disabledBuiltInRuleIDs = disabledIDs
        enabledBuiltInRuleIDs = enabledIDs
        nextRevision = candidateRevision
        snapshot = candidate
    }

    private func persist(_ document: RuleSetDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw RuleStoreError.invalidDocument
        }
        guard data.count <= Self.maximumImportByteCount else {
            throw RuleStoreError.exportTooLarge
        }

        do {
            try FileManager.default.createDirectory(
                at: userRulesFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: userRulesFileURL, options: [.atomic])
        } catch {
            throw RuleStoreError.persistenceFailed
        }
    }

    private func builtInPreserveOverrides(
        in userRules: [CleaningRule]
    ) -> [String] {
        Self.builtInPreserveOverrides(
            in: userRules,
            builtInRules: originalBuiltInSnapshot.builtInRules
        )
    }

    private static func builtInPreserveOverrides(
        in userRules: [CleaningRule],
        builtInRules: [CleaningRule]
    ) -> [String] {
        let builtInPreserves = builtInRules.filter {
            $0.enabled && $0.action == .preserveParameter
        }
        var names = Set<String>()
        for userRule in userRules
        where userRule.enabled && userRule.action == .removeParameter {
            for preserve in builtInPreserves
            where matcherMayOverlap(userRule, preserve) {
                names.insert(preserve.name)
            }
        }
        return names.sorted()
    }

    private static func builtInPreserveOverrideRuleIDs(
        in userRules: [CleaningRule],
        builtInRules: [CleaningRule]
    ) -> Set<String> {
        let builtInPreserves = builtInRules.filter {
            $0.enabled && $0.action == .preserveParameter
        }
        return Set(userRules.compactMap { userRule in
            guard userRule.enabled,
                  userRule.action == .removeParameter,
                  builtInPreserves.contains(where: {
                      matcherMayOverlap(userRule, $0)
                  })
            else {
                return nil
            }
            return userRule.id
        })
    }

    private static func matcherMayOverlap(
        _ lhs: CleaningRule,
        _ rhs: CleaningRule
    ) -> Bool {
        let left = asciiLowercased(lhs.name)
        let right = asciiLowercased(rhs.name)
        switch (lhs.matcher, rhs.matcher) {
        case (.exactASCIIName, .exactASCIIName):
            return left == right
        case (.exactASCIIName, .asciiPrefix):
            return left.hasPrefix(right)
        case (.asciiPrefix, .exactASCIIName):
            return right.hasPrefix(left)
        case (.asciiPrefix, .asciiPrefix):
            return left.hasPrefix(right) || right.hasPrefix(left)
        }
    }

    private static func applyingEnablementOverrides(
        _ disabledIDs: Set<String>,
        enabledIDs: Set<String>,
        to rules: [CleaningRule]
    ) -> [CleaningRule] {
        rules.map { rule in
            if enabledIDs.contains(rule.id), !rule.enabled {
                return rule.withEnabled(true)
            }
            guard disabledIDs.contains(rule.id),
                  rule.enabled,
                  rule.action != .hardProtectURL
            else {
                return rule
            }
            return rule.withEnabled(false)
        }
    }

    private static func incremented(_ revision: UInt64) -> UInt64 {
        // RECOMMENDATION: wrapping preserves the only invariant the
        // coordinator needs—that every live rule mutation changes revision.
        revision == .max ? 1 : revision + 1
    }

    private static func asciiLowercased(_ value: String) -> String {
        String(decoding: value.utf8.map {
            ($0 >= 0x41 && $0 <= 0x5A) ? $0 + 0x20 : $0
        }, as: UTF8.self)
    }
}

extension RuleStoreLoadIssue: Error {}
