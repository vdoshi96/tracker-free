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
        _ = board.prepareForNewContents(with: .currentHostOnly)
        XCTAssertTrue(board.writeObjects([item]))
    }
}
