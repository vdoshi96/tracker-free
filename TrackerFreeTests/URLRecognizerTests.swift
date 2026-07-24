import XCTest
@testable import TrackerFree

final class URLRecognizerTests: XCTestCase {
    func testRecognizesStrictASCIIHTTPURLsAndPreservesRawParts() throws {
        let cases: [(input: String, host: String, path: String, query: String?)] = [
            ("https://example.com", "example.com", "", nil),
            ("HTTP://Example.COM/a", "example.com", "/a", nil),
            (
                "HTTPS://Example.COM:443/a%2Fb?x=%2f+%41#Frag",
                "example.com",
                "/a%2Fb",
                "x=%2f+%41"
            ),
            (
                "\t https://xn--bcher-kva.example/path? \t\r\n",
                "xn--bcher-kva.example",
                "/path",
                ""
            ),
            ("https://example.com/?&q=", "example.com", "/", "&q="),
        ]

        for item in cases {
            let recognized = try XCTUnwrap(
                try? URLRecognizer.recognize(item.input).get(),
                "Expected recognition for \(item.input)"
            )
            XCTAssertEqual(recognized.canonicalHost, item.host)
            XCTAssertEqual(recognized.rawPath, item.path)
            XCTAssertEqual(recognized.rawQuery, item.query)
            XCTAssertEqual(recognized.original, item.input)
        }
    }

    func testRejectsUnsafeOrAmbiguousURLForms() {
        let invalid = [
            "",
            "   ",
            "//example.com/a",
            "file:///tmp/value",
            "mailto:user@example.com",
            "https://",
            "https://user:pass@example.com/a",
            "https://example.com/a b",
            "https://example.com/mañana",
            "https://éxample.com/a",
            "https://example.com\\a",
            "https://example.com/%",
            "https://example.com/%0",
            "https://example.com/%GG",
            "https://example.com/?next=http://other.example/a",
            "https://example.com/?next=HTTPS://other.example/a",
            "http://127.0.0.1/a",
            "http://127.1/a",
            "http://0x7f.0.0.1/a",
            "http://[::1]/a",
            "http://localhost/a",
            "http://service.local/a",
            "http://service.internal/a",
            "http://singlelabel/a",
            "http://example.com:/a",
            "http://example.com:0/a",
            "http://example.com:65536/a",
            "http://example..com/a",
            "http://example.com./a",
            "\nhttps://example.com/a",
            "https://example.com/a\n\n",
            "https://example.com/a\r",
            "https://example.com/a\u{00A0}",
            "https://example.com/a\tb",
        ]

        for value in invalid {
            guard case .failure = URLRecognizer.recognize(value) else {
                XCTFail("Expected rejection for \(String(reflecting: value))")
                continue
            }
        }
    }

    func testEnforcesUTF8ByteLimit() {
        let oversized = "https://example.com/" + String(
            repeating: "a",
            count: URLRecognizer.maximumUTF8ByteCount
        )
        XCTAssertEqual(
            URLRecognizer.recognize(oversized),
            .failure(.inputTooLarge)
        )
    }

    func testRawTokenizerRetainsStructuralAndSpellingDetails() throws {
        let tokenized = try RawQueryTokenizer.tokenize(
            "%75tm_source=a+b&&x=a=b&empty=&bare"
        ).get()

        XCTAssertEqual(
            tokenized.fields.map(\.raw),
            ["%75tm_source=a+b", "", "x=a=b", "empty=", "bare"]
        )
        XCTAssertEqual(
            tokenized.fields.map(\.decodedASCIIName),
            ["utm_source", "", "x", "empty", "bare"]
        )
        XCTAssertEqual(tokenized.fields[0].rawValue, "a+b")
        XCTAssertEqual(tokenized.fields[2].rawValue, "a=b")
        XCTAssertEqual(tokenized.fields[3].rawValue, "")
        XCTAssertNil(tokenized.fields[4].rawValue)
    }

    func testRawTokenizerDoesNotTreatPlusAsSpace() throws {
        let field = try XCTUnwrap(
            try RawQueryTokenizer.tokenize("utm+source=x").get().fields.first
        )
        XCTAssertEqual(field.decodedASCIIName, "utm+source")
    }

    func testRawTokenizerFailsOpenForAmbiguousOrNonASCIINames() {
        XCTAssertEqual(
            RawQueryTokenizer.tokenize("a=1;b=2"),
            .failure(.ambiguousSemicolon)
        )
        XCTAssertEqual(
            RawQueryTokenizer.tokenize("%C3%A9=value"),
            .failure(.nonASCIIFieldName)
        )
        XCTAssertEqual(
            RawQueryTokenizer.tokenize("%Q0=value"),
            .failure(.malformedPercentEscape)
        )
    }
}
