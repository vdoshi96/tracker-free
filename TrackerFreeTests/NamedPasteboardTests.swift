import AppKit
import Foundation
import XCTest
@testable import TrackerFree

final class NamedPasteboardTests: XCTestCase {
    @MainActor
    func testNamedClientCapturesWritesAndVerifiesAllowedRepresentations() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let client = NamedPasteboardClient(pasteboard: board)
        let original = PasteboardContent(
            plainText: " \thttps://example.test/p?utm_source=x \n",
            url: "https://example.test/p?utm_source=x"
        )
        try seed(board, content: original)

        let originalGeneration = client.generation
        guard case let .success(snapshot) = PasteboardSnapshotReader.capture(
            from: client,
            expectedGeneration: originalGeneration
        ) else {
            return XCTFail("Expected a bounded matching snapshot")
        }
        XCTAssertEqual(snapshot.content, original)

        let cleaned = PasteboardContent(
            plainText: " \thttps://example.test/p \n",
            url: "https://example.test/p"
        )
        let request = PasteboardWriteRequest(
            content: cleaned,
            includesTrackerFreeMarker: true
        )
        let prepared = try XCTUnwrap(client.prepareWrite(request))
        _ = client.prepareForNewContentsCurrentHostOnly()
        XCTAssertTrue(client.writePrepared(prepared))
        let writtenGeneration = client.generation

        XCTAssertTrue(PasteboardSnapshotReader.verify(
            cleaned,
            includesMarker: true,
            in: client,
            generation: writtenGeneration
        ))
    }

    @MainActor
    func testCoordinatorCleansAndRestoresOnUniqueNamedPasteboard() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let client = NamedPasteboardClient(pasteboard: board)
        let store = InMemoryClipboardCoordinatorStateStore(requestedEnabled: true)
        let coordinator = ClipboardCoordinator(
            pasteboard: client,
            stateStore: store,
            transform: { input, _ in
                let output = PasteboardContent(
                    plainText: input.content.plainText?.replacingOccurrences(
                        of: "?utm_source=x",
                        with: ""
                    ),
                    url: input.content.url?.replacingOccurrences(
                        of: "?utm_source=x",
                        with: ""
                    )
                )
                guard output != input.content else {
                    return .unchanged(.noKnownTrackingParameters)
                }
                return .changed(ClipboardTransformOutput(
                    content: output,
                    removedParameterNames: ["utm_source"]
                ))
            },
            ruleRevision: { 1 },
            automaticallyStartsMonitoring: false
        )

        let original = PasteboardContent(
            plainText: "https://example.test/p?utm_source=x"
        )
        try seed(board, content: original)
        coordinator.pollOnce()

        XCTAssertEqual(
            coordinator.lastResult,
            .cleaned(removedParameterNames: ["utm_source"])
        )
        XCTAssertTrue(coordinator.canRestoreOriginal)
        XCTAssertEqual(coordinator.restoreOriginal(), .restored)

        let restoredGeneration = client.generation
        XCTAssertTrue(PasteboardSnapshotReader.verify(
            original,
            includesMarker: false,
            in: client,
            generation: restoredGeneration
        ))
    }

    /// Firefox on macOS wraps HTML written by a web page's copy command in this
    /// envelope. X's web "Copy link" produces exactly one such item: plain text
    /// plus an HTML span carrying the same URL.
    private static func firefoxCopyLinkHTML(_ escapedURL: String) -> String {
        "<html><head><meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\"></head>"
            + "<body><span style=\"position: absolute; white-space: pre-wrap; user-select: auto;\">"
            + escapedURL
            + "</span></body></html>"
    }

    @MainActor
    func testCoordinatorCleansBrowserCopyLinkWithRedundantHTMLAndRestoresIt() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let client = NamedPasteboardClient(pasteboard: board)
        let snapshot = try TestRuleFactory.builtInSnapshot()
        let coordinator = ClipboardCoordinator(
            pasteboard: client,
            stateStore: InMemoryClipboardCoordinatorStateStore(requestedEnabled: true),
            transform: { input, _ in
                ClipboardContentTransformer.transform(input, using: snapshot)
            },
            ruleRevision: { snapshot.revision },
            automaticallyStartsMonitoring: false
        )

        let original = PasteboardContent(
            plainText: "https://x.com/person/status/123?a=xa3_synthetic&s=20",
            html: Self.firefoxCopyLinkHTML(
                "https://x.com/person/status/123?a=xa3_synthetic&amp;s=20"
            )
        )
        try seed(board, content: original)
        coordinator.pollOnce()

        XCTAssertEqual(
            coordinator.lastResult,
            .cleaned(removedParameterNames: ["a", "s"])
        )
        let cleanedGeneration = client.generation
        XCTAssertEqual(
            Set(client.typeIdentifiers(forItemAt: 0) ?? []),
            [
                PasteboardTypeIdentifier.plainText,
                PasteboardTypeIdentifier.trackerFreeMarker,
            ],
            "The cleaned write must not carry the tracked URL in a rich representation"
        )
        XCTAssertTrue(PasteboardSnapshotReader.verify(
            PasteboardContent(plainText: "https://x.com/person/status/123"),
            includesMarker: true,
            in: client,
            generation: cleanedGeneration
        ))

        XCTAssertEqual(coordinator.restoreOriginal(), .restored)
        let restoredGeneration = client.generation
        XCTAssertTrue(PasteboardSnapshotReader.verify(
            original,
            includesMarker: false,
            in: client,
            generation: restoredGeneration
        ))
    }

    @MainActor
    func testNamedClientAcceptsOnlyRedundantURLHTML() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let client = NamedPasteboardClient(pasteboard: board)
        let url = "https://example.test/p?utm_source=x&q=1"

        let accepted: [(label: String, plainText: String, html: String)] = [
            ("Firefox envelope", url, Self.firefoxCopyLinkHTML(
                "https://example.test/p?utm_source=x&amp;q=1"
            )),
            (
                "Chromium envelope",
                url,
                "<meta charset='utf-8'><span style=\"color: rgb(0, 0, 0);\">"
                    + "https://example.test/p?utm_source=x&#38;q=1</span>"
            ),
            (
                "doctype, fragment comments, and edge whitespace",
                " \(url)\n",
                "<!DOCTYPE html>\n<html><body>\n<!--StartFragment-->"
                    + "https://example.test/p?utm_source=x&#x26;q=1"
                    + "<!--EndFragment-->\n</body></html>"
            ),
        ]
        for testCase in accepted {
            let content = PasteboardContent(
                plainText: testCase.plainText,
                html: testCase.html
            )
            try seed(board, content: content)
            XCTAssertEqual(
                PasteboardSnapshotReader.capture(
                    from: client,
                    expectedGeneration: client.generation
                ),
                .success(PasteboardSnapshot(
                    generation: client.generation,
                    content: content
                )),
                testCase.label
            )
        }

        let rejected: [(label: String, html: String)] = [
            ("different URL", "<span>https://example.test/other</span>"),
            ("extra visible text", "<span>Look: \(url.replacingOccurrences(of: "&", with: "&amp;"))</span>"),
            ("hyperlink", "<a href=\"https://e.test/\">\(url.replacingOccurrences(of: "&", with: "&amp;"))</a>"),
            ("image", "<span>\(url.replacingOccurrences(of: "&", with: "&amp;"))</span><img src=\"x.png\">"),
            ("formatting", "<b>\(url.replacingOccurrences(of: "&", with: "&amp;"))</b>"),
            ("style element", "<style>a{}</style><span>\(url.replacingOccurrences(of: "&", with: "&amp;"))</span>"),
            ("unknown entity", "<span>https://example.test/p?utm_source=x&bogus;q=1</span>"),
            ("unterminated tag", "<span>\(url.replacingOccurrences(of: "&", with: "&amp;"))</span"),
            ("unterminated comment", "<!-- \(url)"),
            ("bare less-than", "<span>\(url.replacingOccurrences(of: "&", with: "&amp;")) < 1</span>"),
            ("empty", ""),
        ]
        for testCase in rejected {
            try seed(board, content: PasteboardContent(plainText: url, html: testCase.html))
            XCTAssertEqual(
                PasteboardSnapshotReader.capture(
                    from: client,
                    expectedGeneration: client.generation
                ),
                .failure(.unsupportedType),
                testCase.label
            )
        }

        try seed(board, content: PasteboardContent(
            url: url,
            html: Self.firefoxCopyLinkHTML(url.replacingOccurrences(of: "&", with: "&amp;"))
        ))
        XCTAssertEqual(
            PasteboardSnapshotReader.capture(
                from: client,
                expectedGeneration: client.generation
            ),
            .failure(.unsupportedType),
            "HTML is only accepted as a companion to a plain-text representation"
        )
    }

    @MainActor
    func testNamedClientRejectsRichAndMultipleItemsWithoutMutation() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let client = NamedPasteboardClient(pasteboard: board)

        _ = board.prepareForNewContents(with: .currentHostOnly)
        let richItem = NSPasteboardItem()
        XCTAssertTrue(richItem.setString(
            "https://example.test/p?utm_source=x",
            forType: .string
        ))
        XCTAssertTrue(richItem.setString(
            "<a>synthetic</a>",
            forType: .html
        ))
        XCTAssertTrue(board.writeObjects([richItem]))
        let richGeneration = client.generation

        XCTAssertEqual(
            PasteboardSnapshotReader.capture(
                from: client,
                expectedGeneration: richGeneration
            ),
            .failure(.unsupportedType)
        )

        _ = board.prepareForNewContents(with: .currentHostOnly)
        let first = NSPasteboardItem()
        let second = NSPasteboardItem()
        XCTAssertTrue(first.setString("https://example.test/a", forType: .string))
        XCTAssertTrue(second.setString("https://example.test/b", forType: .string))
        XCTAssertTrue(board.writeObjects([first, second]))
        let multipleGeneration = client.generation

        XCTAssertEqual(
            PasteboardSnapshotReader.capture(
                from: client,
                expectedGeneration: multipleGeneration
            ),
            .failure(.requiresExactlyOneItem)
        )
    }

    @MainActor
    private func seed(
        _ board: NSPasteboard,
        content: PasteboardContent
    ) throws {
        let item = NSPasteboardItem()
        if let plainText = content.plainText {
            XCTAssertTrue(item.setString(plainText, forType: .string))
        }
        if let url = content.url {
            XCTAssertTrue(item.setString(url, forType: .URL))
        }
        if let html = content.html {
            XCTAssertTrue(item.setString(html, forType: .html))
        }
        _ = board.prepareForNewContents(with: .currentHostOnly)
        XCTAssertTrue(board.writeObjects([item]))
    }
}
