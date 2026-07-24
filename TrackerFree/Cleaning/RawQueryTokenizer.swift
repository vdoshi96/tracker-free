import Foundation

public enum RawQueryTokenizationFailure: String, Error, Sendable, Equatable {
    case ambiguousSemicolon
    case tooManyFields
    case nonASCIIFieldName
    case malformedPercentEscape
}

public struct RawQueryField: Sendable, Equatable, Hashable {
    public let position: Int
    public let raw: String
    public let rawName: String
    public let rawValue: String?
    public let decodedASCIIName: String

    public init(
        position: Int,
        raw: String,
        rawName: String,
        rawValue: String?,
        decodedASCIIName: String
    ) {
        self.position = position
        self.raw = raw
        self.rawName = rawName
        self.rawValue = rawValue
        self.decodedASCIIName = decodedASCIIName
    }
}

public struct TokenizedRawQuery: Sendable, Equatable {
    public let original: String
    public let fields: [RawQueryField]

    public init(original: String, fields: [RawQueryField]) {
        self.original = original
        self.fields = fields
    }
}

public enum RawQueryTokenizer {
    public static let maximumFieldCount = 256

    public static func tokenize(
        _ rawQuery: String
    ) -> Result<TokenizedRawQuery, RawQueryTokenizationFailure> {
        guard !rawQuery.contains(";") else {
            return .failure(.ambiguousSemicolon)
        }

        var fieldCount = 1
        for byte in rawQuery.utf8 where byte == 0x26 {
            fieldCount += 1
            guard fieldCount <= maximumFieldCount else {
                return .failure(.tooManyFields)
            }
        }

        let rawFields = rawQuery.split(
            separator: "&",
            omittingEmptySubsequences: false
        )
        var fields: [RawQueryField] = []
        fields.reserveCapacity(rawFields.count)

        for (position, rawSubstring) in rawFields.enumerated() {
            let raw = String(rawSubstring)
            let nameSubstring: Substring
            let value: String?
            if let equals = rawSubstring.firstIndex(of: "=") {
                nameSubstring = rawSubstring[..<equals]
                value = String(rawSubstring[rawSubstring.index(after: equals)...])
            } else {
                nameSubstring = rawSubstring
                value = nil
            }

            let rawName = String(nameSubstring)
            let decodedName: String
            switch percentDecodeASCII(rawName) {
            case let .success(value):
                decodedName = value
            case let .failure(error):
                return .failure(error)
            }

            fields.append(
                RawQueryField(
                    position: position,
                    raw: raw,
                    rawName: rawName,
                    rawValue: value,
                    decodedASCIIName: decodedName
                )
            )
        }

        return .success(TokenizedRawQuery(original: rawQuery, fields: fields))
    }

    /// Strictly decodes `%HH` octets for matching only. A plus sign remains a
    /// literal plus and decoded non-ASCII bytes are rejected.
    public static func percentDecodeASCII(
        _ raw: String
    ) -> Result<String, RawQueryTokenizationFailure> {
        let bytes = Array(raw.utf8)
        guard bytes.allSatisfy({ $0 < 0x80 }) else {
            return .failure(.nonASCIIFieldName)
        }

        var decoded: [UInt8] = []
        decoded.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x25 {
                guard index + 2 < bytes.count,
                      let high = hexValue(bytes[index + 1]),
                      let low = hexValue(bytes[index + 2])
                else {
                    return .failure(.malformedPercentEscape)
                }
                let byte = (high << 4) | low
                guard byte < 0x80 else {
                    return .failure(.nonASCIIFieldName)
                }
                decoded.append(byte)
                index += 3
            } else {
                decoded.append(bytes[index])
                index += 1
            }
        }
        return .success(String(decoding: decoded, as: UTF8.self))
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39:
            byte - 0x30
        case 0x41...0x46:
            byte - 0x41 + 10
        case 0x61...0x66:
            byte - 0x61 + 10
        default:
            nil
        }
    }
}
