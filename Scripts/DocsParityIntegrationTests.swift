#!/usr/bin/env swift

import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private struct Result {
    let status: Int32
    let output: String
}

private let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let generatorSource = repositoryRoot.appendingPathComponent("Scripts/DocsParity.swift")
private let testRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("tracker-free-docs-parity-tests-\(UUID().uuidString)", isDirectory: true)
private let generatorExecutable = testRoot.appendingPathComponent("docs-parity")

private func run(_ executable: String, _ arguments: [String], at directory: URL? = nil) throws -> Result {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    return Result(
        status: process.terminationStatus,
        output: String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    )
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(text.utf8).write(to: url, options: [.atomic])
}

private func fixture(_ name: String) throws -> URL {
    let url = testRoot.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let result = try run("/usr/bin/git", ["init", "-q", url.path])
    guard result.status == 0 else {
        throw TestFailure(description: "Could not initialize fixture \(name): \(result.output)")
    }
    return url
}

private func parity(_ mode: String, root: URL) throws -> Result {
    try run(generatorExecutable.path, [mode, "--root", root.path])
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw TestFailure(description: message)
    }
}

do {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: testRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: testRoot) }

    let compile = try run(
        "/usr/bin/xcrun",
        ["swiftc", generatorSource.path, "-o", generatorExecutable.path]
    )
    try require(compile.status == 0, "Generator did not compile: \(compile.output)")

    let basic = try fixture("basic")
    try write(
        """
        # Example

        See [details](docs/DETAILS.md#same-heading).

        ## Same heading

        First.

        ## Same heading

        Second.
        """,
        to: basic.appendingPathComponent("README.md")
    )
    let missingCheck = try parity("--check", root: basic)
    try require(missingCheck.status != 0, "Missing output unexpectedly passed check.")
    let firstGenerate = try parity("--generate", root: basic)
    try require(firstGenerate.status == 0, "Generation failed: \(firstGenerate.output)")
    let htmlURL = basic.appendingPathComponent("README.html")
    let firstHTML = try String(contentsOf: htmlURL, encoding: .utf8)
    try require(
        firstHTML.contains("tracker-free-docs-parity:v1"),
        "Ownership marker is missing."
    )
    try require(
        firstHTML.contains("href=\"docs/DETAILS.html#same-heading\""),
        "Local Markdown link was not rewritten."
    )
    try require(
        firstHTML.contains("id=\"same-heading\"") && firstHTML.contains("id=\"same-heading-2\""),
        "Heading IDs are not stable and de-duplicated."
    )
    let secondGenerate = try parity("--generate", root: basic)
    try require(secondGenerate.status == 0, "Second generation failed.")
    let secondHTML = try String(contentsOf: htmlURL, encoding: .utf8)
    try require(firstHTML == secondHTML, "Generation is not deterministic.")
    let passingCheck = try parity("--check", root: basic)
    try require(passingCheck.status == 0, "Fresh output failed check.")
    try write("# Example\n\nChanged.\n", to: basic.appendingPathComponent("README.md"))
    let staleCheck = try parity("--check", root: basic)
    try require(staleCheck.status != 0, "Stale output unexpectedly passed check.")

    let collision = try fixture("collision")
    try write("# Collision\n", to: collision.appendingPathComponent("README.md"))
    try write("<html>unmanaged</html>\n", to: collision.appendingPathComponent("README.html"))
    let collisionResult = try parity("--generate", root: collision)
    try require(collisionResult.status != 0, "Unmanaged HTML collision was overwritten.")

    let orphan = try fixture("orphan")
    try write("# Orphan\n", to: orphan.appendingPathComponent("README.md"))
    let orphanSetup = try parity("--generate", root: orphan)
    try require(orphanSetup.status == 0, "Orphan setup failed.")
    try fileManager.removeItem(at: orphan.appendingPathComponent("README.md"))
    let orphanCheck = try parity("--check", root: orphan)
    try require(orphanCheck.status != 0, "Orphan passed check.")
    let orphanCleanup = try parity("--generate", root: orphan)
    try require(orphanCleanup.status == 0, "Orphan cleanup failed.")
    try require(
        !fileManager.fileExists(atPath: orphan.appendingPathComponent("README.html").path),
        "Marker-owned orphan was not removed."
    )

    let unsupported = try fixture("unsupported")
    try write("Unsupported\n===========\n", to: unsupported.appendingPathComponent("docs/legacy.rst"))
    let unsupportedResult = try parity("--generate", root: unsupported)
    try require(unsupportedResult.status != 0, "Unsupported RST did not fail closed.")

    let sourceSymlink = try fixture("source-symlink")
    try write("# Target\n", to: sourceSymlink.appendingPathComponent("target"))
    try fileManager.createSymbolicLink(
        at: sourceSymlink.appendingPathComponent("README.md"),
        withDestinationURL: sourceSymlink.appendingPathComponent("target")
    )
    let sourceSymlinkResult = try parity("--generate", root: sourceSymlink)
    try require(sourceSymlinkResult.status != 0, "Markdown source symlink was followed.")

    let outputSymlink = try fixture("output-symlink")
    try write("# Output link\n", to: outputSymlink.appendingPathComponent("README.md"))
    try write("target\n", to: outputSymlink.appendingPathComponent("target"))
    try fileManager.createSymbolicLink(
        at: outputSymlink.appendingPathComponent("README.html"),
        withDestinationURL: outputSymlink.appendingPathComponent("target")
    )
    let outputSymlinkResult = try parity("--generate", root: outputSymlink)
    try require(outputSymlinkResult.status != 0, "HTML output symlink was followed.")

    print("DocsParity integration tests passed (determinism, missing/stale, links/IDs, collision, orphan, unsupported format, symlinks).")
} catch {
    FileHandle.standardError.write(Data("DocsParity integration test failure: \(error)\n".utf8))
    try? FileManager.default.removeItem(at: testRoot)
    exit(1)
}
