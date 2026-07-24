import Foundation

public enum RuleOrigin: String, Codable, Sendable, CaseIterable {
    case builtIn
    case user
}

public enum RuleAction: String, Codable, Sendable, CaseIterable {
    case removeParameter
    case preserveParameter
    case hardProtectURL
}

public enum RuleMatcher: String, Codable, Sendable, CaseIterable {
    case exactASCIIName
    case asciiPrefix
}

public enum RuleCaseSensitivity: String, Codable, Sendable, CaseIterable {
    case caseSensitive
    case asciiCaseInsensitive
}

public enum RuleScope: String, Codable, Sendable, CaseIterable {
    case global
    case host
    case hostPath

    var specificity: Int {
        switch self {
        case .global: 1
        case .host: 2
        case .hostPath: 3
        }
    }
}

public enum RuleConfidence: String, Codable, Sendable, CaseIterable {
    case verified
    case inferred
    case experimental
}

public enum SafePathConstraintKind: String, Codable, Sendable, CaseIterable {
    case literalPrefix
    case xStatusPermalink
    case youtubeShareContent
    case instagramContent
}

public struct SafePathConstraint: Codable, Sendable, Equatable {
    public let kind: SafePathConstraintKind
    public let value: String?

    public init(kind: SafePathConstraintKind, value: String? = nil) {
        self.kind = kind
        self.value = value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case value
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(
            in: decoder,
            allowing: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(SafePathConstraintKind.self, forKey: .kind)
        value = try container.decodeIfPresent(String.self, forKey: .value)
    }
}

public struct CleaningRule: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let enabled: Bool
    public let origin: RuleOrigin
    public let action: RuleAction
    public let matcher: RuleMatcher
    public let name: String
    public let caseSensitivity: RuleCaseSensitivity
    public let scope: RuleScope
    public let hosts: [String]
    public let includeSubdomains: Bool
    public let pathConstraint: SafePathConstraint?
    public let confidence: RuleConfidence
    public let explanation: String
    public let provenanceURL: String

    public init(
        id: String,
        enabled: Bool,
        origin: RuleOrigin,
        action: RuleAction,
        matcher: RuleMatcher,
        name: String,
        caseSensitivity: RuleCaseSensitivity,
        scope: RuleScope,
        hosts: [String] = [],
        includeSubdomains: Bool = false,
        pathConstraint: SafePathConstraint? = nil,
        confidence: RuleConfidence,
        explanation: String,
        provenanceURL: String
    ) {
        self.id = id
        self.enabled = enabled
        self.origin = origin
        self.action = action
        self.matcher = matcher
        self.name = name
        self.caseSensitivity = caseSensitivity
        self.scope = scope
        self.hosts = hosts
        self.includeSubdomains = includeSubdomains
        self.pathConstraint = pathConstraint
        self.confidence = confidence
        self.explanation = explanation
        self.provenanceURL = provenanceURL
    }

    public func withEnabled(_ enabled: Bool) -> CleaningRule {
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
            confidence: confidence,
            explanation: explanation,
            provenanceURL: provenanceURL
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case enabled
        case origin
        case action
        case matcher
        case name
        case caseSensitivity
        case scope
        case hosts
        case includeSubdomains
        case pathConstraint
        case confidence
        case explanation
        case provenanceURL
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(
            in: decoder,
            allowing: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        origin = try container.decode(RuleOrigin.self, forKey: .origin)
        action = try container.decode(RuleAction.self, forKey: .action)
        matcher = try container.decode(RuleMatcher.self, forKey: .matcher)
        name = try container.decode(String.self, forKey: .name)
        caseSensitivity = try container.decode(
            RuleCaseSensitivity.self,
            forKey: .caseSensitivity
        )
        scope = try container.decode(RuleScope.self, forKey: .scope)
        hosts = try container.decode([String].self, forKey: .hosts)
        includeSubdomains = try container.decodeIfPresent(
            Bool.self,
            forKey: .includeSubdomains
        ) ?? false
        pathConstraint = try container.decodeIfPresent(
            SafePathConstraint.self,
            forKey: .pathConstraint
        )
        confidence = try container.decode(RuleConfidence.self, forKey: .confidence)
        explanation = try container.decode(String.self, forKey: .explanation)
        provenanceURL = try container.decode(String.self, forKey: .provenanceURL)
    }
}

public struct RuleSetDocument: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let ruleSetRevision: UInt64
    public let reviewedDate: String
    public let reviewedBuiltInRuleSetRevision: UInt64?
    public let rules: [CleaningRule]

    public init(
        schemaVersion: Int,
        ruleSetRevision: UInt64,
        reviewedDate: String,
        reviewedBuiltInRuleSetRevision: UInt64? = nil,
        rules: [CleaningRule]
    ) {
        self.schemaVersion = schemaVersion
        self.ruleSetRevision = ruleSetRevision
        self.reviewedDate = reviewedDate
        self.reviewedBuiltInRuleSetRevision =
            reviewedBuiltInRuleSetRevision
        self.rules = rules
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case ruleSetRevision
        case reviewedDate
        case reviewedBuiltInRuleSetRevision
        case rules
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(
            in: decoder,
            allowing: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        ruleSetRevision = try container.decode(
            UInt64.self,
            forKey: .ruleSetRevision
        )
        reviewedDate = try container.decode(String.self, forKey: .reviewedDate)
        reviewedBuiltInRuleSetRevision = try container.decodeIfPresent(
            UInt64.self,
            forKey: .reviewedBuiltInRuleSetRevision
        )
        rules = try container.decode([CleaningRule].self, forKey: .rules)
    }
}

public enum RuleValidationError: Error, Sendable, Equatable {
    case unsupportedSchemaVersion
    case invalidRevision
    case invalidReviewedDate
    case tooManyRules
    case duplicateID(String)
    case invalidID(String)
    case invalidName(String)
    case invalidHost(String)
    case invalidScope(String)
    case invalidPathConstraint(String)
    case invalidExplanation(String)
    case invalidProvenanceURL(String)
    case contradictoryUserRules(String, String)
    case nonUserRuleInImport(String)
    case nonBuiltInRuleInBundle(String)
}

public struct RuleSetSnapshot: Sendable, Equatable {
    public static let supportedSchemaVersion = 1
    public static let maximumUserRuleCount = 512

    public let schemaVersion: Int
    public let revision: UInt64
    public let reviewedDate: String
    public let rules: [CleaningRule]

    public var builtInRules: [CleaningRule] {
        rules.filter { $0.origin == .builtIn }
    }

    public var userRules: [CleaningRule] {
        rules.filter { $0.origin == .user }
    }

    public init(document: RuleSetDocument) throws {
        try RuleValidator.validateDocument(document)
        schemaVersion = document.schemaVersion
        revision = document.ruleSetRevision
        reviewedDate = document.reviewedDate
        rules = document.rules
    }

    public init(
        schemaVersion: Int = supportedSchemaVersion,
        revision: UInt64,
        reviewedDate: String,
        rules: [CleaningRule]
    ) throws {
        try self.init(
            document: RuleSetDocument(
                schemaVersion: schemaVersion,
                ruleSetRevision: revision,
                reviewedDate: reviewedDate,
                rules: rules
            )
        )
    }

    public func merging(
        userRules: [CleaningRule],
        revision newRevision: UInt64
    ) throws -> RuleSetSnapshot {
        guard userRules.allSatisfy({ $0.origin == .user }) else {
            let offending = userRules.first { $0.origin != .user }?.id ?? "unknown"
            throw RuleValidationError.nonUserRuleInImport(offending)
        }
        return try RuleSetSnapshot(
            schemaVersion: schemaVersion,
            revision: newRevision,
            reviewedDate: reviewedDate,
            rules: builtInRules + userRules
        )
    }
}

enum RuleValidator {
    static func validateDocument(_ document: RuleSetDocument) throws {
        guard document.schemaVersion == RuleSetSnapshot.supportedSchemaVersion else {
            throw RuleValidationError.unsupportedSchemaVersion
        }
        guard document.ruleSetRevision > 0 else {
            throw RuleValidationError.invalidRevision
        }
        guard isValidDate(document.reviewedDate) else {
            throw RuleValidationError.invalidReviewedDate
        }
        guard document.rules.count <= 2_048,
              document.rules.filter({ $0.origin == .user }).count
                <= RuleSetSnapshot.maximumUserRuleCount
        else {
            throw RuleValidationError.tooManyRules
        }

        var ids = Set<String>()
        for rule in document.rules {
            guard isSafeIdentifier(rule.id) else {
                throw RuleValidationError.invalidID(rule.id)
            }
            guard ids.insert(rule.id).inserted else {
                throw RuleValidationError.duplicateID(rule.id)
            }
            guard isValidParameterName(rule.name) else {
                throw RuleValidationError.invalidName(rule.id)
            }
            guard rule.explanation.utf8.count <= 1_024,
                  !rule.explanation.contains(where: \.isNewline)
            else {
                throw RuleValidationError.invalidExplanation(rule.id)
            }
            guard isValidProvenance(rule.provenanceURL) else {
                throw RuleValidationError.invalidProvenanceURL(rule.id)
            }
            try validateScope(rule)
        }

        try validateUserContradictions(
            document.rules.filter { $0.origin == .user && $0.enabled }
        )
    }

    static func validateUserImport(_ document: RuleSetDocument) throws {
        guard document.rules.allSatisfy({ $0.origin == .user }) else {
            let offending = document.rules.first { $0.origin != .user }?.id ?? "unknown"
            throw RuleValidationError.nonUserRuleInImport(offending)
        }
        try validateDocument(document)
    }

    private static func validateScope(_ rule: CleaningRule) throws {
        switch rule.scope {
        case .global:
            guard rule.hosts.isEmpty,
                  !rule.includeSubdomains,
                  rule.pathConstraint == nil
            else {
                throw RuleValidationError.invalidScope(rule.id)
            }
        case .host:
            guard !rule.hosts.isEmpty,
                  rule.hosts.count <= 64,
                  rule.pathConstraint == nil
            else {
                throw RuleValidationError.invalidScope(rule.id)
            }
        case .hostPath:
            guard !rule.hosts.isEmpty,
                  rule.hosts.count <= 64,
                  let pathConstraint = rule.pathConstraint
            else {
                throw RuleValidationError.invalidScope(rule.id)
            }
            try validatePathConstraint(pathConstraint, ruleID: rule.id)
        }

        var uniqueHosts = Set<String>()
        for host in rule.hosts {
            guard URLRecognizer.isValidCanonicalRuleHost(host),
                  !URLRecognizer.isLocalOrIPHost(host),
                  uniqueHosts.insert(host).inserted
            else {
                throw RuleValidationError.invalidHost(rule.id)
            }
        }
    }

    private static func validatePathConstraint(
        _ constraint: SafePathConstraint,
        ruleID: String
    ) throws {
        switch constraint.kind {
        case .literalPrefix:
            guard let value = constraint.value,
                  value.utf8.count <= 512,
                  value.hasPrefix("/"),
                  value.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }),
                  !value.contains("?"),
                  !value.contains("#"),
                  !value.contains("\\"),
                  !value.contains("%")
            else {
                throw RuleValidationError.invalidPathConstraint(ruleID)
            }
        case .xStatusPermalink, .youtubeShareContent, .instagramContent:
            guard constraint.value == nil else {
                throw RuleValidationError.invalidPathConstraint(ruleID)
            }
        }
    }

    private static func validateUserContradictions(
        _ rules: [CleaningRule]
    ) throws {
        guard rules.count > 1 else {
            return
        }
        for firstIndex in rules.indices {
            for secondIndex in rules.index(after: firstIndex)..<rules.endIndex {
                let first = rules[firstIndex]
                let second = rules[secondIndex]
                let ordinaryActions: Set<RuleAction> = [
                    .removeParameter, .preserveParameter,
                ]
                guard ordinaryActions.contains(first.action),
                      ordinaryActions.contains(second.action),
                      first.action != second.action,
                      matcherDomainsOverlap(first, second),
                      scopesOverlap(first, second)
                else {
                    continue
                }
                throw RuleValidationError.contradictoryUserRules(
                    first.id,
                    second.id
                )
            }
        }
    }

    private static func matcherDomainsOverlap(
        _ first: CleaningRule,
        _ second: CleaningRule
    ) -> Bool {
        let lhs = foldedMatcherText(first)
        let rhs = foldedMatcherText(second)
        switch (first.matcher, second.matcher) {
        case (.exactASCIIName, .exactASCIIName):
            return lhs == rhs
        case (.exactASCIIName, .asciiPrefix):
            return lhs.hasPrefix(rhs)
        case (.asciiPrefix, .exactASCIIName):
            return rhs.hasPrefix(lhs)
        case (.asciiPrefix, .asciiPrefix):
            return lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
        }
    }

    private static func scopesOverlap(
        _ first: CleaningRule,
        _ second: CleaningRule
    ) -> Bool {
        if first.scope == .global || second.scope == .global {
            return true
        }
        guard hostsOverlap(first, second) else {
            return false
        }
        if first.scope != .hostPath || second.scope != .hostPath {
            return true
        }
        guard let lhs = first.pathConstraint,
              let rhs = second.pathConstraint
        else {
            return true
        }
        if lhs.kind != .literalPrefix || rhs.kind != .literalPrefix {
            // Typed predicates are deliberately treated as potentially
            // overlapping during import validation. Rejecting a harmless pair
            // is safer than admitting an unresolved preservation/removal pair.
            return true
        }
        guard let lhsValue = lhs.value, let rhsValue = rhs.value else {
            return true
        }
        return pathPrefixesOverlap(lhsValue, rhsValue)
    }

    private static func hostsOverlap(
        _ first: CleaningRule,
        _ second: CleaningRule
    ) -> Bool {
        first.hosts.contains { lhs in
            second.hosts.contains { rhs in
                lhs == rhs
                    || (first.includeSubdomains && isSubdomain(rhs, of: lhs))
                    || (second.includeSubdomains && isSubdomain(lhs, of: rhs))
            }
        }
    }

    private static func isSubdomain(_ host: String, of base: String) -> Bool {
        host.hasSuffix("." + base)
    }

    private static func pathPrefixesOverlap(_ lhs: String, _ rhs: String) -> Bool {
        isSegmentPrefix(lhs, of: rhs) || isSegmentPrefix(rhs, of: lhs)
    }

    private static func isSegmentPrefix(_ prefix: String, of path: String) -> Bool {
        guard path.hasPrefix(prefix) else {
            return false
        }
        if path.count == prefix.count || prefix.hasSuffix("/") {
            return true
        }
        let boundary = path.index(path.startIndex, offsetBy: prefix.count)
        return path[boundary] == "/"
    }

    private static func foldedMatcherText(_ rule: CleaningRule) -> String {
        // Contradiction checks intentionally fold if either side can be
        // insensitive; false-positive rejection is safer than importing an
        // ambiguous rule file.
        asciiLowercased(rule.name)
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else {
            return false
        }
        return value.utf8.allSatisfy {
            ($0 >= 0x41 && $0 <= 0x5A)
                || ($0 >= 0x61 && $0 <= 0x7A)
                || ($0 >= 0x30 && $0 <= 0x39)
                || $0 == 0x2D
                || $0 == 0x5F
                || $0 == 0x2E
        }
    }

    private static func isValidParameterName(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else {
            return false
        }
        return value.utf8.allSatisfy {
            $0 >= 0x21 && $0 <= 0x7E
                && $0 != 0x26
                && $0 != 0x3D
                && $0 != 0x23
                && $0 != 0x3B
        }
    }

    private static func isValidProvenance(_ value: String) -> Bool {
        guard value.utf8.count <= 2_048,
              !value.contains(where: \.isNewline)
        else {
            return false
        }
        guard !value.isEmpty else {
            return true
        }
        guard let components = URLComponents(string: value),
              components.string == value,
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil
        else {
            return false
        }
        return true
    }

    private static func isValidDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10,
              bytes[4] == 0x2D,
              bytes[7] == 0x2D
        else {
            return false
        }
        let digitIndices = [0, 1, 2, 3, 5, 6, 8, 9]
        guard digitIndices.allSatisfy({
            bytes[$0] >= 0x30 && bytes[$0] <= 0x39
        }) else {
            return false
        }
        let year = Int(String(decoding: bytes[0...3], as: UTF8.self)) ?? 0
        let month = Int(String(decoding: bytes[5...6], as: UTF8.self)) ?? 0
        let day = Int(String(decoding: bytes[8...9], as: UTF8.self)) ?? 0
        guard (1...9_999).contains(year),
              (1...12).contains(month)
        else {
            return false
        }

        let daysInMonth: Int
        switch month {
        case 2:
            let isLeapYear =
                year.isMultiple(of: 400)
                    || (
                        year.isMultiple(of: 4)
                            && !year.isMultiple(of: 100)
                    )
            daysInMonth = isLeapYear ? 29 : 28
        case 4, 6, 9, 11:
            daysInMonth = 30
        default:
            daysInMonth = 31
        }
        return (1...daysInMonth).contains(day)
    }

    private static func asciiLowercased(_ value: String) -> String {
        String(decoding: value.utf8.map {
            ($0 >= 0x41 && $0 <= 0x5A) ? $0 + 0x20 : $0
        }, as: UTF8.self)
    }
}

public enum BuiltInRuleLoader {
    public static func load(data: Data) throws -> RuleSetSnapshot {
        let document = try JSONDecoder().decode(RuleSetDocument.self, from: data)
        guard document.rules.allSatisfy({ $0.origin == .builtIn }) else {
            let offending = document.rules.first {
                $0.origin != .builtIn
            }?.id ?? "unknown"
            throw RuleValidationError.nonBuiltInRuleInBundle(offending)
        }
        return try RuleSetSnapshot(document: document)
    }

    public static func load(from bundle: Bundle = .main) throws -> RuleSetSnapshot {
        guard let url = bundle.url(
            forResource: "BuiltInRules",
            withExtension: "json"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try load(data: Data(contentsOf: url))
    }
}

private struct StrictCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private func rejectUnknownKeys(
    in decoder: Decoder,
    allowing allowedKeys: Set<String>
) throws {
    let container = try decoder.container(keyedBy: StrictCodingKey.self)
    let unknown = container.allKeys.map(\.stringValue).filter {
        !allowedKeys.contains($0)
    }
    guard unknown.isEmpty else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown rule-data field."
            )
        )
    }
}
