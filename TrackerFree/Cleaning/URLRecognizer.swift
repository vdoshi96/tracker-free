import Foundation

public enum URLRecognitionFailure: String, Error, Sendable, Equatable {
    case inputTooLarge
    case invalidEnvelope
    case emptyURL
    case nonASCII
    case unsupportedScheme
    case invalidCharacter
    case malformedPercentEscape
    case nestedLiteralURL
    case missingHost
    case credentials
    case invalidHost
    case localOrIPHost
    case invalidPort
    case structuralLimitExceeded
    case foundationRejected
    case foundationChangedSpelling
}

/// An immutable, byte-faithful view of one strictly recognized HTTP(S) URL.
///
/// `URLComponents` participates only in validation. Every raw component stored
/// here comes from the original string and is the only source used by cleaning.
public struct RecognizedURL: Sendable, Equatable {
    public let original: String
    public let envelopePrefix: String
    public let core: String
    public let envelopeSuffix: String
    public let scheme: String
    public let canonicalHost: String
    public let port: Int?
    public let rawAuthority: String
    public let rawPath: String
    public let rawQuery: String?
    public let rawFragment: String?
    public let rawPrefixThroughPath: String
    public let rawFragmentWithDelimiter: String

    public var hasQueryDelimiter: Bool {
        rawQuery != nil
    }
}

public enum URLRecognizer {
    public static let maximumUTF8ByteCount = 64 * 1024
    public static let maximumPathUTF8ByteCount = 8 * 1024
    public static let maximumFragmentUTF8ByteCount = 8 * 1024

    public static func recognize(
        _ input: String
    ) -> Result<RecognizedURL, URLRecognitionFailure> {
        var inputBytes: [UInt8] = []
        inputBytes.reserveCapacity(maximumUTF8ByteCount + 1)
        for byte in input.utf8.prefix(maximumUTF8ByteCount + 1) {
            inputBytes.append(byte)
        }
        guard inputBytes.count <= maximumUTF8ByteCount else {
            return .failure(.inputTooLarge)
        }

        guard let envelope = splitEnvelope(inputBytes) else {
            return .failure(.invalidEnvelope)
        }
        let coreBytes = Array(envelope.core)
        guard !coreBytes.isEmpty else {
            return .failure(.emptyURL)
        }
        guard coreBytes.allSatisfy({ $0 < 0x80 }) else {
            return .failure(.nonASCII)
        }
        guard coreBytes.allSatisfy({ $0 >= 0x21 && $0 <= 0x7E }) else {
            return .failure(.invalidCharacter)
        }
        guard !coreBytes.contains(0x5C) else {
            return .failure(.invalidCharacter)
        }
        guard hasValidPercentEscapes(coreBytes[...]) else {
            return .failure(.malformedPercentEscape)
        }

        let lowerCore = coreBytes.map(asciiLowercasedByte)
        let scheme: String
        let authorityStart: Int
        if lowerCore.starts(with: Array("https://".utf8)) {
            scheme = "https"
            authorityStart = 8
        } else if lowerCore.starts(with: Array("http://".utf8)) {
            scheme = "http"
            authorityStart = 7
        } else {
            return .failure(.unsupportedScheme)
        }

        if containsLiteralScheme(lowerCore, startingAt: authorityStart) {
            return .failure(.nestedLiteralURL)
        }

        let fragmentIndex = coreBytes.firstIndex(of: 0x23)
        let querySearchEnd = fragmentIndex ?? coreBytes.count
        let queryIndex = coreBytes[..<querySearchEnd].firstIndex(of: 0x3F)
        let authorityEnd = coreBytes[authorityStart...].firstIndex {
            $0 == 0x2F || $0 == 0x3F || $0 == 0x23
        } ?? coreBytes.count

        guard authorityStart < authorityEnd else {
            return .failure(.missingHost)
        }

        let authorityBytes = Array(coreBytes[authorityStart..<authorityEnd])
        guard !authorityBytes.contains(0x40) else {
            return .failure(.credentials)
        }

        let parsedAuthority: (host: String, port: Int?)
        switch parseAuthority(authorityBytes) {
        case let .success(value):
            parsedAuthority = value
        case let .failure(error):
            return .failure(error)
        }

        let canonicalHost = asciiLowercased(parsedAuthority.host)
        guard isValidCanonicalRuleHost(canonicalHost) else {
            return .failure(.invalidHost)
        }
        guard !isLocalOrIPHost(canonicalHost) else {
            return .failure(.localOrIPHost)
        }

        let pathEnd = queryIndex ?? fragmentIndex ?? coreBytes.count
        guard pathEnd - authorityEnd <= maximumPathUTF8ByteCount else {
            return .failure(.structuralLimitExceeded)
        }
        if let fragmentIndex,
           coreBytes.count - fragmentIndex - 1
            > maximumFragmentUTF8ByteCount
        {
            return .failure(.structuralLimitExceeded)
        }
        let rawPath = String(decoding: coreBytes[authorityEnd..<pathEnd], as: UTF8.self)
        let rawQuery: String?
        if let queryIndex {
            let end = fragmentIndex ?? coreBytes.count
            rawQuery = String(
                decoding: coreBytes[(queryIndex + 1)..<end],
                as: UTF8.self
            )
        } else {
            rawQuery = nil
        }
        let rawFragment: String?
        let fragmentWithDelimiter: String
        if let fragmentIndex {
            rawFragment = String(
                decoding: coreBytes[(fragmentIndex + 1)...],
                as: UTF8.self
            )
            fragmentWithDelimiter = String(
                decoding: coreBytes[fragmentIndex...],
                as: UTF8.self
            )
        } else {
            rawFragment = nil
            fragmentWithDelimiter = ""
        }

        let core = String(decoding: coreBytes, as: UTF8.self)
        guard let components = URLComponents(string: core) else {
            return .failure(.foundationRejected)
        }
        guard components.string == core else {
            return .failure(.foundationChangedSpelling)
        }
        guard asciiLowercased(components.scheme ?? "") == scheme,
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.port == parsedAuthority.port
        else {
            return .failure(.foundationRejected)
        }

        let prefix = String(decoding: envelope.prefix, as: UTF8.self)
        let suffix = String(decoding: envelope.suffix, as: UTF8.self)
        let prefixThroughPath = String(
            decoding: coreBytes[..<pathEnd],
            as: UTF8.self
        )
        let authority = String(decoding: authorityBytes, as: UTF8.self)

        return .success(
            RecognizedURL(
                original: input,
                envelopePrefix: prefix,
                core: core,
                envelopeSuffix: suffix,
                scheme: scheme,
                canonicalHost: canonicalHost,
                port: parsedAuthority.port,
                rawAuthority: authority,
                rawPath: rawPath,
                rawQuery: rawQuery,
                rawFragment: rawFragment,
                rawPrefixThroughPath: prefixThroughPath,
                rawFragmentWithDelimiter: fragmentWithDelimiter
            )
        )
    }

    /// Validates canonical rule hosts without DNS lookup or Foundation repair.
    public static func isValidCanonicalRuleHost(_ host: String) -> Bool {
        let bytes = Array(host.utf8)
        guard !bytes.isEmpty,
              bytes.count <= 253,
              bytes.allSatisfy({ $0 < 0x80 }),
              host == asciiLowercased(host),
              host.contains("."),
              !host.hasPrefix("."),
              !host.hasSuffix(".")
        else {
            return false
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else {
            return false
        }
        return labels.allSatisfy { label in
            guard !label.isEmpty,
                  label.utf8.count <= 63,
                  label.first != "-",
                  label.last != "-"
            else {
                return false
            }
            return label.utf8.allSatisfy {
                ($0 >= 0x61 && $0 <= 0x7A)
                    || ($0 >= 0x30 && $0 <= 0x39)
                    || $0 == 0x2D
            }
        }
    }

    public static func isLocalOrIPHost(_ canonicalHost: String) -> Bool {
        let host = asciiLowercased(canonicalHost)
        if host == "localhost" || host.hasSuffix(".localhost") {
            return true
        }

        let privateBases = [
            "local", "internal", "intranet", "lan", "home",
            "home.arpa", "corp",
        ]
        if privateBases.contains(where: {
            host == $0 || host.hasSuffix("." + $0)
        }) {
            return true
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count < 2 {
            return true
        }

        // Reject conventional and legacy numeric IP spellings. Hostname
        // resolution is intentionally never attempted.
        if labels.allSatisfy({ looksNumeric($0) }) {
            return true
        }
        return false
    }

    private static func splitEnvelope(
        _ bytes: [UInt8]
    ) -> (prefix: ArraySlice<UInt8>, core: ArraySlice<UInt8>, suffix: ArraySlice<UInt8>)? {
        var prefixEnd = 0
        while prefixEnd < bytes.count,
              bytes[prefixEnd] == 0x20 || bytes[prefixEnd] == 0x09 {
            prefixEnd += 1
        }

        var contentEnd = bytes.count
        if bytes.last == 0x0A {
            contentEnd -= 1
            if contentEnd > 0, bytes[contentEnd - 1] == 0x0D {
                contentEnd -= 1
            }
        } else if bytes.last == 0x0D {
            return nil
        }

        var coreEnd = contentEnd
        while coreEnd > prefixEnd,
              bytes[coreEnd - 1] == 0x20 || bytes[coreEnd - 1] == 0x09 {
            coreEnd -= 1
        }

        guard prefixEnd <= coreEnd else {
            return nil
        }
        return (
            bytes[..<prefixEnd],
            bytes[prefixEnd..<coreEnd],
            bytes[coreEnd...]
        )
    }

    private static func parseAuthority(
        _ authority: [UInt8]
    ) -> Result<(host: String, port: Int?), URLRecognitionFailure> {
        guard !authority.isEmpty else {
            return .failure(.missingHost)
        }
        guard !authority.contains(0x5B), !authority.contains(0x5D) else {
            return .failure(.localOrIPHost)
        }

        let colonIndices = authority.indices.filter { authority[$0] == 0x3A }
        guard colonIndices.count <= 1 else {
            return .failure(.invalidHost)
        }

        let hostBytes: ArraySlice<UInt8>
        let port: Int?
        if let colon = colonIndices.first {
            hostBytes = authority[..<colon]
            let portBytes = authority[(colon + 1)...]
            guard !portBytes.isEmpty,
                  portBytes.count <= 5,
                  portBytes.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
                  let parsedPort = Int(String(decoding: portBytes, as: UTF8.self)),
                  (1...65_535).contains(parsedPort)
            else {
                return .failure(.invalidPort)
            }
            port = parsedPort
        } else {
            hostBytes = authority[...]
            port = nil
        }

        guard !hostBytes.isEmpty else {
            return .failure(.missingHost)
        }
        let host = String(decoding: hostBytes, as: UTF8.self)
        return .success((host, port))
    }

    private static func hasValidPercentEscapes(_ bytes: ArraySlice<UInt8>) -> Bool {
        var index = bytes.startIndex
        while index < bytes.endIndex {
            if bytes[index] == 0x25 {
                let first = bytes.index(after: index)
                guard first < bytes.endIndex else {
                    return false
                }
                let second = bytes.index(after: first)
                guard second < bytes.endIndex,
                      isHex(bytes[first]),
                      isHex(bytes[second])
                else {
                    return false
                }
                index = bytes.index(after: second)
            } else {
                index = bytes.index(after: index)
            }
        }
        return true
    }

    private static func containsLiteralScheme(
        _ lowerCore: [UInt8],
        startingAt start: Int
    ) -> Bool {
        let http = Array("http://".utf8)
        let https = Array("https://".utf8)
        guard start < lowerCore.count else {
            return false
        }
        for index in start..<lowerCore.count {
            if lowerCore[index...].starts(with: http)
                || lowerCore[index...].starts(with: https) {
                return true
            }
        }
        return false
    }

    private static func looksNumeric(_ label: Substring) -> Bool {
        let lower = asciiLowercased(String(label))
        if lower.hasPrefix("0x"), lower.count > 2 {
            return lower.dropFirst(2).utf8.allSatisfy(isHex)
        }
        return !lower.isEmpty && lower.utf8.allSatisfy {
            $0 >= 0x30 && $0 <= 0x39
        }
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39)
            || (byte >= 0x41 && byte <= 0x46)
            || (byte >= 0x61 && byte <= 0x66)
    }

    private static func asciiLowercasedByte(_ byte: UInt8) -> UInt8 {
        if byte >= 0x41 && byte <= 0x5A {
            return byte + 0x20
        }
        return byte
    }

    private static func asciiLowercased(_ value: String) -> String {
        String(decoding: value.utf8.map(asciiLowercasedByte), as: UTF8.self)
    }
}
