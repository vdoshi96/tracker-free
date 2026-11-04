import AppKit
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
        switch markerPolicy {
        case .require:
            allowedTypes.insert(PasteboardTypeIdentifier.trackerFreeMarker)
        case .forbid:
            // Browsers add companions when a page copies a URL as text (for
            // example X's web "Copy link"). They are admitted only beside plain
            // text and only when proven redundant below; cleaned writes never
            // carry them.
            allowedTypes.formUnion(PasteboardCompanionPolicy.companionTypes)
        }
        guard typeSet.isSubset(of: allowedTypes) else {
            return .failure(.unsupportedType)
        }
        guard !typeSet.isDisjoint(with: PasteboardTypeIdentifier.allowedContent) else {
            return .failure(.missingAllowedRepresentation)
        }
        let companionTypes = typeSet.intersection(PasteboardCompanionPolicy.companionTypes)
        if !companionTypes.isEmpty,
           !typeSet.contains(PasteboardTypeIdentifier.plainText) {
            return .failure(.unsupportedType)
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
        var companions: [String: Data] = [:]

        // Every read, primary or companion, shares one generation, duration, and
        // combined-size bound.
        func readBounded(_ typeIdentifier: String) -> Result<Data, PasteboardSnapshotFailure> {
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
            return .success(data)
        }

        for typeIdentifier in [
            PasteboardTypeIdentifier.plainText,
            PasteboardTypeIdentifier.url,
        ] where typeSet.contains(typeIdentifier) {
            let data: Data
            switch readBounded(typeIdentifier) {
            case let .success(value): data = value
            case let .failure(failure): return .failure(failure)
            }

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

        for typeIdentifier in companionTypes.sorted() {
            switch readBounded(typeIdentifier) {
            case let .success(data): companions[typeIdentifier] = data
            case let .failure(failure): return .failure(failure)
            }
        }

        let content = PasteboardContent(
            plainText: plainText,
            url: url,
            companions: companions
        )
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

        if !companions.isEmpty {
            guard let plainText,
                  PasteboardCompanionPolicy.areRedundant(companions, plainText: plainText)
            else {
                return .failure(.unsupportedType)
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

/// Decides which browser-added representations may accompany a plain-text URL.
///
/// `VERIFIED` (2026-11-04): a page copy that mirrors X's web "Copy link" puts one
/// item on the General pasteboard holding `public.utf8-plain-text` plus:
/// - Firefox: `public.html`.
/// - Chrome 156: `public.html`, `org.chromium.source-url`, and
///   `org.chromium.internal.source-rfh-token`.
/// - System WebKit (Safari 27.3's engine): `com.apple.webarchive`, `public.rtf`,
///   `public.html`, `public.utf16-external-plain-text`, and
///   `com.apple.WebKit.custom-pasteboard-data`.
///
/// Each companion must prove it adds nothing: rich forms must render exactly the
/// plain-text URL with no link or embedded resource, alternate text must equal
/// the plain text, and metadata must be bounded and carry no page-supplied data.
/// Anything unproven keeps the whole item a hard skip.
enum PasteboardCompanionPolicy {
    static let companionTypes: Set<String> = [
        PasteboardTypeIdentifier.html,
        PasteboardTypeIdentifier.rtf,
        PasteboardTypeIdentifier.webArchive,
        PasteboardTypeIdentifier.utf16ExternalPlainText,
        PasteboardTypeIdentifier.webKitCustomData,
        PasteboardTypeIdentifier.chromiumSourceURL,
        PasteboardTypeIdentifier.chromiumSourceFrameToken,
    ]

    static let maximumChromiumSourceURLBytes = 8 * 1_024
    static let maximumChromiumFrameTokenBytes = 64
    static let maximumWebKitOriginBytes = 2 * 1_024

    private static let webArchiveResourceKeys: Set<String> = [
        "WebResourceData",
        "WebResourceFrameName",
        "WebResourceMIMEType",
        "WebResourceTextEncodingName",
        "WebResourceURL",
    ]

    @MainActor
    static func areRedundant(_ companions: [String: Data], plainText: String) -> Bool {
        guard let core = PlainTextEnvelope.core(from: plainText) else {
            return false
        }
        return companions.allSatisfy { type, data in
            isRedundant(type: type, data: data, plainText: plainText, core: core)
        }
    }

    @MainActor
    private static func isRedundant(
        type: String,
        data: Data,
        plainText: String,
        core: String
    ) -> Bool {
        switch type {
        case PasteboardTypeIdentifier.html:
            return strictUTF8(data).flatMap(RedundantURLHTML.textContent(of:)) == core
        case PasteboardTypeIdentifier.rtf:
            return rtfText(data) == core
        case PasteboardTypeIdentifier.webArchive:
            return webArchiveText(data) == core
        case PasteboardTypeIdentifier.utf16ExternalPlainText:
            return externalUTF16(data) == plainText
        case PasteboardTypeIdentifier.webKitCustomData:
            return isEmptyWebKitCustomData(data)
        case PasteboardTypeIdentifier.chromiumSourceURL:
            return isInertSourceURL(data)
        case PasteboardTypeIdentifier.chromiumSourceFrameToken:
            return (1...maximumChromiumFrameTokenBytes).contains(data.count)
        default:
            return false
        }
    }

    private static func strictUTF8(_ data: Data) -> String? {
        guard let value = String(data: data, encoding: .utf8),
              Data(value.utf8) == data
        else {
            return nil
        }
        return value
    }

    /// RTF text with edge whitespace trimmed, or nil when the document carries a
    /// link or attachment. Styling such as font and kerning is not content.
    @MainActor
    private static func rtfText(_ data: Data) -> String? {
        guard data.starts(with: Array("{\\rtf".utf8)),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                  documentAttributes: nil
              )
        else {
            return nil
        }
        var index = 0
        while index < attributed.length {
            var range = NSRange(location: 0, length: 0)
            let attributes = attributed.attributes(at: index, effectiveRange: &range)
            if attributes[.link] != nil || attributes[.attachment] != nil {
                return nil
            }
            index = max(index + 1, NSMaxRange(range))
        }
        return trimmingHTMLWhitespace(attributed.string)
    }

    /// The text of a web archive holding exactly one redundant HTML resource and
    /// no subresources or subframes.
    private static func webArchiveText(_ data: Data) -> String? {
        guard let archive = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ) as? [String: Any],
              Set(archive.keys) == ["WebMainResource"],
              let resource = archive["WebMainResource"] as? [String: Any],
              Set(resource.keys).isSubset(of: webArchiveResourceKeys),
              resource["WebResourceMIMEType"] as? String == "text/html",
              let body = resource["WebResourceData"] as? Data,
              let html = strictUTF8(body)
        else {
            return nil
        }
        if let encoding = resource["WebResourceTextEncodingName"] {
            guard let name = encoding as? String, name.lowercased() == "utf-8" else {
                return nil
            }
        }
        for key in ["WebResourceFrameName", "WebResourceURL"] where resource[key] != nil {
            guard resource[key] is String else {
                return nil
            }
        }
        return RedundantURLHTML.textContent(of: html)
    }

    /// UTF-16 text with a mandatory byte-order mark, as "external" text carries.
    private static func externalUTF16(_ data: Data) -> String? {
        guard data.count >= 2, data.count % 2 == 0 else {
            return nil
        }
        let encoding: String.Encoding
        switch (data[data.startIndex], data[data.startIndex + 1]) {
        case (0xFF, 0xFE): encoding = .utf16LittleEndian
        case (0xFE, 0xFF): encoding = .utf16BigEndian
        default: return nil
        }
        return String(data: data.dropFirst(2), encoding: encoding)
    }

    /// WebKit's PasteboardCustomData serialization, version 1: a UInt32 version,
    /// the origin as a UInt32 length (0xFFFFFFFF for null) with an 8-bit flag and
    /// characters, then the same-origin string map and ordered type list as UInt64
    /// counts. Only empty map and list counts prove no page-supplied data.
    private static func isEmptyWebKitCustomData(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        func littleEndianUInt32(at offset: Int) -> UInt32? {
            guard offset + 4 <= bytes.count else {
                return nil
            }
            return bytes[offset..<(offset + 4)].reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }
        guard littleEndianUInt32(at: 0) == 1,
              let originLength = littleEndianUInt32(at: 4)
        else {
            return false
        }

        let countsStart: Int
        if originLength == UInt32.max {
            countsStart = 8
        } else {
            guard bytes.count > 8, bytes[8] <= 1 else {
                return false
            }
            let characterBytes = Int(originLength) * (bytes[8] == 1 ? 1 : 2)
            guard characterBytes <= maximumWebKitOriginBytes else {
                return false
            }
            countsStart = 9 + characterBytes
        }
        guard countsStart + 16 == bytes.count else {
            return false
        }
        return bytes[countsStart...].allSatisfy { $0 == 0 }
    }

    /// The source page's address as Chromium records it: bounded UTF-8 with no
    /// control characters. It describes the copy and is never written back clean.
    private static func isInertSourceURL(_ data: Data) -> Bool {
        guard (1...maximumChromiumSourceURLBytes).contains(data.count),
              strictUTF8(data) != nil
        else {
            return false
        }
        return data.allSatisfy { $0 >= 0x20 && $0 != 0x7F }
    }

    private static func trimmingHTMLWhitespace(_ value: String) -> String {
        let whitespace: Set<Character> = [" ", "\t", "\n", "\u{0C}", "\r", "\r\n"]
        var characters = Substring(value)
        while let first = characters.first, whitespace.contains(first) {
            characters.removeFirst()
        }
        while let last = characters.last, whitespace.contains(last) {
            characters.removeLast()
        }
        return String(characters)
    }
}

/// Recognizes the HTML a browser adds when a web page copies a URL as text.
///
/// Returns the decoded visible text only when the markup consists solely of
/// structural wrappers (`html`, `head`, `meta`, `body`, `span`), comments, and a
/// doctype. Any other element, a bare `<` or `&`, an unknown entity, or
/// unterminated markup returns nil, so genuinely rich content stays a hard skip.
/// Attribute values are skipped, never interpreted: the HTML is only ever kept
/// for byte-exact restoration, so its styling carries no meaning here.
enum RedundantURLHTML {
    private static let permittedElements: Set<String> = [
        "html", "head", "meta", "body", "span",
    ]
    private static let maximumEntityLength = 12

    static func textContent(of html: String) -> String? {
        let bytes = Array(html.utf8)
        var text: [UInt8] = []
        text.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 0x3C: // <
                guard let next = endOfMarkup(bytes, from: index) else {
                    return nil
                }
                index = next
            case 0x26: // &
                guard let (decoded, next) = decodeEntity(bytes, from: index) else {
                    return nil
                }
                text.append(contentsOf: decoded)
                index = next
            default:
                text.append(bytes[index])
                index += 1
            }
        }

        var start = text.startIndex
        var end = text.endIndex
        while start < end, isHTMLWhitespace(text[start]) {
            start += 1
        }
        while end > start, isHTMLWhitespace(text[end - 1]) {
            end -= 1
        }
        return String(decoding: text[start..<end], as: UTF8.self)
    }

    /// Returns the index just past a permitted tag, comment, or doctype.
    private static func endOfMarkup(_ bytes: [UInt8], from start: Int) -> Int? {
        if hasPrefix(bytes, at: start, "<!--") {
            var index = start + 4
            while index + 2 < bytes.count {
                if bytes[index] == 0x2D, bytes[index + 1] == 0x2D, bytes[index + 2] == 0x3E {
                    return index + 3
                }
                index += 1
            }
            return nil
        }
        if hasPrefix(bytes, at: start, "<!doctype", caseInsensitive: true) {
            guard let close = bytes[start...].firstIndex(of: 0x3E) else {
                return nil
            }
            return close + 1
        }

        var index = start + 1
        if index < bytes.count, bytes[index] == 0x2F { // /
            index += 1
        }
        let nameStart = index
        while index < bytes.count, isASCIIAlphaNumeric(bytes[index]) {
            index += 1
        }
        guard index > nameStart, isASCIILetter(bytes[nameStart]) else {
            return nil
        }
        let name = String(decoding: bytes[nameStart..<index].map(asciiLowercased), as: UTF8.self)
        guard permittedElements.contains(name), index < bytes.count else {
            return nil
        }
        guard isHTMLWhitespace(bytes[index]) || bytes[index] == 0x2F || bytes[index] == 0x3E else {
            return nil
        }

        while index < bytes.count {
            switch bytes[index] {
            case 0x3E: // >
                return index + 1
            case 0x22, 0x27: // " or '
                let quote = bytes[index]
                index += 1
                while index < bytes.count, bytes[index] != quote {
                    index += 1
                }
                guard index < bytes.count else {
                    return nil
                }
                index += 1
            case 0x3C: // < inside a tag is malformed
                return nil
            default:
                index += 1
            }
        }
        return nil
    }

    private static func decodeEntity(
        _ bytes: [UInt8],
        from start: Int
    ) -> (decoded: [UInt8], next: Int)? {
        let limit = min(bytes.count, start + maximumEntityLength)
        guard let semicolon = bytes[(start + 1)..<limit].firstIndex(of: 0x3B) else {
            return nil
        }
        let name = Array(bytes[(start + 1)..<semicolon])
        let next = semicolon + 1

        switch String(decoding: name, as: UTF8.self) {
        case "amp": return (Array("&".utf8), next)
        case "lt": return (Array("<".utf8), next)
        case "gt": return (Array(">".utf8), next)
        case "quot": return (Array("\"".utf8), next)
        case "apos": return (Array("'".utf8), next)
        default: break
        }

        guard name.first == 0x23 else { // #
            return nil
        }
        var digits = name.dropFirst()
        var radix: UInt32 = 10
        if let marker = digits.first, marker == 0x78 || marker == 0x58 { // x or X
            radix = 16
            digits = digits.dropFirst()
        }
        guard !digits.isEmpty, digits.count <= 8 else {
            return nil
        }
        var value: UInt32 = 0
        for byte in digits {
            guard let digit = hexValue(byte), digit < radix else {
                return nil
            }
            value = value * radix + digit
        }
        guard value != 0, let scalar = Unicode.Scalar(value) else {
            return nil
        }
        return (Array(String(Character(scalar)).utf8), next)
    }

    private static func hasPrefix(
        _ bytes: [UInt8],
        at start: Int,
        _ prefix: String,
        caseInsensitive: Bool = false
    ) -> Bool {
        let expected = Array(prefix.utf8)
        guard start + expected.count <= bytes.count else {
            return false
        }
        for offset in expected.indices {
            let actual = bytes[start + offset]
            let matches = caseInsensitive
                ? asciiLowercased(actual) == expected[offset]
                : actual == expected[offset]
            guard matches else {
                return false
            }
        }
        return true
    }

    private static func hexValue(_ byte: UInt8) -> UInt32? {
        switch byte {
        case 0x30...0x39: UInt32(byte - 0x30)
        case 0x41...0x46: UInt32(byte - 0x41 + 10)
        case 0x61...0x66: UInt32(byte - 0x61 + 10)
        default: nil
        }
    }

    private static func isHTMLWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }

    private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        isASCIILetter(byte) || (byte >= 0x30 && byte <= 0x39)
    }

    private static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        (byte >= 0x41 && byte <= 0x5A) ? byte + 0x20 : byte
    }
}
