import Foundation

public struct RuleMatch: Sendable, Equatable {
    public let ruleID: String
    public let displayName: String
    public let action: RuleAction
    public let origin: RuleOrigin

    public init(rule: CleaningRule) {
        ruleID = rule.id
        displayName = rule.name
        action = rule.action
        origin = rule.origin
    }
}

public enum ParameterRuleDecision: Sendable, Equatable {
    case preserve(RuleMatch?)
    case remove(RuleMatch)
    case conflict
}

/// A synchronous immutable evaluator. A caller captures one instance (and thus
/// one revision) for an entire clean attempt.
public struct RuleEngine: Sendable {
    public let snapshot: RuleSetSnapshot

    public init(snapshot: RuleSetSnapshot) {
        self.snapshot = snapshot
    }

    public func hardProtectionMatch(
        url: RecognizedURL,
        query: TokenizedRawQuery
    ) -> RuleMatch? {
        let fieldCandidates = query.fields.map(RuleFieldCandidate.init)
        let matches = snapshot.rules.filter { rule in
            rule.enabled
                && rule.action == .hardProtectURL
                && scopeMatches(rule, url: url, query: query)
                && fieldCandidates.contains { nameMatches(rule, candidate: $0) }
        }
        return preferredRule(from: matches).map(RuleMatch.init)
    }

    public func decision(
        for field: RawQueryField,
        in url: RecognizedURL,
        query: TokenizedRawQuery
    ) -> ParameterRuleDecision {
        let candidate = RuleFieldCandidate(field: field)
        let matches = snapshot.rules.filter { rule in
            rule.enabled
                && rule.action != .hardProtectURL
                && nameMatches(rule, candidate: candidate)
                && scopeMatches(rule, url: url, query: query)
        }

        let userPreserves = matches.filter {
            $0.origin == .user && $0.action == .preserveParameter
        }
        if let rule = preferredRule(from: userPreserves) {
            return .preserve(RuleMatch(rule: rule))
        }

        let userRemovals = matches.filter {
            $0.origin == .user && $0.action == .removeParameter
        }
        if let rule = preferredRule(from: userRemovals) {
            return .remove(RuleMatch(rule: rule))
        }

        let builtIns = matches.filter { $0.origin == .builtIn }
        guard let maximumSpecificity = builtIns.map(\.scope.specificity).max() else {
            return .preserve(nil)
        }
        let mostSpecific = builtIns.filter {
            $0.scope.specificity == maximumSpecificity
        }

        // RECOMMENDATION: at equal built-in scope, preservation is the
        // deterministic safety tie-breaker.
        let preserves = mostSpecific.filter { $0.action == .preserveParameter }
        if let rule = preferredRule(from: preserves) {
            return .preserve(RuleMatch(rule: rule))
        }
        let removals = mostSpecific.filter { $0.action == .removeParameter }
        if let rule = preferredRule(from: removals) {
            return .remove(RuleMatch(rule: rule))
        }
        return .conflict
    }

    private func preferredRule(from rules: [CleaningRule]) -> CleaningRule? {
        rules.sorted { lhs, rhs in
            if lhs.matcher != rhs.matcher {
                return lhs.matcher == .exactASCIIName
            }
            if lhs.scope.specificity != rhs.scope.specificity {
                return lhs.scope.specificity > rhs.scope.specificity
            }
            return lhs.id < rhs.id
        }.first
    }

    private func nameMatches(
        _ rule: CleaningRule,
        candidate: RuleFieldCandidate
    ) -> Bool {
        let candidateName: String
        let expected: String
        switch rule.caseSensitivity {
        case .caseSensitive:
            candidateName = candidate.original
            expected = rule.name
        case .asciiCaseInsensitive:
            candidateName = candidate.folded
            expected = asciiLowercased(rule.name)
        }

        switch rule.matcher {
        case .exactASCIIName:
            return candidateName == expected
        case .asciiPrefix:
            return candidateName.hasPrefix(expected)
        }
    }

    private func scopeMatches(
        _ rule: CleaningRule,
        url: RecognizedURL,
        query: TokenizedRawQuery
    ) -> Bool {
        switch rule.scope {
        case .global:
            return true
        case .host:
            return hostMatches(rule, host: url.canonicalHost)
        case .hostPath:
            guard hostMatches(rule, host: url.canonicalHost),
                  let constraint = rule.pathConstraint
            else {
                return false
            }
            if url.rawPath.contains("%") {
                // Percent-encoded paths are never used to prove a removal
                // scope. For an additive hard guard, ambiguity protects the
                // whole URL instead of allowing an encoded-path bypass.
                return rule.action == .hardProtectURL
            }
            return pathMatches(
                constraint,
                url: url,
                query: query
            )
        }
    }

    private func hostMatches(_ rule: CleaningRule, host: String) -> Bool {
        rule.hosts.contains { base in
            host == base
                || (
                    rule.includeSubdomains
                        && host.hasSuffix("." + base)
                )
        }
    }

    private func pathMatches(
        _ constraint: SafePathConstraint,
        url: RecognizedURL,
        query: TokenizedRawQuery
    ) -> Bool {
        switch constraint.kind {
        case .literalPrefix:
            guard let prefix = constraint.value,
                  url.rawPath.hasPrefix(prefix)
            else {
                return false
            }
            if url.rawPath.count == prefix.count || prefix.hasSuffix("/") {
                return true
            }
            let boundary = url.rawPath.index(
                url.rawPath.startIndex,
                offsetBy: prefix.count
            )
            return url.rawPath[boundary] == "/"
        case .xStatusPermalink:
            return isXStatusPermalink(url.rawPath)
        case .youtubeShareContent:
            return isYouTubeShareContent(url: url, query: query)
        case .instagramContent:
            return isInstagramContent(url.rawPath)
        }
    }

    private func isXStatusPermalink(_ path: String) -> Bool {
        let segments = normalizedPathSegments(path)
        let statusIndex: Int
        if segments.count >= 3,
           segments[1] == "status",
           isValidXHandle(segments[0]) {
            statusIndex = 1
        } else if segments.count >= 4,
                  segments[0] == "i",
                  segments[1] == "web",
                  segments[2] == "status" {
            statusIndex = 2
        } else {
            return false
        }

        let idIndex = statusIndex + 1
        guard idIndex < segments.count, isASCIIDigits(segments[idIndex]) else {
            return false
        }
        if segments.count == idIndex + 1 {
            return true
        }
        guard segments.count == idIndex + 3,
              segments[idIndex + 1] == "photo"
                || segments[idIndex + 1] == "video",
              isASCIIDigits(segments[idIndex + 2])
        else {
            return false
        }
        return true
    }

    private func isYouTubeShareContent(
        url: RecognizedURL,
        query: TokenizedRawQuery
    ) -> Bool {
        let segments = normalizedPathSegments(url.rawPath)
        if url.canonicalHost == "youtu.be" {
            return segments.count == 1 && isYouTubeID(segments[0])
        }

        let youtubeHosts: Set<String> = [
            "youtube.com",
            "www.youtube.com",
            "m.youtube.com",
            "music.youtube.com",
        ]
        guard youtubeHosts.contains(url.canonicalHost) else {
            return false
        }
        if segments == ["watch"] {
            return query.fields.contains {
                $0.decodedASCIIName == "v"
                    && $0.rawValue.map(isYouTubeID) == true
            }
        }
        return segments.count == 2
            && segments[0] == "shorts"
            && isYouTubeID(segments[1])
    }

    private func isInstagramContent(_ path: String) -> Bool {
        let segments = normalizedPathSegments(path)
        guard segments.count == 2,
              ["p", "reel", "tv"].contains(segments[0])
        else {
            return false
        }
        return !segments[1].isEmpty && segments[1].utf8.allSatisfy {
            isASCIIAlphaNumeric($0) || $0 == 0x2D || $0 == 0x5F
        }
    }

    private func normalizedPathSegments(_ path: String) -> [String] {
        guard !path.contains("%"), !path.contains("\\") else {
            return []
        }
        var segments = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        if segments.first == "" {
            segments.removeFirst()
        }
        if segments.last == "" {
            segments.removeLast()
        }
        guard !segments.contains("") else {
            return []
        }
        return segments
    }

    private func isValidXHandle(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 15
            && value.utf8.allSatisfy {
                isASCIIAlphaNumeric($0) || $0 == 0x5F
            }
    }

    private func isASCIIDigits(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            $0 >= 0x30 && $0 <= 0x39
        }
    }

    private func isYouTubeID(_ value: String) -> Bool {
        // VERIFIED: the required regression corpus uses short synthetic IDs.
        // RECOMMENDATION: accept a bounded nonempty identifier alphabet here;
        // no network lookup or claim about video existence is made.
        (1...64).contains(value.utf8.count) && value.utf8.allSatisfy {
            isASCIIAlphaNumeric($0) || $0 == 0x2D || $0 == 0x5F
        }
    }

    private func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A)
            || (byte >= 0x61 && byte <= 0x7A)
            || (byte >= 0x30 && byte <= 0x39)
    }

    private func asciiLowercased(_ value: String) -> String {
        String(decoding: value.utf8.map {
            ($0 >= 0x41 && $0 <= 0x5A) ? $0 + 0x20 : $0
        }, as: UTF8.self)
    }
}

private struct RuleFieldCandidate {
    let original: String
    let folded: String

    init(field: RawQueryField) {
        original = field.decodedASCIIName
        folded = String(decoding: field.decodedASCIIName.utf8.map { byte in
            if byte >= 0x41 && byte <= 0x5A {
                return byte + 0x20
            }
            return byte
        }, as: UTF8.self)
    }
}
