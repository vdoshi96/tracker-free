import Foundation

public enum ProtectedLinkReason: String, Sendable, Equatable {
    case signedURL
    case authentication
    case sensitiveMarker
    case sensitivePath
    case tokenFragment
    case redirectWrapper
    case opaqueShortener
    case invitation
    case ambiguousPath
    case rule
}

public enum ProtectedLinkClassification: Sendable, Equatable {
    case allowed
    case protected(ProtectedLinkReason)
}

public enum ProtectedLinkClassifier {
    private static let maximumPathComponentCount = 128
    private static let maximumFragmentFieldCount = 128

    public static func classify(
        _ url: RecognizedURL,
        query: TokenizedRawQuery
    ) -> ProtectedLinkClassification {
        let host = url.canonicalHost
        guard url.rawPath.utf8.count
                <= URLRecognizer.maximumPathUTF8ByteCount,
              let decodedPath = decodePathForClassification(url.rawPath)
        else {
            return .protected(.ambiguousPath)
        }
        let path = decodedPath.path
        let lowerPath = asciiLowercased(path)

        if isKnownRedirectWrapper(host: host, path: path) {
            return .protected(.redirectWrapper)
        }
        if isOpaqueShortener(host: host, path: path) {
            return .protected(.opaqueShortener)
        }
        if isProtectedXPath(host: host, lowerPath: lowerPath) {
            return .protected(.redirectWrapper)
        }
        if lowerPath.hasSuffix(".ics") || lowerPath.hasSuffix(".ics/") {
            return .protected(.invitation)
        }

        let names = Set(query.fields.map {
            asciiLowercased($0.decodedASCIIName)
        })

        if names.contains(where: {
            $0.hasPrefix("x-amz-") || $0.hasPrefix("x-goog-")
        }) {
            return .protected(.signedURL)
        }
        if names.contains("sig")
            || names.contains("signature")
            || names.contains("hmac") {
            return .protected(.signedURL)
        }
        if isRecognizableSignedTuple(names) {
            return .protected(.signedURL)
        }

        if (names.contains("client_id")
            && (
                names.contains("response_type")
                    || names.contains("redirect_uri")
            ))
            || names.contains("code_challenge")
            || names.contains("code_verifier")
            || (names.contains("code") && names.contains("state"))
            || !names.isDisjoint(with: authenticationNames) {
            return .protected(.authentication)
        }

        if !names.isDisjoint(with: sensitiveNames) {
            return .protected(.sensitiveMarker)
        }

        guard let fragmentNames = fragmentFieldNames(url.rawFragment) else {
            return .protected(.ambiguousPath)
        }
        if !fragmentNames.isDisjoint(with: tokenFragmentNames)
            || (
                fragmentNames.contains("code")
                    && fragmentNames.contains("state")
            ) {
            return .protected(.tokenFragment)
        }

        let lowerComponents = Set(
            decodedPath.components
                .filter { !$0.isEmpty }
                .map(asciiLowercased)
        )
        let nonemptyQuery = url.rawQuery.map { !$0.isEmpty } == true
        let tokenLikeFragment = hasTokenLikeFragment(url.rawFragment)
        if !lowerComponents.isDisjoint(with: sensitivePathComponents),
           nonemptyQuery || tokenLikeFragment {
            return .protected(.sensitivePath)
        }

        return .allowed
    }

    private static let authenticationNames: Set<String> = [
        "access_token",
        "id_token",
        "refresh_token",
        "samlrequest",
        "samlresponse",
        "relaystate",
    ]

    private static let sensitiveNames: Set<String> = [
        "token",
        "reset_token",
        "verify_token",
        "invite",
        "invitation",
        "ticket",
        "jwt",
        "auth",
        "session",
        "api_key",
        "key",
    ]

    private static let tokenFragmentNames: Set<String> = [
        "access_token",
        "id_token",
        "refresh_token",
        "token",
        "jwt",
        "samlresponse",
        "signature",
        "sig",
    ]

    private static let sensitivePathComponents: Set<String> = [
        "oauth",
        "authorize",
        "callback",
        "login",
        "signin",
        "magic",
        "reset",
        "password",
        "verify",
        "verification",
        "invite",
        "invitation",
        "accept",
        "activate",
        "unsubscribe",
    ]

    private static func isRecognizableSignedTuple(_ names: Set<String>) -> Bool {
        let awsLegacy: Set<String> = [
            "awsaccesskeyid", "expires", "signature",
        ]
        if awsLegacy.isSubset(of: names) {
            return true
        }

        let cloudFrontCore: Set<String> = ["signature", "key-pair-id"]
        if cloudFrontCore.isSubset(of: names)
            && (names.contains("policy") || names.contains("expires")) {
            return true
        }

        let azureCore: Set<String> = ["sv", "sp", "se", "sr"]
        if azureCore.isSubset(of: names)
            && (names.contains("sig") || names.contains("signature")) {
            return true
        }
        return false
    }

    private static func isKnownRedirectWrapper(host: String, path: String) -> Bool {
        if (host == "l.facebook.com" || host == "lm.facebook.com"),
           path == "/l.php" {
            return true
        }
        if (host == "google.com" || host == "www.google.com"),
           path == "/url" || path == "/url/" {
            return true
        }
        return false
    }

    private static func isOpaqueShortener(host: String, path: String) -> Bool {
        let hosts: Set<String> = [
            "t.co",
            "www.t.co",
            "bit.ly",
            "www.bit.ly",
            "tinyurl.com",
            "www.tinyurl.com",
            "ow.ly",
            "www.ow.ly",
            "buff.ly",
            "www.buff.ly",
            "amzn.to",
            "www.amzn.to",
            "vm.tiktok.com",
            "vt.tiktok.com",
        ]
        if hosts.contains(host) {
            return true
        }
        let tiktokHosts: Set<String> = [
            "tiktok.com", "www.tiktok.com", "m.tiktok.com",
        ]
        return tiktokHosts.contains(host)
            && (path == "/t" || path.hasPrefix("/t/"))
    }

    private static func isProtectedXPath(
        host: String,
        lowerPath: String
    ) -> Bool {
        let xHosts: Set<String> = [
            "x.com",
            "www.x.com",
            "twitter.com",
            "www.twitter.com",
            "mobile.twitter.com",
        ]
        guard xHosts.contains(host) else {
            return false
        }
        if lowerPath == "/i/redirect" || lowerPath.hasPrefix("/i/redirect/") {
            return true
        }
        let first = lowerPath.split(separator: "/").first.map(String.init) ?? ""
        let protectedComponents: Set<String> = [
            "oauth",
            "authorize",
            "login",
            "signin",
            "signup",
            "account",
            "settings",
            "reset",
            "password",
            "email",
        ]
        return protectedComponents.contains(first)
    }

    private static func decodePathForClassification(
        _ path: String
    ) -> (path: String, components: [String])? {
        var componentCount = 1
        for byte in path.utf8 where byte == 0x2F {
            componentCount += 1
            guard componentCount <= maximumPathComponentCount else {
                return nil
            }
        }

        var output: [String] = []
        output.reserveCapacity(componentCount)
        for rawComponent in path.split(
            separator: "/",
            omittingEmptySubsequences: false
        ) {
            switch RawQueryTokenizer.percentDecodeASCII(String(rawComponent)) {
            case let .success(value):
                guard value != ".",
                      value != "..",
                      value.utf8.allSatisfy({
                    $0 >= 0x20
                        && $0 != 0x2F
                        && $0 != 0x5C
                        && $0 != 0x25
                        && $0 != 0x7F
                }) else {
                    return nil
                }
                output.append(value)
            case .failure:
                return nil
            }
        }
        return (output.joined(separator: "/"), output)
    }

    private static func fragmentFieldNames(
        _ fragment: String?
    ) -> Set<String>? {
        guard var fragment, !fragment.isEmpty else {
            return []
        }
        guard fragment.utf8.count
                <= URLRecognizer.maximumFragmentUTF8ByteCount
        else {
            return nil
        }
        if fragment.first == "?" {
            fragment.removeFirst()
        }
        var fieldCount = 1
        for byte in fragment.utf8 where byte == 0x26 {
            fieldCount += 1
            guard fieldCount <= maximumFragmentFieldCount else {
                return nil
            }
        }
        var names = Set<String>()
        for rawField in fragment.split(
            separator: "&",
            omittingEmptySubsequences: false
        ) {
            let name = rawField.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).first.map(String.init) ?? ""
            if case let .success(decoded) =
                RawQueryTokenizer.percentDecodeASCII(name) {
                names.insert(asciiLowercased(decoded))
            }
        }
        return names
    }

    private static func hasTokenLikeFragment(_ fragment: String?) -> Bool {
        guard let fragment, !fragment.isEmpty else {
            return false
        }
        let lower = asciiLowercased(fragment)
        let markers = [
            "access_token=",
            "id_token=",
            "refresh_token=",
            "token=",
            "jwt=",
            "signature=",
            "sig=",
            "samlresponse=",
        ]
        return markers.contains(where: { lower.contains($0) })
    }

    private static func asciiLowercased(_ value: String) -> String {
        String(decoding: value.utf8.map {
            ($0 >= 0x41 && $0 <= 0x5A) ? $0 + 0x20 : $0
        }, as: UTF8.self)
    }
}
