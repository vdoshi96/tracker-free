import XCTest
@testable import TrackerFree

final class URLCleanerTests: XCTestCase {
    private func basicSnapshot() throws -> RuleSetSnapshot {
        try TestRuleFactory.snapshot([
            TestRuleFactory.rule(
                id: "remove.utm_source",
                action: .removeParameter,
                name: "utm_source"
            ),
            TestRuleFactory.rule(
                id: "remove.gclid",
                action: .removeParameter,
                name: "gclid"
            ),
            TestRuleFactory.rule(
                id: "preserve.q",
                action: .preserveParameter,
                name: "q"
            ),
        ])
    }

    func testRawSurgeryChangesOnlyApprovedWholeFields() throws {
        let input = "\t HTTPS://Example.COM:443/a%41"
            + "?keep=%2f+%41&&utm_source=x&empty=&dup=1&dup=2"
            + "#Frag \t\r\n"
        let expected = "\t HTTPS://Example.COM:443/a%41"
            + "?keep=%2f+%41&&empty=&dup=1&dup=2"
            + "#Frag \t\r\n"

        let result = URLCleaner.clean(input, using: try basicSnapshot())

        XCTAssertEqual(result.decision, .cleaned)
        XCTAssertEqual(result.output, expected)
        XCTAssertEqual(result.removedParameters.map(\.name), ["utm_source"])
    }

    func testRemovesEveryDuplicateSpellingAndForm() throws {
        let input = "https://example.com/"
            + "?utm_source&utm_source=&utm_source=x&q=y"
        let result = URLCleaner.clean(input, using: try basicSnapshot())

        XCTAssertEqual(result.output, "https://example.com/?q=y")
        XCTAssertEqual(result.removedParameters.count, 3)
    }

    func testRemovesQuestionMarkOnlyWhenNoStructuralFieldRemains() throws {
        let snapshot = try basicSnapshot()

        XCTAssertEqual(
            URLCleaner.clean(
                "https://example.com/a?utm_source=x#f",
                using: snapshot
            ).output,
            "https://example.com/a#f"
        )
        XCTAssertEqual(
            URLCleaner.clean(
                "https://example.com/a?utm_source=x&#f",
                using: snapshot
            ).output,
            "https://example.com/a?#f"
        )
        XCTAssertEqual(
            URLCleaner.clean(
                "https://example.com/a?&utm_source=x&q=1",
                using: snapshot
            ).output,
            "https://example.com/a?&q=1"
        )
    }

    func testPercentDecodesNamesOnlyAndDoesNotFoldCaseOrPlus() throws {
        let input = "https://example.com/"
            + "?%75tm_source=a+b&UTM_SOURCE=x&utm+source=y"
        let result = URLCleaner.clean(input, using: try basicSnapshot())

        XCTAssertEqual(
            result.output,
            "https://example.com/?UTM_SOURCE=x&utm+source=y"
        )
        XCTAssertEqual(result.removedParameters.count, 1)
    }

    func testNeverRecursivelyCleansNestedEncodedURLValues() throws {
        let input = "https://example.com/content"
            + "?destination=https%3A%2F%2Fother.example%2F"
            + "%3Futm_source%3Dinner&utm_source=outer"
        let result = URLCleaner.clean(input, using: try basicSnapshot())

        XCTAssertEqual(
            result.output,
            "https://example.com/content"
                + "?destination=https%3A%2F%2Fother.example%2F"
                + "%3Futm_source%3Dinner"
        )
    }

    func testNoOpAndUnsupportedInputsNeverProduceOutput() throws {
        let snapshot = try basicSnapshot()
        let cases: [(String, CleanDecision)] = [
            ("https://example.com/", .unchanged),
            ("https://example.com/?", .unchanged),
            ("https://example.com/?q=term", .unchanged),
            ("https://example.com/?utm_source=x;q=term", .unsupported),
            ("not a url", .unsupported),
            ("https://example.com/café?utm_source=x", .unsupported),
        ]

        for (input, expectedDecision) in cases {
            let result = URLCleaner.clean(input, using: snapshot)
            XCTAssertEqual(result.decision, expectedDecision, input)
            XCTAssertNil(result.output, input)
        }
    }

    func testHardGuardsPreserveWholeURLBeforeRules() throws {
        let snapshot = try basicSnapshot()
        let protected = [
            "https://example.com/login?utm_source=x",
            "https://example.com/file?X-Amz-Signature=a&utm_source=x",
            "https://example.com/callback?code=a&state=b&utm_source=x",
            "https://example.com/a?utm_source=x#access_token=secret",
            "https://example.com/a?utm_source=x#code=abc&state=xyz",
            "https://www.google.com/url?utm_source=x&q=destination",
            "https://bit.ly/path?utm_source=x",
            "https://example.com/invite.ics?utm_source=x",
            "https://example.com/a?api_key=value&utm_source=x",
        ]

        for input in protected {
            let result = URLCleaner.clean(input, using: snapshot)
            XCTAssertEqual(result.decision, .protected, input)
            XCTAssertNil(result.output, input)
        }
    }

    func testUserRemovalCannotOverrideHardGuard() throws {
        let userRemoval = TestRuleFactory.rule(
            id: "user.remove.utm_source",
            origin: .user,
            action: .removeParameter,
            name: "utm_source"
        )
        let snapshot = try TestRuleFactory.snapshot([userRemoval])
        let result = URLCleaner.clean(
            "https://example.com/reset?utm_source=x&token=secret",
            using: snapshot
        )

        XCTAssertEqual(result.decision, .protected)
        XCTAssertNil(result.output)
    }

    func testBundledGlobalAndDomainRules() throws {
        let snapshot = try TestRuleFactory.builtInSnapshot()
        let cases: [(input: String, expected: String?)] = [
            (
                "https://example.com/a?q=term&utm_source=x&fbclid=y",
                "https://example.com/a?q=term"
            ),
            (
                "https://example.com/a?utm_unreviewed=x&UTM_SOURCE=y",
                nil
            ),
            (
                "https://x.com/person/status/123?s=20&t=abc&lang=en",
                "https://x.com/person/status/123?lang=en"
            ),
            (
                "https://x.com/home?s=20&t=abc",
                nil
            ),
            (
                "https://www.youtube.com/watch"
                    + "?v=dQw4w9WgXcQ&si=share&t=43",
                "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=43"
            ),
            (
                "https://www.youtube.com/watch?v=short&si=share",
                "https://www.youtube.com/watch?v=short"
            ),
            (
                "https://youtu.be/dQw4w9WgXcQ?si=share",
                "https://youtu.be/dQw4w9WgXcQ"
            ),
            (
                "https://youtu.be/abc?si=share&t=90",
                "https://youtu.be/abc?t=90"
            ),
            (
                "https://www.instagram.com/reel/ABC_123/?igsh=share&q=x",
                "https://www.instagram.com/reel/ABC_123/?q=x"
            ),
            (
                "https://example.com/product?tag=affiliate&utm_medium=email",
                "https://example.com/product?tag=affiliate"
            ),
            (
                "https://example.com/content?mc_cid=a&story=1",
                "https://example.com/content?story=1"
            ),
        ]

        for item in cases {
            let result = URLCleaner.clean(item.input, using: snapshot)
            XCTAssertEqual(result.output, item.expected, item.input)
            XCTAssertEqual(
                result.decision,
                item.expected == nil ? .unchanged : .cleaned,
                item.input
            )
        }

        XCTAssertEqual(
            URLCleaner.clean(
                "https://x.com/i/redirect?utm_source=x",
                using: snapshot
            ).decision,
            .protected
        )
        XCTAssertEqual(
            URLCleaner.clean(
                "https://vm.tiktok.com/abc?ttclid=x",
                using: snapshot
            ).decision,
            .protected
        )
        XCTAssertEqual(
            URLCleaner.clean(
                "https://example.com/unsubscribe?mc_cid=x",
                using: snapshot
            ).decision,
            .protected
        )
    }

    func testDeterministicRawFieldPropertyAndIdempotence() throws {
        let snapshot = try basicSnapshot()
        var generator = DeterministicGenerator(seed: 0xC1EA_F00D)
        let fieldTemplates = [
            "alpha=%2f+%41",
            "beta=",
            "q=search+term",
            "x=a=b",
            "",
            "bare",
            "utm+source=kept",
        ]

        for iteration in 0..<300 {
            let removal = generator.next() & 1 == 0
                ? "utm_source=\(generator.next() % 10_000)"
                : "%75tm_source=\(generator.next() % 10_000)"
            var fields = [removal]
            let extraCount = Int(generator.next() % 8)
            for _ in 0..<extraCount {
                fields.append(
                    fieldTemplates[
                        Int(generator.next() % UInt64(fieldTemplates.count))
                    ]
                )
            }
            deterministicShuffle(&fields, using: &generator)

            let prefix = iteration.isMultiple(of: 3) ? "\t " : ""
            let suffix = iteration.isMultiple(of: 5) ? " \r\n" : ""
            let input = prefix
                + "https://example.com/p?"
                + fields.joined(separator: "&")
                + "#fragment"
                + suffix
            let retained = fields.filter { raw in
                let rawName = raw.split(
                    separator: "=",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                ).first.map(String.init) ?? ""
                return (try? RawQueryTokenizer.percentDecodeASCII(rawName).get())
                    != "utm_source"
            }
            let expectedCore = "https://example.com/p"
                + (
                    retained.isEmpty
                        ? ""
                        : "?" + retained.joined(separator: "&")
                )
                + "#fragment"
            let expected = prefix + expectedCore + suffix

            let first = URLCleaner.clean(input, using: snapshot)
            XCTAssertEqual(first.decision, .cleaned, "iteration \(iteration)")
            XCTAssertEqual(first.output, expected, "iteration \(iteration)")

            let second = URLCleaner.clean(
                try XCTUnwrap(first.output),
                using: snapshot
            )
            XCTAssertEqual(second.decision, .unchanged, "iteration \(iteration)")
            XCTAssertNil(second.output, "iteration \(iteration)")
        }
    }

    private struct DeterministicGenerator {
        var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return state
        }
    }

    private func deterministicShuffle(
        _ values: inout [String],
        using generator: inout DeterministicGenerator
    ) {
        guard values.count > 1 else {
            return
        }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            let other = Int(generator.next() % UInt64(index + 1))
            values.swapAt(index, other)
        }
    }
}
