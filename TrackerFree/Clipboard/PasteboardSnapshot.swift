import Foundation

public struct PasteboardSnapshot: Equatable, Sendable {
    public let generation: PasteboardGeneration
    public let content: PasteboardContent

    public init(generation: PasteboardGeneration, content: PasteboardContent) {
        self.generation = generation
        self.content = content
    }
}

public enum PasteboardSnapshotFailure: Error, Equatable, Sendable {
    case generationChanged
    case itemInventoryUnavailable
    case requiresExactlyOneItem
    case unsupportedType
    case appMarkerFromUnownedGeneration
    case missingAllowedRepresentation
    case representationUnavailable
    case invalidUTF8
    case sizeLimitExceeded
    case conflictingRepresentations
    case markerMissingOrInvalid
}

enum PasteboardMarkerPolicy: Equatable {
    case forbid
    case require
}

enum PasteboardSnapshotReader {
    static let maximumCombinedBytes = 64 * 1_024
    static let maximumRepresentationReadDuration = Duration.milliseconds(100)

    @MainActor
    static func capture(
        from client: any PasteboardClient,
        expectedGeneration: PasteboardGeneration,
        markerPolicy: PasteboardMarkerPolicy = .forbid
    ) -> Result<PasteboardSnapshot, PasteboardSnapshotFailure> {
        guard client.generation == expectedGeneration else {
            return .failure(.generationChanged)
        }

        guard let itemCount = client.itemCount() else {
            return .failure(.itemInventoryUnavailable)
        }
        guard client.generation == expectedGeneration else {
            return .failure(.generationChanged)
        }
        guard itemCount == 1 else {
            return .failure(.requiresExactlyOneItem)
        }

        guard let typeIdentifiers = client.typeIdentifiers(forItemAt: 0) else {
            return .failure(.itemInventoryUnavailable)
        }
        guard client.generation == expectedGeneration else {
            return .failure(.generationChanged)
        }

        let typeSet = Set(typeIdentifiers)
        guard typeSet.count == typeIdentifiers.count else {
            return .failure(.unsupportedType)
        }

        let includesMarker = typeSet.contains(PasteboardTypeIdentifier.trackerFreeMarker)
        switch markerPolicy {
        case .forbid:
            if includesMarker {
                return .failure(.appMarkerFromUnownedGeneration)
            }
        case .require:
            guard includesMarker else {
                return .failure(.markerMissingOrInvalid)
            }
        }

        var allowedTypes = PasteboardTypeIdentifier.allowedContent
        if markerPolicy == .require {
            allowedTypes.insert(PasteboardTypeIdentifier.trackerFreeMarker)
        }
        guard typeSet.isSubset(of: allowedTypes) else {
            return .failure(.unsupportedType)
        }
        guard !typeSet.isDisjoint(with: PasteboardTypeIdentifier.allowedContent) else {
            return .failure(.missingAllowedRepresentation)
        }

        if markerPolicy == .require {
            guard let markerData = client.data(
                forTypeIdentifier: PasteboardTypeIdentifier.trackerFreeMarker,
                itemAt: 0
            ) else {
                return .failure(.markerMissingOrInvalid)
            }
            guard client.generation == expectedGeneration else {
                return .failure(.generationChanged)
            }
            guard markerData.isEmpty else {
                return .failure(.markerMissingOrInvalid)
            }
        }

        var combinedByteCount = 0
        var plainText: String?
        var url: String?

        for typeIdentifier in [
            PasteboardTypeIdentifier.plainText,
            PasteboardTypeIdentifier.url,
        ] where typeSet.contains(typeIdentifier) {
            let clock = ContinuousClock()
            let readStart = clock.now
            guard let data = client.data(forTypeIdentifier: typeIdentifier, itemAt: 0) else {
                return .failure(.representationUnavailable)
            }
            guard client.generation == expectedGeneration else {
                return .failure(.generationChanged)
            }
            guard readStart.duration(to: clock.now) <= maximumRepresentationReadDuration else {
                // A synchronous AppKit provider cannot be preempted safely without moving
                // pasteboard objects across an actor. A late return is still rejected.
                return .failure(.representationUnavailable)
            }

            let (nextByteCount, overflow) = combinedByteCount.addingReportingOverflow(data.count)
            guard !overflow, nextByteCount <= maximumCombinedBytes else {
                return .failure(.sizeLimitExceeded)
            }
            combinedByteCount = nextByteCount

            guard let value = String(data: data, encoding: .utf8),
                  Data(value.utf8) == data
            else {
                return .failure(.invalidUTF8)
            }

            if typeIdentifier == PasteboardTypeIdentifier.plainText {
                plainText = value
            } else {
                url = value
            }
        }

        let content = PasteboardContent(plainText: plainText, url: url)
        guard !content.isEmpty else {
            return .failure(.missingAllowedRepresentation)
        }

        if let plainText, let url {
            guard let plainTextCore = PlainTextEnvelope.core(from: plainText),
                  plainTextCore == url
            else {
                return .failure(.conflictingRepresentations)
            }
        }

        return .success(PasteboardSnapshot(
            generation: expectedGeneration,
            content: content
        ))
    }

    @MainActor
    static func verify(
        _ expectedContent: PasteboardContent,
        includesMarker: Bool,
        in client: any PasteboardClient,
        generation: PasteboardGeneration
    ) -> Bool {
        let markerPolicy: PasteboardMarkerPolicy = includesMarker ? .require : .forbid
        guard case let .success(snapshot) = capture(
            from: client,
            expectedGeneration: generation,
            markerPolicy: markerPolicy
        ) else {
            return false
        }
        return snapshot.content == expectedContent && client.generation == generation
    }
}

enum PlainTextEnvelope {
    /// Returns the URL core only when the surrounding bytes use the permitted v1 envelope.
    static func core(from value: String) -> String? {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty else {
            return nil
        }

        var end = bytes.count
        if bytes[end - 1] == 0x0A {
            end -= 1
            if end > 0, bytes[end - 1] == 0x0D {
                end -= 1
            }
        }

        guard !bytes[..<end].contains(0x0A),
              !bytes[..<end].contains(0x0D)
        else {
            return nil
        }

        var coreEnd = end
        while coreEnd > 0 && (bytes[coreEnd - 1] == 0x20 || bytes[coreEnd - 1] == 0x09) {
            coreEnd -= 1
        }

        var coreStart = 0
        while coreStart < coreEnd && (bytes[coreStart] == 0x20 || bytes[coreStart] == 0x09) {
            coreStart += 1
        }

        guard coreStart < coreEnd else {
            return nil
        }
        return String(decoding: bytes[coreStart..<coreEnd], as: UTF8.self)
    }
}
