import Testing
@testable import TrackerFree

@Suite("Pure URL engine")
struct PureEngineSwiftTestingTests {
    @Test(
        "Required URL fixtures 1 through 65",
        arguments: makeURLAcceptanceFixtures()
    )
    func requiredURLFixture(_ fixture: URLAcceptanceFixture) throws {
        let snapshot = try TestRuleFactory.builtInSnapshot()

        for testCase in fixture.cases {
            let result = URLCleaner.clean(testCase.input, using: snapshot)
            switch testCase.expectation {
            case let .cleaned(expected):
                #expect(
                    result.decision == .cleaned,
                    "fixture \(fixture.id), \(testCase.label)"
                )
                #expect(
                    result.output == expected,
                    "fixture \(fixture.id), \(testCase.label)"
                )
                #expect(expected.utf8.count <= testCase.input.utf8.count)

                let second = URLCleaner.clean(expected, using: snapshot)
                #expect(second.decision == .unchanged)
                #expect(second.output == nil)

            case let .unchanged(expectedDecision):
                #expect(
                    result.decision == expectedDecision,
                    "fixture \(fixture.id), \(testCase.label)"
                )
                #expect(result.output == nil)
            }
        }
    }

    @Test(
        "Recognition and rejection are parameterized",
        arguments: RecognitionFixture.all
    )
    func recognitionAndRejection(_ fixture: RecognitionFixture) {
        let result = URLRecognizer.recognize(fixture.input)
        switch (fixture.expectedHost, result) {
        case let (.some(expectedHost), .success(recognized)):
            #expect(recognized.canonicalHost == expectedHost)
            #expect(recognized.original == fixture.input)
        case (.none, .failure):
            break
        default:
            Issue.record("Unexpected recognition result for \(fixture.label)")
        }
    }

    @Test(
        "Rule precedence is deterministic",
        arguments: PrecedenceScenario.allCases
    )
    func rulePrecedence(_ scenario: PrecedenceScenario) throws {
        let builtInRemoval = TestRuleFactory.rule(
            id: "builtin.remove.x",
            action: .removeParameter,
            name: "x"
        )
        let builtInPreserve = TestRuleFactory.rule(
            id: "builtin.preserve.x",
            action: .preserveParameter,
            name: "x"
        )
        let userPreserve = TestRuleFactory.rule(
            id: "user.preserve.x",
            origin: .user,
            action: .preserveParameter,
            name: "x"
        )
        let userRemoval = TestRuleFactory.rule(
            id: "user.remove.x",
            origin: .user,
            action: .removeParameter,
            name: "x"
        )

        let rules: [CleaningRule]
        let expectedAction: RuleAction
        switch scenario {
        case .builtInTiePreserves:
            rules = [builtInRemoval, builtInPreserve]
            expectedAction = .preserveParameter
        case .userPreserveWins:
            rules = [builtInRemoval, userPreserve]
            expectedAction = .preserveParameter
        case .acknowledgedUserRemovalWins:
            rules = [builtInPreserve, userRemoval]
            expectedAction = .removeParameter
        }

        for orderedRules in [rules, Array(rules.reversed())] {
            let snapshot = try TestRuleFactory.snapshot(orderedRules)
            let url = try URLRecognizer.recognize(
                "https://example.test/?x=1"
            ).get()
            let query = try RawQueryTokenizer.tokenize("x=1").get()
            let field = try #require(query.fields.first)
            let decision = RuleEngine(snapshot: snapshot).decision(
                for: field,
                in: url,
                query: query
            )

            switch decision {
            case let .preserve(match):
                #expect(expectedAction == .preserveParameter)
                #expect(match?.action == .preserveParameter)
            case let .remove(match):
                #expect(expectedAction == .removeParameter)
                #expect(match.action == .removeParameter)
            case .conflict:
                Issue.record("Unexpected rule conflict for \(scenario)")
            }
        }
    }

    @Test("Deterministic encoding property and idempotence")
    func deterministicEncodingAndIdempotence() throws {
        let snapshot = try TestRuleFactory.snapshot([
            TestRuleFactory.rule(
                id: "remove.utm_source",
                action: .removeParameter,
                name: "utm_source"
            ),
        ])
        var generator = SwiftTestingGenerator(seed: 0xC1EA_F00D)
        let retainedTemplates = [
            "alpha=%2f+%41",
            "beta=",
            "q=search+term",
            "x=a=b",
            "",
            "bare",
            "utm+source=kept",
        ]

        for iteration in 0..<300 {
            var fields = [
                generator.next().isMultiple(of: 2)
                    ? "utm_source=\(generator.next() % 10_000)"
                    : "%75tm_source=\(generator.next() % 10_000)",
            ]
            for _ in 0..<Int(generator.next() % 8) {
                fields.append(
                    retainedTemplates[
                        Int(generator.next() % UInt64(retainedTemplates.count))
                    ]
                )
            }
            generator.shuffle(&fields)

            let input =
                (iteration.isMultiple(of: 3) ? "\t " : "")
                + "https://example.test/p?"
                + fields.joined(separator: "&")
                + "#fragment"
                + (iteration.isMultiple(of: 5) ? " \r\n" : "")
            let first = URLCleaner.clean(input, using: snapshot)

            #expect(first.decision == .cleaned)
            let output = try #require(first.output)
            #expect(output.utf8.count < input.utf8.count)
            let second = URLCleaner.clean(output, using: snapshot)
            #expect(second.decision == .unchanged)
            #expect(second.output == nil)
        }
    }
}

struct RecognitionFixture: Sendable {
    let label: String
    let input: String
    let expectedHost: String?

    static let all: [RecognitionFixture] = [
        RecognitionFixture(
            label: "ASCII HTTPS",
            input: "https://Example.TEST/p?utm_source=x",
            expectedHost: "example.test"
        ),
        RecognitionFixture(
            label: "Punycode",
            input: "https://xn--bcher-kva.example/p?utm_source=x",
            expectedHost: "xn--bcher-kva.example"
        ),
        RecognitionFixture(
            label: "suffix attack is a distinct host",
            input: "https://x.com.evil/p?utm_source=x",
            expectedHost: "x.com.evil"
        ),
        RecognitionFixture(
            label: "literal Unicode",
            input: "https://例え.テスト/道?utm_source=x",
            expectedHost: nil
        ),
        RecognitionFixture(
            label: "userinfo",
            input: "https://u:p@example.test/p?utm_source=x",
            expectedHost: nil
        ),
        RecognitionFixture(
            label: "private IP",
            input: "https://192.168.1.1/p?utm_source=x",
            expectedHost: nil
        ),
        RecognitionFixture(
            label: "embedded prose",
            input: "See https://example.test/p?utm_source=x",
            expectedHost: nil
        ),
    ]
}

enum PrecedenceScenario: String, CaseIterable, Sendable {
    case builtInTiePreserves
    case userPreserveWins
    case acknowledgedUserRemovalWins
}

private struct SwiftTestingGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }

    mutating func shuffle(_ values: inout [String]) {
        guard values.count > 1 else {
            return
        }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            let other = Int(next() % UInt64(index + 1))
            values.swapAt(index, other)
        }
    }
}
