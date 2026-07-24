import Foundation

public enum CleanDecision: String, Codable, Sendable, Equatable {
    case cleaned
    case unchanged
    case protected
    case unsupported
    case ruleConflict
}

public enum CleanResultReason: String, Codable, Sendable, Equatable {
    case removedKnownParameters
    case noQuery
    case noMatchingParameter
    case recognitionFailure
    case ambiguousQuery
    case protectedLink
    case hardProtectionRule
    case ruleConflict
    case postconditionFailure
}

public struct RemovedParameter: Sendable, Equatable, Hashable {
    public let name: String
    public let ruleID: String
    public let origin: RuleOrigin

    public init(name: String, ruleID: String, origin: RuleOrigin) {
        self.name = name
        self.ruleID = ruleID
        self.origin = origin
    }
}

public struct CleanResult: Sendable, Equatable {
    public let decision: CleanDecision
    public let reason: CleanResultReason
    public let output: String?
    public let removedParameters: [RemovedParameter]
    public let ruleSetRevision: UInt64

    public var didChange: Bool {
        decision == .cleaned && output != nil
    }

    public init(
        decision: CleanDecision,
        reason: CleanResultReason,
        output: String?,
        removedParameters: [RemovedParameter],
        ruleSetRevision: UInt64
    ) {
        self.decision = decision
        self.reason = reason
        self.output = output
        self.removedParameters = removedParameters
        self.ruleSetRevision = ruleSetRevision
    }
}

public struct URLCleaner: Sendable {
    public let ruleSet: RuleSetSnapshot

    public init(ruleSet: RuleSetSnapshot) {
        self.ruleSet = ruleSet
    }

    public func clean(_ input: String) -> CleanResult {
        Self.clean(input, using: ruleSet)
    }

    public static func clean(
        _ input: String,
        using ruleSet: RuleSetSnapshot
    ) -> CleanResult {
        let revision = ruleSet.revision
        let recognized: RecognizedURL
        switch URLRecognizer.recognize(input) {
        case let .success(value):
            recognized = value
        case .failure:
            return result(
                .unsupported,
                .recognitionFailure,
                revision: revision
            )
        }

        guard let rawQuery = recognized.rawQuery, !rawQuery.isEmpty else {
            return result(.unchanged, .noQuery, revision: revision)
        }

        let tokenized: TokenizedRawQuery
        switch RawQueryTokenizer.tokenize(rawQuery) {
        case let .success(value):
            tokenized = value
        case let .failure(error):
            let reason: CleanResultReason =
                error == .ambiguousSemicolon
                    ? .ambiguousQuery
                    : .recognitionFailure
            return result(.unsupported, reason, revision: revision)
        }

        switch ProtectedLinkClassifier.classify(recognized, query: tokenized) {
        case .allowed:
            break
        case .protected:
            return result(.protected, .protectedLink, revision: revision)
        }

        let engine = RuleEngine(snapshot: ruleSet)
        if engine.hardProtectionMatch(url: recognized, query: tokenized) != nil {
            return result(.protected, .hardProtectionRule, revision: revision)
        }

        var retainedRawFields: [String] = []
        retainedRawFields.reserveCapacity(tokenized.fields.count)
        var removed: [RemovedParameter] = []

        for field in tokenized.fields {
            switch engine.decision(for: field, in: recognized, query: tokenized) {
            case .preserve:
                retainedRawFields.append(field.raw)
            case let .remove(match):
                removed.append(
                    RemovedParameter(
                        name: match.displayName,
                        ruleID: match.ruleID,
                        origin: match.origin
                    )
                )
            case .conflict:
                return result(
                    .ruleConflict,
                    .ruleConflict,
                    revision: revision
                )
            }
        }

        guard !removed.isEmpty else {
            return result(.unchanged, .noMatchingParameter, revision: revision)
        }

        let retainedQuery = retainedRawFields.joined(separator: "&")
        let keepsQueryDelimiter = !retainedRawFields.isEmpty
        let outputCore = recognized.rawPrefixThroughPath
            + (keepsQueryDelimiter ? "?" + retainedQuery : "")
            + recognized.rawFragmentWithDelimiter
        let output = recognized.envelopePrefix
            + outputCore
            + recognized.envelopeSuffix

        guard output != input,
              postconditionsHold(
                original: recognized,
                output: output,
                retainedRawFields: retainedRawFields,
                keepsQueryDelimiter: keepsQueryDelimiter
              )
        else {
            return result(
                .unsupported,
                .postconditionFailure,
                revision: revision
            )
        }

        return CleanResult(
            decision: .cleaned,
            reason: .removedKnownParameters,
            output: output,
            removedParameters: removed,
            ruleSetRevision: revision
        )
    }

    private static func postconditionsHold(
        original: RecognizedURL,
        output: String,
        retainedRawFields: [String],
        keepsQueryDelimiter: Bool
    ) -> Bool {
        guard case let .success(cleaned) = URLRecognizer.recognize(output),
              cleaned.envelopePrefix == original.envelopePrefix,
              cleaned.envelopeSuffix == original.envelopeSuffix,
              cleaned.rawPrefixThroughPath == original.rawPrefixThroughPath,
              cleaned.rawAuthority == original.rawAuthority,
              cleaned.rawPath == original.rawPath,
              cleaned.rawFragmentWithDelimiter
                == original.rawFragmentWithDelimiter,
              cleaned.scheme == original.scheme,
              cleaned.canonicalHost == original.canonicalHost,
              cleaned.port == original.port
        else {
            return false
        }

        if keepsQueryDelimiter {
            guard let query = cleaned.rawQuery,
                  case let .success(tokenized) =
                    RawQueryTokenizer.tokenize(query),
                  tokenized.fields.map(\.raw) == retainedRawFields
            else {
                return false
            }
        } else if cleaned.rawQuery != nil {
            return false
        }

        return isOrderedSubsequence(
            retainedRawFields,
            of: original.rawQuery.map {
                $0.split(separator: "&", omittingEmptySubsequences: false)
                    .map(String.init)
            } ?? []
        )
    }

    private static func isOrderedSubsequence(
        _ candidate: [String],
        of source: [String]
    ) -> Bool {
        var candidateIndex = 0
        for value in source where candidateIndex < candidate.count {
            if value == candidate[candidateIndex] {
                candidateIndex += 1
            }
        }
        return candidateIndex == candidate.count
    }

    private static func result(
        _ decision: CleanDecision,
        _ reason: CleanResultReason,
        revision: UInt64
    ) -> CleanResult {
        CleanResult(
            decision: decision,
            reason: reason,
            output: nil,
            removedParameters: [],
            ruleSetRevision: revision
        )
    }
}
