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
    private func makeRealTransformCoordinator(
        _ client: NamedPasteboardClient
    ) throws -> ClipboardCoordinator {
        let snapshot = try TestRuleFactory.builtInSnapshot()
        return ClipboardCoordinator(
            pasteboard: client,
            stateStore: InMemoryClipboardCoordinatorStateStore(requestedEnabled: true),
            transform: { input, _ in
                ClipboardContentTransformer.transform(input, using: snapshot)
            },
            ruleRevision: { snapshot.revision },
            automaticallyStartsMonitoring: false
        )
    }

    @MainActor
    func testCoordinatorCleansObservedBrowserCopyLinkInventoriesAndRestoresThem() throws {
        for (label, original) in [
            ("Firefox", BrowserCopyFixture.firefox),
            ("Chrome", BrowserCopyFixture.chrome),
            ("WebKit", BrowserCopyFixture.webKit),
        ] {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let client = NamedPasteboardClient(pasteboard: board)
            let coordinator = try makeRealTransformCoordinator(client)

            try seed(board, content: original)
            coordinator.pollOnce()

            XCTAssertEqual(
                coordinator.lastResult,
                .cleaned(removedParameterNames: ["a", "s"]),
                label
            )
            XCTAssertEqual(
                Set(client.typeIdentifiers(forItemAt: 0) ?? []),
                [
                    PasteboardTypeIdentifier.plainText,
                    PasteboardTypeIdentifier.trackerFreeMarker,
                ],
                "\(label): a cleaned write must not carry the tracked URL in a companion"
            )
            XCTAssertTrue(PasteboardSnapshotReader.verify(
                PasteboardContent(plainText: BrowserCopyFixture.cleaned),
                includesMarker: true,
                in: client,
                generation: client.generation
            ), label)

            XCTAssertEqual(coordinator.restoreOriginal(), .restored, label)
            XCTAssertEqual(
                Set(client.typeIdentifiers(forItemAt: 0) ?? []),
                Set(original.companions.keys).union([PasteboardTypeIdentifier.plainText]),
                "\(label): Restore Original reproduces every representation"
            )
            XCTAssertTrue(PasteboardSnapshotReader.verify(
                original,
                includesMarker: false,
                in: client,
                generation: client.generation
            ), "\(label): Restore Original is byte-exact")
        }
    }

    @MainActor
    func testNamedClientAcceptsOnlyRedundantURLHTML() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let client = NamedPasteboardClient(pasteboard: board)
        let url = "https://example.test/p?utm_source=x&q=1"
        let escaped = url.replacingOccurrences(of: "&", with: "&amp;")

        let accepted: [(label: String, plainText: String, html: String)] = [
            ("Firefox envelope", url, BrowserCopyFixture.firefoxHTML(escaped)),
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
                companions: [PasteboardTypeIdentifier.html: Data(testCase.html.utf8)]
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
            ("extra visible text", "<span>Look: \(escaped)</span>"),
            ("hyperlink", "<a href=\"https://e.test/\">\(escaped)</a>"),
            ("image", "<span>\(escaped)</span><img src=\"x.png\">"),
            ("formatting", "<b>\(escaped)</b>"),
            ("style element", "<style>a{}</style><span>\(escaped)</span>"),
            ("unknown entity", "<span>https://example.test/p?utm_source=x&bogus;q=1</span>"),
            ("unterminated tag", "<span>\(escaped)</span"),
            ("unterminated comment", "<!-- \(url)"),
            ("bare less-than", "<span>\(escaped) < 1</span>"),
            ("empty", ""),
        ]
        for testCase in rejected {
            try seed(board, content: PasteboardContent(
                plainText: url,
                companions: [PasteboardTypeIdentifier.html: Data(testCase.html.utf8)]
            ))
            XCTAssertEqual(
                PasteboardSnapshotReader.capture(
                    from: client,
                    expectedGeneration: client.generation
                ),
                .failure(.unsupportedType),
                testCase.label
            )
        }
    }

    @MainActor
    func testNamedClientRejectsCompanionsThatAreNotProvablyRedundant() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let client = NamedPasteboardClient(pasteboard: board)
        typealias Fixture = BrowserCopyFixture
        let span = "<span>\(Fixture.escapedURL)</span>"

        let rejected: [(label: String, type: String, data: Data)] = [
            ("RTF with different text", PasteboardTypeIdentifier.rtf, Fixture.webKitRTF("https://example.test/other")),
            (
                "RTF hyperlink",
                PasteboardTypeIdentifier.rtf,
                Data(#"{\rtf1\ansi{\field{\*\fldinst{HYPERLINK "https://e.test/"}}{\fldrslt https://x.com/person/status/123?a=xa3_synthetic&s=20}}}"#.utf8)
            ),
            (
                "web archive with subresources",
                PasteboardTypeIdentifier.webArchive,
                Fixture.webArchive(html: span, extraTopLevel: [
                    "WebSubresources": [["WebResourceData": Data("x".utf8)]],
                ])
            ),
            ("web archive with rich HTML", PasteboardTypeIdentifier.webArchive, Fixture.webArchive(html: "<b>\(Fixture.escapedURL)</b>")),
            (
                "web archive with unknown resource key",
                PasteboardTypeIdentifier.webArchive,
                Fixture.webArchive(html: span, extraMainKeys: ["WebResourceResponse": Data("r".utf8)])
            ),
            ("web archive that is not HTML", PasteboardTypeIdentifier.webArchive, Fixture.webArchive(html: span, mimeType: "text/plain")),
            ("web archive that is not a property list", PasteboardTypeIdentifier.webArchive, Data("nope".utf8)),
            (
                "WebKit custom data with entries",
                PasteboardTypeIdentifier.webKitCustomData,
                Fixture.webKitCustomData(trailing: [1] + Array(repeating: 0, count: 15))
            ),
            (
                "WebKit custom data with trailing bytes",
                PasteboardTypeIdentifier.webKitCustomData,
                Fixture.webKitCustomData(trailing: Array(repeating: 0, count: 17))
            ),
            ("WebKit custom data version 2", PasteboardTypeIdentifier.webKitCustomData, Fixture.webKitCustomData(version: 2)),
            ("UTF-16 text that differs", PasteboardTypeIdentifier.utf16ExternalPlainText, Fixture.utf16External("https://example.test/other")),
            ("oversize Chromium frame token", PasteboardTypeIdentifier.chromiumSourceFrameToken, Data(count: 65)),
            ("Chromium source URL with a newline", PasteboardTypeIdentifier.chromiumSourceURL, Data("https://e.test/\nx".utf8)),
            ("Chromium source URL that is not UTF-8", PasteboardTypeIdentifier.chromiumSourceURL, Data([0xFF, 0xFE])),
            ("unknown companion type", "public.url-name", Data("name".utf8)),
        ]
        for testCase in rejected {
            try seed(board, content: PasteboardContent(
                plainText: Fixture.url,
                companions: [testCase.type: testCase.data]
            ))
            XCTAssertEqual(
                PasteboardSnapshotReader.capture(
                    from: client,
                    expectedGeneration: client.generation
                ),
                .failure(.unsupportedType),
                testCase.label
            )
        }

        // AppKit itself refuses to return malformed RTF from a real pasteboard, so
        // the read fails before validation; the validator is exercised directly too.
        try seed(board, content: PasteboardContent(
            plainText: Fixture.url,
            companions: [PasteboardTypeIdentifier.rtf: Data("plain words".utf8)]
        ))
        XCTAssertEqual(
            PasteboardSnapshotReader.capture(
                from: client,
                expectedGeneration: client.generation
            ),
            .failure(.representationUnavailable),
            "malformed RTF on a real pasteboard"
        )
        let fake = FakePasteboardClient(items: [FakePasteboardItem(content: PasteboardContent(
            plainText: Fixture.url,
            companions: [PasteboardTypeIdentifier.rtf: Data("plain words".utf8)]
        ))])
        XCTAssertEqual(
            PasteboardSnapshotReader.capture(from: fake, expectedGeneration: fake.generation),
            .failure(.unsupportedType),
            "malformed RTF reaching the validator"
        )

        try seed(board, content: PasteboardContent(
            url: Fixture.url,
            companions: [PasteboardTypeIdentifier.html: Data(span.utf8)]
        ))
        XCTAssertEqual(
            PasteboardSnapshotReader.capture(
                from: client,
                expectedGeneration: client.generation
            ),
            .failure(.unsupportedType),
            "Companions are only accepted beside a plain-text representation"
        )

        let marked = NSPasteboardItem()
        XCTAssertTrue(marked.setString(Fixture.cleaned, forType: .string))
        XCTAssertTrue(marked.setData(Data(), forType: NSPasteboard.PasteboardType(
            PasteboardTypeIdentifier.trackerFreeMarker
        )))
        XCTAssertTrue(marked.setData(Data(span.utf8), forType: .html))
        _ = board.prepareForNewContents(with: .currentHostOnly)
        XCTAssertTrue(board.writeObjects([marked]))
        XCTAssertFalse(
            PasteboardSnapshotReader.verify(
                PasteboardContent(
                    plainText: Fixture.cleaned,
                    companions: [PasteboardTypeIdentifier.html: Data(span.utf8)]
                ),
                includesMarker: true,
                in: client,
                generation: client.generation
            ),
            "A Tracker Free-owned value never carries a companion"
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
        for (type, data) in content.companions {
            XCTAssertTrue(item.setData(data, forType: NSPasteboard.PasteboardType(type)))
        }
        _ = board.prepareForNewContents(with: .currentHostOnly)
        XCTAssertTrue(board.writeObjects([item]))
    }
}

/// Clipboard inventories observed on 2026-11-04 by copying from a page that
/// mirrors X's web "Copy link" (a span selected and copied with execCommand):
/// Firefox Nightly on the live General pasteboard, Chrome 156 driven through
/// DevTools with a trusted click, and the system WebKit that Safari 27.3 uses.
/// Byte layouts follow the observed values; URLs and tokens are synthetic.
enum BrowserCopyFixture {
    static let url = "https://x.com/person/status/123?a=xa3_synthetic&s=20"
    static let escapedURL = "https://x.com/person/status/123?a=xa3_synthetic&amp;s=20"
    static let cleaned = "https://x.com/person/status/123"
    static let pageURL = "https://x.com/person/status/123"

    static func firefoxHTML(_ escapedText: String) -> String {
        "<html><head><meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\"></head>"
            + "<body><span style=\"position: absolute; white-space: pre-wrap; user-select: auto;\">"
            + escapedText
            + "</span></body></html>"
    }

    static var firefox: PasteboardContent {
        PasteboardContent(plainText: url, companions: [
            PasteboardTypeIdentifier.html: Data(firefoxHTML(escapedURL).utf8),
        ])
    }

    static let chromeHTML = "<meta charset='utf-8'><span style=\"color: rgb(0, 0, 0); font-family: Times; font-size: medium; font-style: normal; font-variant-ligatures: normal; font-variant-caps: normal; font-weight: 400; letter-spacing: normal; orphans: 2; text-align: start; text-indent: 0px; text-transform: none; widows: 2; word-spacing: 0px; -webkit-text-stroke-width: 0px; white-space: pre-wrap; text-decoration-thickness: initial; text-decoration-style: initial; text-decoration-color: initial; display: inline !important; float: none;\">\(escapedURL)</span>"

    static var chrome: PasteboardContent {
        PasteboardContent(plainText: url, companions: [
            PasteboardTypeIdentifier.html: Data(chromeHTML.utf8),
            PasteboardTypeIdentifier.chromiumSourceURL: Data(pageURL.utf8),
            PasteboardTypeIdentifier.chromiumSourceFrameToken: Data([
                0x14, 0x00, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00,
                0xCF, 0xA3, 0x58, 0x73, 0xBE, 0xA3, 0x06, 0x2A,
                0x51, 0x6E, 0x0C, 0x9D, 0x22, 0x47, 0x8A, 0x13,
            ]),
        ])
    }

    static let webKitSpan = "<span style=\"color: rgb(0, 0, 0); font-family: -webkit-standard; font-size: medium; font-style: normal; font-variant-caps: normal; font-weight: 400; letter-spacing: normal; orphans: 2; text-align: start; text-indent: 0px; text-transform: none; white-space: pre-wrap; widows: 2; word-spacing: 0px; -webkit-text-stroke-width: 0px; text-decoration: none; display: inline !important; float: none;\">\(escapedURL)</span>"

    static var webKit: PasteboardContent {
        PasteboardContent(plainText: url, companions: [
            PasteboardTypeIdentifier.webArchive: webArchive(
                html: "<!DOCTYPE html><body dir=\"ltr\">\(webKitSpan)</body>"
            ),
            PasteboardTypeIdentifier.rtf: webKitRTF(url),
            PasteboardTypeIdentifier.html: Data(webKitSpan.utf8),
            PasteboardTypeIdentifier.webKitCustomData: webKitCustomData(),
            PasteboardTypeIdentifier.utf16ExternalPlainText: utf16External(url),
        ])
    }

    static func webKitRTF(_ text: String) -> Data {
        Data((#"""
        {\rtf1\ansi\ansicpg1252\cocoartf2909
        \cocoatextscaling0\cocoaplatform0{\fonttbl\f0\froman\fcharset0 Times-Roman;}
        {\colortbl;\red255\green255\blue255;\red0\green0\blue0;}
        {\*\expandedcolortbl;;\cssrgb\c0\c0\c0;}
        \deftab720
        \pard\pardeftab720\partightenfactor0

        \f0\fs32 \cf0 \expnd0\expndtw0\kerning0
        \outl0\strokewidth0 \strokec2
        """# + " " + text + "}").utf8)
    }

    static func webArchive(
        html: String,
        mimeType: String = "text/html",
        extraMainKeys: [String: Any] = [:],
        extraTopLevel: [String: Any] = [:]
    ) -> Data {
        var mainResource: [String: Any] = [
            "WebResourceData": Data(html.utf8),
            "WebResourceFrameName": "",
            "WebResourceMIMEType": mimeType,
            "WebResourceTextEncodingName": "UTF-8",
            "WebResourceURL": pageURL,
        ]
        mainResource.merge(extraMainKeys) { $1 }
        var archive: [String: Any] = ["WebMainResource": mainResource]
        archive.merge(extraTopLevel) { $1 }
        return try! PropertyListSerialization.data(
            fromPropertyList: archive,
            format: .binary,
            options: 0
        )
    }

    /// WebKit's PasteboardCustomData v1: version, origin string, then an empty
    /// same-origin string map and an empty ordered type list (two zero UInt64s).
    static func webKitCustomData(
        origin: String = "https://x.com",
        version: UInt32 = 1,
        trailing: [UInt8] = Array(repeating: 0, count: 16)
    ) -> Data {
        var data = Data()
        withUnsafeBytes(of: version.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(origin.utf8.count).littleEndian) {
            data.append(contentsOf: $0)
        }
        data.append(1)
        data.append(contentsOf: origin.utf8)
        data.append(contentsOf: trailing)
        return data
    }

    static func utf16External(_ text: String) -> Data {
        var data = Data([0xFF, 0xFE])
        for unit in text.utf16 {
            withUnsafeBytes(of: unit.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}
