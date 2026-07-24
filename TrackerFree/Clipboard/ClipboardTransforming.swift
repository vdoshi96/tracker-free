import Foundation

public typealias ClipboardRuleRevision = UInt64

public struct ClipboardTransformInput: Equatable, Sendable {
    public let content: PasteboardContent

    public init(content: PasteboardContent) {
        self.content = content
    }
}

public enum ClipboardTransformNoChangeReason: Equatable, Sendable {
    case noKnownTrackingParameters
    case protectedOrUnsupported
    case ruleConflict
    case invalidInput
}

public struct ClipboardTransformOutput: Equatable, Sendable {
    public let content: PasteboardContent
    /// Safe display names only; never parameter values or a URL.
    public let removedParameterNames: [String]

    public init(content: PasteboardContent, removedParameterNames: [String]) {
        self.content = content
        self.removedParameterNames = removedParameterNames
    }
}

public enum ClipboardTransformDecision: Equatable, Sendable {
    case unchanged(ClipboardTransformNoChangeReason)
    case changed(ClipboardTransformOutput)
}

public typealias ClipboardTransformClosure =
    @MainActor (ClipboardTransformInput, ClipboardRuleRevision) -> ClipboardTransformDecision

public typealias ClipboardRuleRevisionProvider = @MainActor () -> ClipboardRuleRevision

/// Production adapter from pasteboard representation shape to the pure URL engine.
///
/// Plain text may retain the v1 edge envelope. A `public.url` representation
/// must be the URL bytes alone; accepting whitespace there would create an
/// invalid URL representation on writeback.
enum ClipboardContentTransformer {
    static func transform(
        _ input: ClipboardTransformInput,
        using snapshot: RuleSetSnapshot
    ) -> ClipboardTransformDecision {
        let plainResult = input.content.plainText.map {
            URLCleaner.clean($0, using: snapshot)
        }
        let urlResult: CleanResult?
        if let urlValue = input.content.url {
            guard case let .success(recognizedURL) =
                    URLRecognizer.recognize(urlValue),
                  recognizedURL.envelopePrefix.isEmpty,
                  recognizedURL.envelopeSuffix.isEmpty
            else {
                return .unchanged(.protectedOrUnsupported)
            }
            urlResult = URLCleaner.clean(urlValue, using: snapshot)
        } else {
            urlResult = nil
        }

        let results = [plainResult, urlResult].compactMap { $0 }
        guard !results.isEmpty else {
            return .unchanged(.invalidInput)
        }

        if results.allSatisfy({ $0.decision == .cleaned }) {
            let plainOutput: String?
            if let plainResult {
                guard let output = plainResult.output else {
                    return .unchanged(.invalidInput)
                }
                plainOutput = output
            } else {
                plainOutput = nil
            }

            let urlOutput: String?
            if let urlResult {
                guard let output = urlResult.output else {
                    return .unchanged(.invalidInput)
                }
                urlOutput = output
            } else {
                urlOutput = nil
            }

            if let plainOutput, let urlOutput {
                guard PlainTextEnvelope.core(from: plainOutput) == urlOutput,
                      plainResult?.removedParameters
                        == urlResult?.removedParameters
                else {
                    return .unchanged(.protectedOrUnsupported)
                }
            }

            let canonical = results[0]
            return .changed(
                ClipboardTransformOutput(
                    content: PasteboardContent(
                        plainText: plainOutput,
                        url: urlOutput
                    ),
                    removedParameterNames:
                        canonical.removedParameters.map(\.name)
                )
            )
        }

        if results.contains(where: { $0.decision == .ruleConflict }) {
            return .unchanged(.ruleConflict)
        }
        if results.contains(where: {
            $0.decision == .protected || $0.decision == .unsupported
        }) {
            return .unchanged(.protectedOrUnsupported)
        }
        if results.allSatisfy({ $0.decision == .unchanged }) {
            return .unchanged(.noKnownTrackingParameters)
        }
        return .unchanged(.protectedOrUnsupported)
    }
}
