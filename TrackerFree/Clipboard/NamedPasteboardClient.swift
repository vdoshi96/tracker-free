import AppKit
import Foundation

/// An isolated AppKit pasteboard for integration tests and non-General workflows.
@MainActor
public final class NamedPasteboardClient: PasteboardClient {
    public let pasteboard: NSPasteboard
    private let backing: AppKitPasteboardClient

    public init(pasteboard: NSPasteboard = NSPasteboard.withUniqueName()) {
        self.pasteboard = pasteboard
        backing = AppKitPasteboardClient(pasteboard: pasteboard)
    }

    public var generation: PasteboardGeneration {
        backing.generation
    }

    public var permissionState: ClipboardPermissionState {
        .notRequired
    }

    public func itemCount() -> Int? {
        backing.itemCount()
    }

    public func typeIdentifiers(forItemAt index: Int) -> [String]? {
        backing.typeIdentifiers(forItemAt: index)
    }

    public func data(forTypeIdentifier typeIdentifier: String, itemAt index: Int) -> Data? {
        backing.data(forTypeIdentifier: typeIdentifier, itemAt: index)
    }

    public func prepareWrite(_ request: PasteboardWriteRequest) -> PasteboardPreparedWrite? {
        backing.prepareWrite(request)
    }

    @discardableResult
    public func prepareForNewContentsCurrentHostOnly() -> PasteboardGeneration {
        backing.prepareForNewContentsCurrentHostOnly()
    }

    public func writePrepared(_ preparedWrite: PasteboardPreparedWrite) -> Bool {
        backing.writePrepared(preparedWrite)
    }

    public func releaseGlobally() {
        pasteboard.releaseGlobally()
    }
}
