import AppKit
import Foundation

@MainActor
final class AppKitPasteboardClient {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    var generation: PasteboardGeneration {
        PasteboardGeneration(rawValue: pasteboard.changeCount)
    }

    func itemCount() -> Int? {
        pasteboard.pasteboardItems?.count ?? 0
    }

    func typeIdentifiers(forItemAt index: Int) -> [String]? {
        guard let items = pasteboard.pasteboardItems,
              items.indices.contains(index)
        else {
            return nil
        }
        return items[index].types.map(\.rawValue)
    }

    func data(forTypeIdentifier typeIdentifier: String, itemAt index: Int) -> Data? {
        guard let items = pasteboard.pasteboardItems,
              items.indices.contains(index)
        else {
            return nil
        }
        return items[index].data(forType: NSPasteboard.PasteboardType(typeIdentifier))
    }

    func prepareWrite(_ request: PasteboardWriteRequest) -> PasteboardPreparedWrite? {
        guard !request.content.isEmpty,
              request.content.combinedUTF8ByteCount <= PasteboardSnapshotReader.maximumCombinedBytes
        else {
            return nil
        }

        let item = NSPasteboardItem()
        if let plainText = request.content.plainText {
            guard item.setString(plainText, forType: .string) else {
                return nil
            }
        }
        if let url = request.content.url {
            guard item.setString(url, forType: .URL) else {
                return nil
            }
        }
        if request.includesTrackerFreeMarker {
            guard item.setData(
                Data(),
                forType: NSPasteboard.PasteboardType(PasteboardTypeIdentifier.trackerFreeMarker)
            ) else {
                return nil
            }
        }

        return PasteboardPreparedWrite(request: request, platformItem: item)
    }

    @discardableResult
    func prepareForNewContentsCurrentHostOnly() -> PasteboardGeneration {
        PasteboardGeneration(rawValue: pasteboard.prepareForNewContents(with: .currentHostOnly))
    }

    func writePrepared(_ preparedWrite: PasteboardPreparedWrite) -> Bool {
        guard let item = preparedWrite.platformItem as? NSPasteboardItem else {
            return false
        }
        return pasteboard.writeObjects([item])
    }
}

/// The sole production adapter allowed to reference `NSPasteboard.general`.
@MainActor
public final class GeneralPasteboardClient: PasteboardClient {
    private let backing: AppKitPasteboardClient

    public init() {
        backing = AppKitPasteboardClient(pasteboard: NSPasteboard.general)
    }

    public var generation: PasteboardGeneration {
        backing.generation
    }

    public var permissionState: ClipboardPermissionState {
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .default:
                return .defaultBehavior
            case .ask:
                return .ask
            case .alwaysAllow:
                return .alwaysAllow
            case .alwaysDeny:
                return .alwaysDeny
            @unknown default:
                return .unknown
            }
        }
        return .notRequired
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
}
