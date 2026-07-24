import OSLog

public enum ClipboardDiagnosticKind: String, Sendable {
    case started
    case stopped
    case snapshotRejected
    case generationChanged
    case ruleRevisionChanged
    case writeSucceeded
    case writeFailed
    case rollbackSucceeded
    case rollbackFailed
    case restoreSucceeded
    case conflictPaused
    case conflictResumed
    case lifecycleReset
}

/// Accepts result metadata only. Its API has no parameter capable of receiving clipboard content.
public struct PrivacySafeLogger {
    private let logger: Logger

    public init(
        subsystem: String = "com.vishal.TrackerFree",
        category: String = "Clipboard"
    ) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func record(
        _ kind: ClipboardDiagnosticKind,
        count: Int = 0,
        ruleRevision: ClipboardRuleRevision = 0
    ) {
        logger.debug(
            "event=\(kind.rawValue, privacy: .public) count=\(count, privacy: .public) revision=\(ruleRevision, privacy: .public)"
        )
    }
}
