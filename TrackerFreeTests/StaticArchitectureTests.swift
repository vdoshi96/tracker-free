import Foundation
import XCTest
@testable import TrackerFree

final class StaticArchitectureTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testGeneralPasteboardIsIsolatedToProductionAdapter() throws {
        let sourceFiles = try swiftSourceFiles()
        var violations: [String] = []

        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains("NSPasteboard.general") else {
                continue
            }
            if file.lastPathComponent != "GeneralPasteboardClient.swift" {
                violations.append(relativePath(file))
            }
        }

        XCTAssertEqual(violations, [], "General pasteboard adapter violations: \(violations)")
    }

    func testProductionSourcesContainNoNetworkOrGlobalInputAPIs() throws {
        let forbiddenTokens = [
            "URLSession",
            "import WebKit",
            "import Network",
            "NWConnection",
            "NWListener",
            "CGEventTap",
            "addGlobalMonitorForEvents",
            "@unchecked Sendable",
            "Sparkle",
            "Sentry",
            "Firebase",
        ]
        var violations: [String] = []

        for file in try swiftSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens where source.contains(token) {
                violations.append("\(relativePath(file)): \(token)")
            }
        }

        XCTAssertEqual(violations, [], "Forbidden production API references: \(violations)")
    }

    func testEntitlementsAreSandboxedAndHaveNoNetworkAccess() throws {
        let entitlementsURL = repositoryRoot
            .appendingPathComponent("TrackerFree/Resources/TrackerFree.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(propertyList["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertNil(propertyList["com.apple.security.network.client"])
        XCTAssertNil(propertyList["com.apple.security.network.server"])
    }

    func testProjectHasNoThirdPartyDependencyManifest() {
        let prohibited = ["Package.swift", "Podfile", "Cartfile"]
        let present = prohibited.filter {
            FileManager.default.fileExists(
                atPath: repositoryRoot.appendingPathComponent($0).path
            )
        }
        XCTAssertEqual(present, [])
    }

    @MainActor
    func testHostedTestsUseIsolatedPasteboardMode() {
        XCTAssertTrue(AppState.isIsolatedTestProcess)
    }

    private func swiftSourceFiles() throws -> [URL] {
        let sourceRoot = repositoryRoot.appendingPathComponent("TrackerFree")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }

    private func relativePath(_ url: URL) -> String {
        url.path.replacingOccurrences(
            of: repositoryRoot.path + "/",
            with: ""
        )
    }
}
