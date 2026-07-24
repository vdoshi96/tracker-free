import Darwin
import Foundation
import XCTest
@testable import TrackerFree

/// Executable acceptance criteria from the v1 regression fixture matrix.
///
/// Every pasteboard used here is the in-memory fake. This suite deliberately
/// does not import AppKit and cannot reach the system pasteboard.
final class AcceptanceTests: XCTestCase {
    @MainActor
    func testRegressionFixtures1Through65UseExactByteOutcomesAndNoOpWrites() throws {
        let snapshot = try TestRuleFactory.builtInSnapshot()
        let fixtures = makeURLAcceptanceFixtures()

        XCTAssertEqual(fixtures.map(\.id), Array(1...65))

        for fixture in fixtures {
            for testCase in fixture.cases {
                let context = "fixture \(fixture.id), \(testCase.label)"
                let directResult = URLCleaner.clean(testCase.input, using: snapshot)

                let originalItem = FakePasteboardItem(
                    content: PasteboardContent(plainText: testCase.input)
                )
                let pasteboard = FakePasteboardClient()
                let coordinator = makeAcceptanceCoordinator(
                    pasteboard: pasteboard,
                    snapshot: snapshot
                )
                pasteboard.replaceExternally(with: [originalItem])
                coordinator.pollOnce()

                switch testCase.expectation {
                case let .cleaned(expected):
                    XCTAssertEqual(directResult.decision, .cleaned, context)
                    XCTAssertEqual(directResult.output, expected, context)
                    XCTAssertEqual(pasteboard.committedWriteCount, 1, context)
                    XCTAssertEqual(
                        pasteboard.items,
                        [
                            FakePasteboardItem(
                                content: PasteboardContent(plainText: expected),
                                includesTrackerFreeMarker: true
                            ),
                        ],
                        context
                    )

                case let .unchanged(expectedDecision):
                    XCTAssertEqual(
                        directResult.decision,
                        expectedDecision,
                        context
                    )
                    XCTAssertNil(directResult.output, context)
                    XCTAssertEqual(pasteboard.committedWriteCount, 0, context)
                    XCTAssertEqual(
                        pasteboard.items,
                        [originalItem],
                        "\(context): an unchanged fixture must remain byte-identical"
                    )
                }
            }
        }
    }

    @MainActor
    func testRegressionFixtures66Through74UseOnlySyntheticPasteboards() throws {
        let snapshot = try TestRuleFactory.builtInSnapshot()
        let fixtures = makePasteboardAcceptanceFixtures()

        XCTAssertEqual(fixtures.map(\.id), Array(66...74))

        for fixture in fixtures {
            for variant in fixture.variants {
                let context = "fixture \(fixture.id), \(variant.label)"
                let pasteboard = FakePasteboardClient()
                let coordinator = makeAcceptanceCoordinator(
                    pasteboard: pasteboard,
                    snapshot: snapshot
                )
                pasteboard.replaceExternally(with: variant.items)
                variant.failureInjection?(pasteboard)
                let originalItems = pasteboard.items

                coordinator.pollOnce()

                if let expectedContent = variant.expectedCleanedContent {
                    XCTAssertEqual(pasteboard.committedWriteCount, 1, context)
                    XCTAssertEqual(
                        pasteboard.items,
                        [
                            FakePasteboardItem(
                                content: expectedContent,
                                includesTrackerFreeMarker: true
                            ),
                        ],
                        context
                    )
                } else {
                    XCTAssertEqual(pasteboard.committedWriteCount, 0, context)
                    XCTAssertEqual(
                        pasteboard.items,
                        originalItems,
                        "\(context): rejection must remain byte-identical"
                    )
                }
            }
        }
    }

    @MainActor
    func testTenThousandEventCoordinatorStressHasNoSustainedFiveMiBGrowth() throws {
        let snapshot = try TestRuleFactory.builtInSnapshot()
        let pasteboard = FakePasteboardClient()
        let clock = AcceptanceStressClock()
        let coordinator = makeAcceptanceCoordinator(
            pasteboard: pasteboard,
            snapshot: snapshot,
            uptime: { clock.uptime }
        )

        runSyntheticEvents(
            count: 1_000,
            startingAt: 0,
            pasteboard: pasteboard,
            coordinator: coordinator,
            clock: clock
        )
        _ = malloc_zone_pressure_relief(nil, 0)
        let baselineBytes = try residentMemoryBytes()

        runSyntheticEvents(
            count: 10_000,
            startingAt: 1_000,
            pasteboard: pasteboard,
            coordinator: coordinator,
            clock: clock
        )
        _ = malloc_zone_pressure_relief(nil, 0)
        let finalBytes = try residentMemoryBytes()
        let signedGrowth = Int64(finalBytes) - Int64(baselineBytes)
        let positiveGrowth = max(0, signedGrowth)
        let maximumGrowth = Int64(5 * 1_024 * 1_024)

        XCTAssertEqual(pasteboard.committedWriteCount, 11_000)
        XCTAssertLessThan(
            positiveGrowth,
            maximumGrowth,
            "10,000-event post-baseline growth was \(positiveGrowth) bytes"
        )
        print(
            "ACCEPTANCE_MEMORY baseline=\(baselineBytes) final=\(finalBytes) "
                + "growth=\(signedGrowth) bytes events=10000"
        )
    }

    func testSixtyFourKiBPureTransformMedianIsUnderTenMilliseconds() throws {
        if acceptanceIsDebugBuild() {
            throw XCTSkip(
                "The 10 ms shipping-performance criterion is measured in Release."
            )
        }

        let snapshot = try TestRuleFactory.builtInSnapshot()
        let largeValuePrefix = "https://e.test/p?q="
        let largeValueSuffix = "&utm_source=x"
        let largeValue = paddedASCIIURL(
            prefix: largeValuePrefix,
            suffix: largeValueSuffix,
            filler: "a"
        )
        let manyFields = paddedASCIIURL(
            prefix: "https://e.test/p?",
            suffix: "utm_source=x",
            filler: "&"
        )
        let hugeFragment = paddedASCIIURL(
            prefix: "https://e.test/p?utm_source=x#",
            suffix: "",
            filler: "&"
        )
        let hugePath = paddedASCIIURL(
            prefix: "https://e.test/",
            suffix: "?utm_source=x",
            filler: "a/"
        )

        let cases: [(String, String, CleanDecision)] = [
            ("large query value", largeValue, .cleaned),
            ("many query fields", manyFields, .unsupported),
            ("many fragment fields", hugeFragment, .unsupported),
            ("many path components", hugePath, .unsupported),
        ]

        let clock = ContinuousClock()
        for (label, input, expectedDecision) in cases {
            XCTAssertEqual(input.utf8.count, 64 * 1_024, label)
            for _ in 0..<3 {
                XCTAssertEqual(
                    URLCleaner.clean(input, using: snapshot).decision,
                    expectedDecision,
                    label
                )
            }

            var elapsedNanoseconds: [Double] = []
            elapsedNanoseconds.reserveCapacity(21)
            for _ in 0..<21 {
                let start = clock.now
                let result = URLCleaner.clean(input, using: snapshot)
                let elapsed = start.duration(to: clock.now)
                XCTAssertEqual(result.decision, expectedDecision, label)
                if expectedDecision == .cleaned {
                    XCTAssertLessThan(
                        try XCTUnwrap(result.output).utf8.count,
                        input.utf8.count,
                        label
                    )
                } else {
                    XCTAssertNil(result.output, label)
                }
                elapsedNanoseconds.append(nanoseconds(elapsed))
            }

            let sorted = elapsedNanoseconds.sorted()
            let median = sorted[sorted.count / 2]
            XCTAssertLessThan(
                median,
                10_000_000,
                "\(label) median was \(median / 1_000_000) ms"
            )
            print(
                "ACCEPTANCE_TRANSFORM label=\(label) bytes=\(input.utf8.count) "
                    + "median_ms=\(median / 1_000_000) samples=\(sorted.count)"
            )
        }

        let maximumUserRuleShape = (0..<RuleSetSnapshot.maximumUserRuleCount).map {
            TestRuleFactory.rule(
                id: "builtin.performance.\($0)",
                action: .removeParameter,
                name: "candidate_\($0)",
                caseSensitivity: .asciiCaseInsensitive
            )
        }
        let maximumRuleSnapshot = try TestRuleFactory.snapshot(
            maximumUserRuleShape
        )
        let longFieldName = paddedASCIIURL(
            prefix: "https://e.test/p?",
            suffix: "=x",
            filler: "A"
        )
        for _ in 0..<3 {
            XCTAssertEqual(
                URLCleaner.clean(
                    longFieldName,
                    using: maximumRuleSnapshot
                ).decision,
                .unchanged
            )
        }
        var maximumRuleElapsed: [Double] = []
        maximumRuleElapsed.reserveCapacity(21)
        for _ in 0..<21 {
            let start = clock.now
            let result = URLCleaner.clean(
                longFieldName,
                using: maximumRuleSnapshot
            )
            maximumRuleElapsed.append(
                nanoseconds(start.duration(to: clock.now))
            )
            XCTAssertEqual(result.decision, .unchanged)
        }
        let maximumRuleMedian = maximumRuleElapsed.sorted()[
            maximumRuleElapsed.count / 2
        ]
        XCTAssertLessThan(
            maximumRuleMedian,
            10_000_000,
            "64 KiB name with 512 rules median was "
                + "\(maximumRuleMedian / 1_000_000) ms"
        )
        print(
            "ACCEPTANCE_TRANSFORM label=long-name-512-rules "
                + "bytes=\(longFieldName.utf8.count) "
                + "median_ms=\(maximumRuleMedian / 1_000_000) "
                + "samples=\(maximumRuleElapsed.count)"
        )

        let oversized = String(repeating: "a", count: 8 * 1_024 * 1_024)
        let oversizedStart = clock.now
        let oversizedResult = URLCleaner.clean(oversized, using: snapshot)
        let oversizedNanoseconds = nanoseconds(
            oversizedStart.duration(to: clock.now)
        )
        XCTAssertEqual(oversizedResult.decision, .unsupported)
        XCTAssertLessThan(
            oversizedNanoseconds,
            10_000_000,
            "8 MiB caller input rejection took "
                + "\(oversizedNanoseconds / 1_000_000) ms"
        )
    }
}

private func paddedASCIIURL(
    prefix: String,
    suffix: String,
    filler: String
) -> String {
    let target = URLRecognizer.maximumUTF8ByteCount
    let available = target - prefix.utf8.count - suffix.utf8.count
    precondition(available >= 0)
    precondition(!filler.isEmpty && filler.utf8.allSatisfy { $0 < 0x80 })

    let fillerBytes = Array(filler.utf8)
    var bytes = Array(prefix.utf8)
    bytes.reserveCapacity(target)
    for index in 0..<available {
        bytes.append(fillerBytes[index % fillerBytes.count])
    }
    bytes.append(contentsOf: suffix.utf8)
    return String(decoding: bytes, as: UTF8.self)
}

enum URLAcceptanceExpectation: Sendable {
    case cleaned(String)
    case unchanged(CleanDecision)
}

struct URLAcceptanceCase: Sendable {
    let label: String
    let input: String
    let expectation: URLAcceptanceExpectation

    init(
        _ input: String,
        _ expectation: URLAcceptanceExpectation,
        label: String = "primary"
    ) {
        self.label = label
        self.input = input
        self.expectation = expectation
    }
}

struct URLAcceptanceFixture: Sendable {
    let id: Int
    let cases: [URLAcceptanceCase]

    init(_ id: Int, _ cases: URLAcceptanceCase...) {
        self.id = id
        self.cases = cases
    }
}

func makeURLAcceptanceFixtures() -> [URLAcceptanceFixture] {
    let oversized = "https://e.test/p?utm_source=x&q="
        + String(repeating: "a", count: URLRecognizer.maximumUTF8ByteCount)

    return [
        URLAcceptanceFixture(
            1,
            URLAcceptanceCase(
                "https://e.test/p?utm_source=x&a=1#frag",
                .cleaned("https://e.test/p?a=1#frag")
            )
        ),
        URLAcceptanceFixture(
            2,
            URLAcceptanceCase(
                "https://e.test/p?a=1&utm_source=x&b=2",
                .cleaned("https://e.test/p?a=1&b=2")
            )
        ),
        URLAcceptanceFixture(
            3,
            URLAcceptanceCase(
                "https://e.test/p?a=1&utm_source=x&a=2",
                .cleaned("https://e.test/p?a=1&a=2")
            )
        ),
        URLAcceptanceFixture(
            4,
            URLAcceptanceCase(
                "https://e.test/p?id=1&id=2&fbclid=x",
                .cleaned("https://e.test/p?id=1&id=2")
            )
        ),
        URLAcceptanceFixture(
            5,
            URLAcceptanceCase(
                "https://e.test/p?utm_source=&q=",
                .cleaned("https://e.test/p?q=")
            )
        ),
        URLAcceptanceFixture(
            6,
            URLAcceptanceCase(
                "https://e.test/p?utm_source&q=x",
                .cleaned("https://e.test/p?q=x")
            )
        ),
        URLAcceptanceFixture(
            7,
            URLAcceptanceCase(
                "https://e.test/p?q=a+b&x=%2B&utm_source=x",
                .cleaned("https://e.test/p?q=a+b&x=%2B")
            )
        ),
        URLAcceptanceFixture(
            8,
            URLAcceptanceCase(
                "https://e.test/p?ut%6D_source=x&a=%2f&b=%41",
                .cleaned("https://e.test/p?a=%2f&b=%41")
            )
        ),
        URLAcceptanceFixture(
            9,
            URLAcceptanceCase(
                "https://e.test/p?UTM_source=x",
                .unchanged(.unchanged)
            )
        ),
        URLAcceptanceFixture(
            10,
            URLAcceptanceCase(
                "https://e.test/p?utm_custom=x",
                .unchanged(.unchanged)
            )
        ),
        URLAcceptanceFixture(
            11,
            URLAcceptanceCase(
                "https://e.test/p?utm_source=x&&q=",
                .cleaned("https://e.test/p?&q=")
            )
        ),
        URLAcceptanceFixture(
            12,
            URLAcceptanceCase(
                "https://e.test/p?utm_source=x#section%2Fone",
                .cleaned("https://e.test/p#section%2Fone")
            )
        ),
        URLAcceptanceFixture(
            13,
            URLAcceptanceCase(
                "https://e.test/p?a=%G1&utm_source=x",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            14,
            URLAcceptanceCase(
                "https://e.test/p?a=1;b=2&utm_source=x",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            15,
            URLAcceptanceCase(
                "https://e.test/p#a?utm_source=x",
                .unchanged(.unchanged)
            )
        ),
        URLAcceptanceFixture(
            16,
            URLAcceptanceCase(
                "https://e.test/p?next=https%3A%2F%2Fx.test%2F%3Fa%3D1&utm_source=x",
                .cleaned(
                    "https://e.test/p?next=https%3A%2F%2Fx.test%2F%3Fa%3D1"
                )
            )
        ),
        URLAcceptanceFixture(
            17,
            URLAcceptanceCase(
                "https://e.test/p?q=tracker-free",
                .unchanged(.unchanged)
            )
        ),
        URLAcceptanceFixture(
            18,
            URLAcceptanceCase(
                "https://e.test/p?utm_source=x&fbclid=y",
                .cleaned("https://e.test/p")
            )
        ),
        URLAcceptanceFixture(
            19,
            URLAcceptanceCase(
                "https://x.com/user/status/123?s=20&t=abc",
                .cleaned("https://x.com/user/status/123")
            )
        ),
        URLAcceptanceFixture(
            20,
            URLAcceptanceCase(
                "https://x.com/user/status/notdigits?s=20&t=abc",
                .unchanged(.unchanged)
            )
        ),
        URLAcceptanceFixture(
            21,
            URLAcceptanceCase(
                "https://x.com.evil/user/status/123?s=20&t=abc",
                .unchanged(.unchanged)
            )
        ),
        URLAcceptanceFixture(
            22,
            URLAcceptanceCase(
                "https://twitter.com/i/redirect?url=https%3A%2F%2Fe.test&t=1&sig=FAKE",
                .unchanged(.protected)
            ),
            URLAcceptanceCase(
                "https://twitter.com/i/%72edirect?url=https%3A%2F%2Fe.test&utm_source=x",
                .unchanged(.protected),
                label: "percent-encoded redirect path"
            )
        ),
        URLAcceptanceFixture(
            23,
            URLAcceptanceCase(
                "https://youtu.be/abc?si=tok&t=90",
                .cleaned("https://youtu.be/abc?t=90")
            )
        ),
        URLAcceptanceFixture(
            24,
            URLAcceptanceCase(
                "https://www.youtube.com/watch?v=abc&list=PL1&index=2&t=90&si=x",
                .cleaned(
                    "https://www.youtube.com/watch?v=abc&list=PL1&index=2&t=90"
                )
            )
        ),
        URLAcceptanceFixture(
            25,
            URLAcceptanceCase(
                "https://www.youtube.com/results?search_query=swift&si=x",
                .unchanged(.unchanged)
            )
        ),
        URLAcceptanceFixture(
            26,
            URLAcceptanceCase(
                "https://www.instagram.com/reel/ABC/?igsh=FAKE",
                .cleaned("https://www.instagram.com/reel/ABC/")
            )
        ),
        URLAcceptanceFixture(
            27,
            URLAcceptanceCase(
                "https://www.instagram.com/accounts/login/?igsh=FAKE",
                .unchanged(.protected)
            )
        ),
        URLAcceptanceFixture(
            28,
            URLAcceptanceCase(
                "https://www.tiktok.com/@u/video/123?ttclid=FAKE",
                .cleaned("https://www.tiktok.com/@u/video/123")
            )
        ),
        URLAcceptanceFixture(
            29,
            URLAcceptanceCase(
                "https://vm.tiktok.com/FAKE/?ttclid=x",
                .unchanged(.protected)
            ),
            URLAcceptanceCase(
                "https://www.tiktok.com/%74/FAKE?ttclid=x",
                .unchanged(.protected),
                label: "percent-encoded shortener path"
            )
        ),
        URLAcceptanceFixture(
            30,
            URLAcceptanceCase(
                "https://www.reddit.com/r/swift/comments/abc/post/?context=3&sort=new&utm_source=share",
                .cleaned(
                    "https://www.reddit.com/r/swift/comments/abc/post/?context=3&sort=new"
                )
            )
        ),
        URLAcceptanceFixture(
            31,
            URLAcceptanceCase(
                "https://www.amazon.com/dp/B00?tag=a-20&linkCode=ogi&th=1&psc=1",
                .unchanged(.unchanged)
            )
        ),
        URLAcceptanceFixture(
            32,
            URLAcceptanceCase(
                "https://e.test/article?mc_cid=C&mc_eid=E&q=1",
                .cleaned("https://e.test/article?q=1")
            )
        ),
        URLAcceptanceFixture(
            33,
            URLAcceptanceCase(
                "https://e.test/unsubscribe?mc_cid=C&mc_eid=E&token=FAKE",
                .unchanged(.protected)
            )
        ),
        URLAcceptanceFixture(
            34,
            URLAcceptanceCase(
                "https://www.google.com/maps/dir/?api=1&origin=A&destination=B&utm_source=x",
                .cleaned(
                    "https://www.google.com/maps/dir/?api=1&origin=A&destination=B"
                )
            )
        ),
        URLAcceptanceFixture(
            35,
            URLAcceptanceCase(
                "https://e.test/search?q=swift+url&page=2&utm_campaign=x",
                .cleaned("https://e.test/search?q=swift+url&page=2")
            )
        ),
        URLAcceptanceFixture(
            36,
            URLAcceptanceCase(
                "https://e.test/products/1?variant=blue&sort=price&page=2&utm_medium=email",
                .cleaned(
                    "https://e.test/products/1?variant=blue&sort=price&page=2"
                )
            )
        ),
        URLAcceptanceFixture(
            37,
            URLAcceptanceCase(
                "https://calendar.e.test/invite?token=FAKE&utm_source=x",
                .unchanged(.protected)
            )
        ),
        URLAcceptanceFixture(
            38,
            URLAcceptanceCase(
                "https://calendar.e.test/event.ics?utm_source=x",
                .unchanged(.protected)
            ),
            URLAcceptanceCase(
                "https://calendar.e.test/event%2Eics?utm_source=x",
                .unchanged(.protected),
                label: "percent-encoded .ics suffix"
            )
        ),
        URLAcceptanceFixture(
            39,
            URLAcceptanceCase(
                "https://bucket.s3.amazonaws.com/o?X-Amz-Signature=FAKE&utm_source=x",
                .unchanged(.protected)
            )
        ),
        URLAcceptanceFixture(
            40,
            URLAcceptanceCase(
                "https://storage.googleapis.com/o?X-Goog-Signature=FAKE&utm_source=x",
                .unchanged(.protected)
            )
        ),
        URLAcceptanceFixture(
            41,
            URLAcceptanceCase(
                "https://cdn.e.test/o?Policy=FAKE&Signature=FAKE&Key-Pair-Id=K",
                .unchanged(.protected)
            )
        ),
        URLAcceptanceFixture(
            42,
            URLAcceptanceCase(
                "https://blob.core.windows.net/o?sv=1&sp=r&sig=FAKE&utm_source=x",
                .unchanged(.protected)
            )
        ),
        URLAcceptanceFixture(
            43,
            URLAcceptanceCase(
                "https://e.test/reset?token=FAKE&utm_source=email",
                .unchanged(.protected)
            )
        ),
        URLAcceptanceFixture(
            44,
            URLAcceptanceCase(
                "https://e.test/oauth/callback?code=FAKE&state=FAKE&utm_source=x",
                .unchanged(.protected)
            )
        ),
        URLAcceptanceFixture(
            45,
            URLAcceptanceCase(
                "https://auth.e.test/authorize?client_id=C&response_type=code&redirect_uri=https%3A%2F%2Fe.test&state=S&utm_source=x",
                .unchanged(.protected)
            )
        ),
        URLAcceptanceFixture(
            46,
            URLAcceptanceCase(
                "https://e.test/callback?utm_source=x#access_token=FAKE",
                .unchanged(.protected)
            )
        ),
        URLAcceptanceFixture(
            47,
            URLAcceptanceCase(
                "https://l.facebook.com/l.php?u=https%3A%2F%2Fe.test&h=FAKE&fbclid=x",
                .unchanged(.protected)
            ),
            URLAcceptanceCase(
                "https://l.facebook.com/l%2Ephp?u=https%3A%2F%2Fe.test&fbclid=x",
                .unchanged(.protected),
                label: "percent-encoded Facebook wrapper path"
            )
        ),
        URLAcceptanceFixture(
            48,
            URLAcceptanceCase(
                "https://www.google.com/url?q=https%3A%2F%2Fe.test&utm_source=x",
                .unchanged(.protected)
            ),
            URLAcceptanceCase(
                "https://www.google.com/u%72l?q=https%3A%2F%2Fe.test&utm_source=x",
                .unchanged(.protected),
                label: "percent-encoded Google wrapper path"
            ),
            URLAcceptanceCase(
                "https://www.google.com/a/../url?q=https%3A%2F%2Fe.test&utm_source=x",
                .unchanged(.protected),
                label: "dot-segment wrapper path"
            ),
            URLAcceptanceCase(
                "https://www.google.com/u%2572l?q=https%3A%2F%2Fe.test&utm_source=x",
                .unchanged(.protected),
                label: "residual-percent wrapper path"
            ),
            URLAcceptanceCase(
                "https://www.google.com/%01url?q=https%3A%2F%2Fe.test&utm_source=x",
                .unchanged(.protected),
                label: "control-byte wrapper path"
            )
        ),
        URLAcceptanceFixture(
            49,
            URLAcceptanceCase(
                "https://bit.ly/FAKE?utm_source=x",
                .unchanged(.protected)
            )
        ),
        URLAcceptanceFixture(
            50,
            URLAcceptanceCase(
                "https://u:p@e.test/p?utm_source=x",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            51,
            URLAcceptanceCase(
                "file:///tmp/a?utm_source=x",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            52,
            URLAcceptanceCase(
                "mailto:a@example.test?utm_source=x",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            53,
            URLAcceptanceCase(
                "//e.test/p?utm_source=x",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            54,
            URLAcceptanceCase(
                "http://localhost:3000/?utm_source=x",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            55,
            URLAcceptanceCase(
                "https://192.168.1.10/p?utm_source=x",
                .unchanged(.unsupported),
                label: "private IPv4"
            ),
            URLAcceptanceCase(
                "https://[2001:db8::1]/p?utm_source=x",
                .unchanged(.unsupported),
                label: "IPv6 literal"
            )
        ),
        URLAcceptanceFixture(
            56,
            URLAcceptanceCase(
                "https://例え.テスト/道?utm_source=x",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            57,
            URLAcceptanceCase(
                "https://xn--r8jz45g.xn--zckzah/p?utm_source=x",
                .cleaned("https://xn--r8jz45g.xn--zckzah/p")
            )
        ),
        URLAcceptanceFixture(
            58,
            URLAcceptanceCase(
                " \thttps://e.test/p?utm_source=x \r\n",
                .cleaned(" \thttps://e.test/p \r\n")
            )
        ),
        URLAcceptanceFixture(
            59,
            URLAcceptanceCase(
                "\nhttps://e.test/p?utm_source=x",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            60,
            URLAcceptanceCase(
                "https://e.test/p?utm_source=x\n\n",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            61,
            URLAcceptanceCase(
                "See https://e.test/p?utm_source=x",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            62,
            URLAcceptanceCase(
                "`https://e.test/p?utm_source=x`",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            63,
            URLAcceptanceCase(
                "curl 'https://e.test/p?utm_source=x'",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            64,
            URLAcceptanceCase(
                "https://e.test/a https://e.test/b",
                .unchanged(.unsupported)
            )
        ),
        URLAcceptanceFixture(
            65,
            URLAcceptanceCase(
                oversized,
                .unchanged(.unsupported)
            )
        ),
    ]
}

private struct PasteboardAcceptanceVariant {
    let label: String
    let items: [FakePasteboardItem]
    let expectedCleanedContent: PasteboardContent?
    let failureInjection: (@MainActor (FakePasteboardClient) -> Void)?

    init(
        label: String,
        items: [FakePasteboardItem],
        expectedCleanedContent: PasteboardContent? = nil,
        failureInjection: (@MainActor (FakePasteboardClient) -> Void)? = nil
    ) {
        self.label = label
        self.items = items
        self.expectedCleanedContent = expectedCleanedContent
        self.failureInjection = failureInjection
    }
}

private struct PasteboardAcceptanceFixture {
    let id: Int
    let variants: [PasteboardAcceptanceVariant]
}

private func makePasteboardAcceptanceFixtures() -> [PasteboardAcceptanceFixture] {
    let input = "https://e.test/p?utm_source=x"
    let output = "https://e.test/p"
    let plainInput = PasteboardContent(plainText: input)
    let urlInput = PasteboardContent(url: input)
    let dualInput = PasteboardContent(plainText: input, url: input)

    let unsupportedTypes = [
        ("image", "public.tiff"),
        ("file", "public.file-url"),
        ("custom", "com.example.synthetic"),
        ("concealed", PasteboardTypeIdentifier.concealed),
        ("transient", PasteboardTypeIdentifier.transient),
        ("autogenerated", PasteboardTypeIdentifier.autoGenerated),
        ("remote", PasteboardTypeIdentifier.remoteClipboard),
    ]

    return [
        PasteboardAcceptanceFixture(
            id: 66,
            variants: [
                PasteboardAcceptanceVariant(
                    label: "one plain-text item",
                    items: [FakePasteboardItem(content: plainInput)],
                    expectedCleanedContent: PasteboardContent(plainText: output)
                ),
            ]
        ),
        PasteboardAcceptanceFixture(
            id: 67,
            variants: [
                PasteboardAcceptanceVariant(
                    label: "one public.url item",
                    items: [FakePasteboardItem(content: urlInput)],
                    expectedCleanedContent: PasteboardContent(url: output)
                ),
                PasteboardAcceptanceVariant(
                    label: "public.url cannot use a plain-text envelope",
                    items: [
                        FakePasteboardItem(
                            content: PasteboardContent(
                                url: " \thttps://e.test/p?utm_source=x \r\n"
                            )
                        ),
                    ]
                ),
            ]
        ),
        PasteboardAcceptanceFixture(
            id: 68,
            variants: [
                PasteboardAcceptanceVariant(
                    label: "matching plain-text and URL",
                    items: [FakePasteboardItem(content: dualInput)],
                    expectedCleanedContent: PasteboardContent(
                        plainText: output,
                        url: output
                    )
                ),
            ]
        ),
        PasteboardAcceptanceFixture(
            id: 69,
            variants: [
                PasteboardAcceptanceVariant(
                    label: "conflicting plain-text and URL",
                    items: [
                        FakePasteboardItem(
                            content: PasteboardContent(
                                plainText: input,
                                url: "https://e.test/other?utm_source=x"
                            )
                        ),
                    ]
                ),
            ]
        ),
        PasteboardAcceptanceFixture(
            id: 70,
            variants: [
                PasteboardAcceptanceVariant(
                    label: "HTML plus plain text",
                    items: [
                        unsupportedItem(
                            input: input,
                            type: "public.html",
                            payload: Data("<a>synthetic</a>".utf8)
                        ),
                    ]
                ),
                PasteboardAcceptanceVariant(
                    label: "RTF plus plain text",
                    items: [
                        unsupportedItem(
                            input: input,
                            type: "public.rtf",
                            payload: Data("{\\rtf1 synthetic}".utf8)
                        ),
                    ]
                ),
            ]
        ),
        PasteboardAcceptanceFixture(
            id: 71,
            variants: [
                PasteboardAcceptanceVariant(
                    label: "multiple items",
                    items: [
                        FakePasteboardItem(content: plainInput),
                        FakePasteboardItem(
                            content: PasteboardContent(
                                plainText: "https://e.test/other?utm_source=x"
                            )
                        ),
                    ]
                ),
            ]
        ),
        PasteboardAcceptanceFixture(
            id: 72,
            variants: unsupportedTypes.map { label, type in
                PasteboardAcceptanceVariant(
                    label: "\(label) representation or marker",
                    items: [
                        unsupportedItem(
                            input: input,
                            type: type,
                            payload: Data("synthetic".utf8)
                        ),
                    ]
                )
            }
        ),
        PasteboardAcceptanceFixture(
            id: 73,
            variants: [
                PasteboardAcceptanceVariant(
                    label: "lazy allowed representation returns nil",
                    items: [FakePasteboardItem(content: plainInput)],
                    failureInjection: { $0.failNextDataRead = true }
                ),
                PasteboardAcceptanceVariant(
                    label: "lazy allowed representation changes generation",
                    items: [FakePasteboardItem(content: plainInput)],
                    failureInjection: {
                        $0.changeGenerationAfterNextDataRead = true
                    }
                ),
            ]
        ),
        PasteboardAcceptanceFixture(
            id: 74,
            variants: [
                PasteboardAcceptanceVariant(
                    label: "own marker on externally owned generation",
                    items: [
                        FakePasteboardItem(
                            content: plainInput,
                            includesTrackerFreeMarker: true
                        ),
                    ]
                ),
            ]
        ),
    ]
}

private func unsupportedItem(
    input: String,
    type: String,
    payload: Data
) -> FakePasteboardItem {
    FakePasteboardItem(representations: [
        PasteboardTypeIdentifier.plainText: Data(input.utf8),
        type: payload,
    ])
}

@MainActor
private func makeAcceptanceCoordinator(
    pasteboard: FakePasteboardClient,
    snapshot: RuleSetSnapshot,
    uptime: @escaping @MainActor () -> TimeInterval = {
        ProcessInfo.processInfo.systemUptime
    }
) -> ClipboardCoordinator {
    ClipboardCoordinator(
        pasteboard: pasteboard,
        stateStore: InMemoryClipboardCoordinatorStateStore(
            requestedEnabled: true
        ),
        transform: { input, _ in
            ClipboardContentTransformer.transform(input, using: snapshot)
        },
        ruleRevision: { snapshot.revision },
        uptime: uptime,
        automaticallyStartsMonitoring: false
    )
}

@MainActor
private final class AcceptanceStressClock {
    var uptime: TimeInterval = 10_000
}

@MainActor
private func runSyntheticEvents(
    count: Int,
    startingAt start: Int,
    pasteboard: FakePasteboardClient,
    coordinator: ClipboardCoordinator,
    clock: AcceptanceStressClock
) {
    for index in start..<(start + count) {
        autoreleasepool {
            let input =
                "https://stress.example.test/item/\(index)"
                + "?q=\(index)&utm_source=synthetic"
            pasteboard.replaceExternally(
                with: PasteboardContent(plainText: input)
            )
            coordinator.pollOnce()
            clock.uptime += 0.01
        }
    }
}

private enum AcceptanceMeasurementError: Error {
    case taskInfoFailed(kern_return_t)
}

private func residentMemoryBytes() throws -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info_data_t>.size
            / MemoryLayout<natural_t>.size
    )
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(
            to: integer_t.self,
            capacity: Int(count)
        ) {
            task_info(
                mach_task_self_,
                task_flavor_t(MACH_TASK_BASIC_INFO),
                $0,
                &count
            )
        }
    }
    guard status == KERN_SUCCESS else {
        throw AcceptanceMeasurementError.taskInfoFailed(status)
    }
    return info.resident_size
}

private func nanoseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000_000_000
        + Double(components.attoseconds) / 1_000_000_000
}

@inline(never)
private func acceptanceIsDebugBuild() -> Bool {
    _isDebugAssertConfiguration()
}
