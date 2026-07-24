import Foundation

public struct FakePasteboardItem: Equatable, Sendable {
    public var representations: [String: Data]

    public init(representations: [String: Data]) {
        self.representations = representations
    }

    public init(content: PasteboardContent, includesTrackerFreeMarker: Bool = false) {
        var representations: [String: Data] = [:]
        if let plainText = content.plainText {
            representations[PasteboardTypeIdentifier.plainText] = Data(plainText.utf8)
        }
        if let url = content.url {
            representations[PasteboardTypeIdentifier.url] = Data(url.utf8)
        }
        if includesTrackerFreeMarker {
            representations[PasteboardTypeIdentifier.trackerFreeMarker] = Data()
        }
        self.representations = representations
    }
}

/// Deterministic in-memory client for state-machine and failure-injection tests.
@MainActor
public final class FakePasteboardClient: PasteboardClient {
    public var permissionState: ClipboardPermissionState
    public private(set) var generation: PasteboardGeneration
    public private(set) var items: [FakePasteboardItem]
    public private(set) var currentHostOnlyPrepareCount = 0
    public private(set) var preparedWriteCount = 0
    public private(set) var committedWriteCount = 0
    public private(set) var itemInventoryReadCount = 0
    public private(set) var typeInventoryReadCount = 0
    public private(set) var representationReadCount = 0

    public var failNextPrepareWrite = false
    public var failNextCommit = false
    public var failNextDataRead = false
    public var corruptNextCommittedWrite = false
    public var changeGenerationAfterNextDataRead = false
    public var delayNextDataRead: TimeInterval = 0
    public var permissionStateAfterNextDataRead: ClipboardPermissionState?
    public var externalItemsAfterNextPrepare: [FakePasteboardItem]?
    public var externalItemsAfterNextCommit: [FakePasteboardItem]?

    public init(
        generation: Int = 0,
        items: [FakePasteboardItem] = [],
        permissionState: ClipboardPermissionState = .notRequired
    ) {
        self.permissionState = permissionState
        self.generation = PasteboardGeneration(rawValue: generation)
        self.items = items
    }

    public func itemCount() -> Int? {
        itemInventoryReadCount += 1
        return items.count
    }

    public func typeIdentifiers(forItemAt index: Int) -> [String]? {
        typeInventoryReadCount += 1
        guard items.indices.contains(index) else {
            return nil
        }
        return items[index].representations.keys.sorted()
    }

    public func data(forTypeIdentifier typeIdentifier: String, itemAt index: Int) -> Data? {
        representationReadCount += 1
        if delayNextDataRead > 0 {
            let delay = delayNextDataRead
            delayNextDataRead = 0
            Thread.sleep(forTimeInterval: delay)
        }
        if failNextDataRead {
            failNextDataRead = false
            return nil
        }
        guard items.indices.contains(index) else {
            return nil
        }
        let result = items[index].representations[typeIdentifier]
        if changeGenerationAfterNextDataRead {
            changeGenerationAfterNextDataRead = false
            incrementGeneration()
        }
        if let permissionStateAfterNextDataRead {
            self.permissionStateAfterNextDataRead = nil
            permissionState = permissionStateAfterNextDataRead
        }
        return result
    }

    public func prepareWrite(_ request: PasteboardWriteRequest) -> PasteboardPreparedWrite? {
        preparedWriteCount += 1
        if failNextPrepareWrite {
            failNextPrepareWrite = false
            return nil
        }
        guard !request.content.isEmpty,
              request.content.combinedUTF8ByteCount <= PasteboardSnapshotReader.maximumCombinedBytes
        else {
            return nil
        }
        return PasteboardPreparedWrite(request: request, platformItem: nil)
    }

    @discardableResult
    public func prepareForNewContentsCurrentHostOnly() -> PasteboardGeneration {
        currentHostOnlyPrepareCount += 1
        items = []
        incrementGeneration()
        let preparedGeneration = generation
        if let externalItemsAfterNextPrepare {
            self.externalItemsAfterNextPrepare = nil
            items = externalItemsAfterNextPrepare
            incrementGeneration()
        }
        return preparedGeneration
    }

    public func writePrepared(_ preparedWrite: PasteboardPreparedWrite) -> Bool {
        committedWriteCount += 1
        if failNextCommit {
            failNextCommit = false
            return false
        }

        var item = FakePasteboardItem(
            content: preparedWrite.request.content,
            includesTrackerFreeMarker: preparedWrite.request.includesTrackerFreeMarker
        )
        if corruptNextCommittedWrite {
            corruptNextCommittedWrite = false
            item.representations[PasteboardTypeIdentifier.plainText] = Data("corrupt".utf8)
        }
        items = [item]
        if let externalItemsAfterNextCommit {
            self.externalItemsAfterNextCommit = nil
            items = externalItemsAfterNextCommit
            incrementGeneration()
        }
        return true
    }

    public func replaceExternally(with newItems: [FakePasteboardItem]) {
        items = newItems
        incrementGeneration()
    }

    public func replaceExternally(
        with content: PasteboardContent,
        includesTrackerFreeMarker: Bool = false
    ) {
        replaceExternally(with: [
            FakePasteboardItem(
                content: content,
                includesTrackerFreeMarker: includesTrackerFreeMarker
            ),
        ])
    }

    public func clearExternally() {
        replaceExternally(with: [])
    }

    private func incrementGeneration() {
        generation = PasteboardGeneration(rawValue: generation.rawValue &+ 1)
    }
}
