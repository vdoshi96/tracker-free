#!/usr/bin/env swift

import CryptoKit
import Darwin
import Foundation

private enum Mode: String {
    case generate = "--generate"
    case check = "--check"
}

private struct ParityFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct ManagedMarker {
    let sourceHash: String
    let sourcePath: String
}

private struct SourceDocument {
    let path: String
    let sourceData: Data
    let outputPath: String
    let renderedData: Data
}

private final class GitInventory {
    private let root: URL

    init(root: URL) {
        self.root = root
    }

    func visiblePaths() throws -> [String] {
        let result = try run(
            executable: "/usr/bin/git",
            arguments: [
                "-C", root.path,
                "ls-files", "--cached", "--others", "--exclude-standard", "-z",
            ]
        )
        guard result.status == 0 else {
            throw ParityFailure("Git inventory failed: \(result.stderr)")
        }

        return try result.stdout
            .split(separator: 0, omittingEmptySubsequences: true)
            .map { bytes in
                guard let path = String(data: Data(bytes), encoding: .utf8) else {
                    throw ParityFailure("Git returned a non-UTF-8 path; refusing ambiguous discovery.")
                }
                return path
            }
            .sorted()
    }
}

private final class DocsParity {
    private static let markerPrefix = "<!-- tracker-free-docs-parity:v1 "
    private static let markerPattern = try! NSRegularExpression(
        pattern: #"^<!-- tracker-free-docs-parity:v1 source-sha256=([0-9a-f]{64}) source-path-base64=([A-Za-z0-9+/=]+) -->$"#
    )

    private let root: URL
    private let inventory: GitInventory
    private let fileManager = FileManager.default

    init(root: URL) {
        self.root = root
        self.inventory = GitInventory(root: root)
    }

    func run(mode: Mode) throws {
        let visiblePaths = try inventory.visiblePaths()
        let unsupported = visiblePaths.filter(isUnsupportedDocumentation)
        guard unsupported.isEmpty else {
            throw ParityFailure(
                "Unsupported documentation format(s) require a structure-preserving renderer: "
                    + unsupported.joined(separator: ", ")
            )
        }

        let sourcePaths = visiblePaths
            .filter(isMarkdownSource)
            .filter { pathExistsWithoutFollowingSymlink(absoluteURL(for: $0)) }

        var documents: [SourceDocument] = []
        var expectedOutputs: Set<String> = []

        for sourcePath in sourcePaths {
            let sourceURL = absoluteURL(for: sourcePath)
            try requireRegularNonSymlink(sourceURL, role: "Markdown source")
            let sourceData = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
            guard let source = String(data: sourceData, encoding: .utf8) else {
                throw ParityFailure("\(sourcePath): Markdown source is not valid UTF-8.")
            }

            let outputPath = replacingExtension(of: sourcePath, with: "html")
            let outputURL = absoluteURL(for: outputPath)
            expectedOutputs.insert(outputPath)
            try preflightOutput(outputURL, sourcePath: sourcePath)

            let hash = sha256(sourceData)
            let rendered = try MarkdownRenderer().render(
                source: source,
                sourcePath: sourcePath,
                sourceHash: hash
            )
            guard let renderedData = rendered.data(using: .utf8) else {
                throw ParityFailure("\(sourcePath): generated HTML was not UTF-8 encodable.")
            }
            documents.append(
                SourceDocument(
                    path: sourcePath,
                    sourceData: sourceData,
                    outputPath: outputPath,
                    renderedData: renderedData
                )
            )
        }

        let managedOutputs = try discoverManagedOutputs(in: visiblePaths)
        let orphans = try managedOutputs.filter { outputPath, marker in
            guard !expectedOutputs.contains(outputPath) else {
                return false
            }
            let expectedCompanion = replacingExtension(of: marker.sourcePath, with: "html")
            guard expectedCompanion == outputPath else {
                throw ParityFailure(
                    "\(outputPath): ownership marker points to non-companion source "
                        + "\(marker.sourcePath); refusing cleanup."
                )
            }
            return true
        }.map(\.key).sorted()

        switch mode {
        case .check:
            var problems: [String] = []
            for document in documents {
                let outputURL = absoluteURL(for: document.outputPath)
                guard fileManager.fileExists(atPath: outputURL.path) else {
                    problems.append("\(document.outputPath): missing")
                    continue
                }
                let actual = try Data(contentsOf: outputURL, options: [.mappedIfSafe])
                if actual != document.renderedData {
                    problems.append("\(document.outputPath): stale or non-deterministic")
                }
            }
            for orphan in orphans {
                problems.append("\(orphan): marker-owned orphan")
            }
            guard problems.isEmpty else {
                throw ParityFailure(
                    "Documentation parity check failed:\n- " + problems.joined(separator: "\n- ")
                )
            }
            print("Documentation parity check passed (\(documents.count) source(s)).")

        case .generate:
            for document in documents {
                let outputURL = absoluteURL(for: document.outputPath)
                try document.renderedData.write(to: outputURL, options: [.atomic])
            }
            for orphan in orphans {
                try removeManagedOrphanAtomically(path: orphan)
            }
            print(
                "Generated \(documents.count) HTML companion(s)"
                    + (orphans.isEmpty ? "." : " and removed \(orphans.count) marker-owned orphan(s).")
            )
        }
    }

    private func absoluteURL(for relativePath: String) -> URL {
        root.appendingPathComponent(relativePath, isDirectory: false)
    }

    private func isExcluded(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.lowercased() }
        let excludedComponents: Set<String> = [
            ".git", ".build", "build", "deriveddata", "node_modules", "pods",
            "carthage", "vendor", "third_party", "qa", "artifacts", ".agents",
            ".codex", ".private", "private", "secrets",
        ]
        return components.contains { excludedComponents.contains($0) }
    }

    private func isMarkdownSource(_ path: String) -> Bool {
        !isExcluded(path) && URL(fileURLWithPath: path).pathExtension.lowercased() == "md"
    }

    private func isUnsupportedDocumentation(_ path: String) -> Bool {
        guard !isExcluded(path) else {
            return false
        }
        let url = URL(fileURLWithPath: path)
        let extensionName = url.pathExtension.lowercased()
        if ["mdx", "rst", "adoc", "asciidoc"].contains(extensionName) {
            return true
        }
        if extensionName == "txt" {
            let isDocsDirectory = path.lowercased().hasPrefix("docs/")
            let knownDocStem = [
                "readme", "project", "status", "decisions", "sources", "skills",
                "log", "wiki", "architecture", "privacy", "testing", "security",
                "contributing", "changelog",
            ].contains(url.deletingPathExtension().lastPathComponent.lowercased())
            return isDocsDirectory || knownDocStem
        }
        return false
    }

    private func preflightOutput(_ outputURL: URL, sourcePath: String) throws {
        guard pathExistsWithoutFollowingSymlink(outputURL) else {
            return
        }
        try requireRegularNonSymlink(outputURL, role: "HTML companion")
        let data = try Data(contentsOf: outputURL, options: [.mappedIfSafe])
        guard let marker = try parseMarker(from: data) else {
            throw ParityFailure(
                "\(relativePath(for: outputURL)): unmanaged same-basename HTML collision; "
                    + "refusing overwrite."
            )
        }
        guard marker.sourcePath == sourcePath else {
            throw ParityFailure(
                "\(relativePath(for: outputURL)): ownership marker belongs to \(marker.sourcePath), "
                    + "not \(sourcePath)."
            )
        }
    }

    private func discoverManagedOutputs(
        in visiblePaths: [String]
    ) throws -> [String: ManagedMarker] {
        var outputs: [String: ManagedMarker] = [:]
        for path in visiblePaths
            where !isExcluded(path)
                && URL(fileURLWithPath: path).pathExtension.lowercased() == "html"
                && pathExistsWithoutFollowingSymlink(absoluteURL(for: path))
        {
            let url = absoluteURL(for: path)
            try requireRegularNonSymlink(url, role: "HTML file")
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let prefixData = try handle.read(upToCount: 1024) ?? Data()
            guard let prefix = String(data: prefixData, encoding: .utf8) else {
                continue
            }
            guard prefix.hasPrefix(Self.markerPrefix) else {
                continue
            }
            guard let marker = try parseMarker(from: prefixData) else {
                throw ParityFailure("\(path): malformed Tracker Free ownership marker.")
            }
            outputs[path] = marker
        }
        return outputs
    }

    private func parseMarker(from data: Data) throws -> ManagedMarker? {
        guard let text = String(data: data, encoding: .utf8),
              let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init),
              firstLine.hasPrefix(Self.markerPrefix)
        else {
            return nil
        }

        let range = NSRange(firstLine.startIndex..<firstLine.endIndex, in: firstLine)
        guard let match = Self.markerPattern.firstMatch(in: firstLine, range: range),
              match.numberOfRanges == 3,
              let hashRange = Range(match.range(at: 1), in: firstLine),
              let pathRange = Range(match.range(at: 2), in: firstLine),
              let pathData = Data(base64Encoded: String(firstLine[pathRange])),
              let path = String(data: pathData, encoding: .utf8),
              isSafeRelativePath(path)
        else {
            throw ParityFailure("Malformed Tracker Free documentation ownership marker.")
        }

        return ManagedMarker(sourceHash: String(firstLine[hashRange]), sourcePath: path)
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    private func requireRegularNonSymlink(_ url: URL, role: String) throws {
        var status = stat()
        guard lstat(url.path, &status) == 0 else {
            throw ParityFailure("\(relativePath(for: url)): \(role) could not be inspected.")
        }
        let kind = status.st_mode & S_IFMT
        guard kind != S_IFLNK else {
            throw ParityFailure("\(relativePath(for: url)): \(role) is a symlink; refusing access.")
        }
        guard kind == S_IFREG else {
            throw ParityFailure("\(relativePath(for: url)): \(role) is not a regular file.")
        }
    }

    private func pathExistsWithoutFollowingSymlink(_ url: URL) -> Bool {
        var status = stat()
        return lstat(url.path, &status) == 0
    }

    private func removeManagedOrphanAtomically(path: String) throws {
        let original = absoluteURL(for: path)
        let temporary = original.deletingLastPathComponent()
            .appendingPathComponent(".docs-parity-orphan-\(UUID().uuidString)")
        do {
            try fileManager.moveItem(at: original, to: temporary)
            try fileManager.removeItem(at: temporary)
        } catch {
            if pathExistsWithoutFollowingSymlink(temporary),
               !pathExistsWithoutFollowingSymlink(original)
            {
                try? fileManager.moveItem(at: temporary, to: original)
            }
            throw ParityFailure("\(path): could not safely remove marker-owned orphan: \(error)")
        }
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            return path
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func replacingExtension(of path: String, with extensionName: String) -> String {
        let base = (path as NSString).deletingPathExtension
        guard let replaced = (base as NSString).appendingPathExtension(extensionName) else {
            return base + "." + extensionName
        }
        return replaced
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class MarkdownRenderer {
    private var headingCounts: [String: Int] = [:]

    func render(source: String, sourcePath: String, sourceHash: String) throws -> String {
        headingCounts = [:]
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let title = firstHeading(in: lines) ?? URL(fileURLWithPath: sourcePath)
            .deletingPathExtension().lastPathComponent
        let body = try renderBlocks(lines)
        let encodedPath = Data(sourcePath.utf8).base64EncodedString()

        return """
        <!-- tracker-free-docs-parity:v1 source-sha256=\(sourceHash) source-path-base64=\(encodedPath) -->
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="generator" content="Tracker Free DocsParity v1">
          <meta name="source-sha256" content="\(sourceHash)">
          <title>\(escapeHTML(title))</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.55; }
            body { max-width: 74rem; margin: 0 auto; padding: 2rem clamp(1rem, 4vw, 3rem); }
            h1, h2, h3, h4, h5, h6 { line-height: 1.2; margin-top: 1.6em; }
            a { color: LinkText; }
            code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
            code { background: color-mix(in srgb, CanvasText 8%, Canvas); border-radius: .25rem; padding: .08rem .3rem; }
            pre { overflow-x: auto; padding: 1rem; border: 1px solid color-mix(in srgb, CanvasText 18%, Canvas); border-radius: .5rem; }
            pre code { background: transparent; padding: 0; }
            table { width: 100%; border-collapse: collapse; display: block; overflow-x: auto; }
            th, td { border: 1px solid color-mix(in srgb, CanvasText 22%, Canvas); padding: .45rem .6rem; text-align: left; vertical-align: top; }
            blockquote { border-left: .25rem solid color-mix(in srgb, CanvasText 25%, Canvas); margin-left: 0; padding-left: 1rem; }
            .generated-note { color: color-mix(in srgb, CanvasText 65%, Canvas); font-size: .9rem; }
          </style>
        </head>
        <body>
          <p class="generated-note">Generated from <code>\(escapeHTML(sourcePath))</code>. Edit the Markdown source, then regenerate.</p>
        \(body)
        </body>
        </html>
        """
    }

    private func renderBlocks(_ lines: [String]) throws -> String {
        var output: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                guard index < lines.count else {
                    throw ParityFailure("Unclosed fenced code block.")
                }
                index += 1
                let languageClass = language.isEmpty
                    ? ""
                    : " class=\"language-\(escapeAttribute(language))\""
                let code = escapeHTML(codeLines.joined(separator: "\n"))
                    .replacingOccurrences(of: " \n", with: "&#32;\n")
                output.append("<pre><code\(languageClass)>\(code)</code></pre>")
                continue
            }

            if let heading = parseHeading(line) {
                let identifier = uniqueHeadingID(for: heading.text)
                output.append(
                    "<h\(heading.level) id=\"\(escapeAttribute(identifier))\">"
                        + renderInline(heading.text)
                        + "</h\(heading.level)>"
                )
                index += 1
                continue
            }

            if isHorizontalRule(line) {
                output.append("<hr>")
                index += 1
                continue
            }

            if index + 1 < lines.count, isTableDelimiter(lines[index + 1]), line.contains("|") {
                let headers = splitTableRow(line)
                index += 2
                var rows: [[String]] = []
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                      lines[index].contains("|")
                {
                    rows.append(splitTableRow(lines[index]))
                    index += 1
                }
                output.append(renderTable(headers: headers, rows: rows))
                continue
            }

            if isUnorderedListItem(line) {
                var items: [String] = []
                while index < lines.count, isUnorderedListItem(lines[index]) {
                    items.append(String(lines[index].dropFirst(2)))
                    index += 1
                }
                output.append(
                    "<ul>\n"
                        + items.map { "  <li>\(renderInline($0))</li>" }.joined(separator: "\n")
                        + "\n</ul>"
                )
                continue
            }

            if let orderedItem = orderedListItem(line) {
                var items = [orderedItem]
                index += 1
                while index < lines.count, let item = orderedListItem(lines[index]) {
                    items.append(item)
                    index += 1
                }
                output.append(
                    "<ol>\n"
                        + items.map { "  <li>\(renderInline($0))</li>" }.joined(separator: "\n")
                        + "\n</ol>"
                )
                continue
            }

            if line.hasPrefix("> ") {
                var quoteLines: [String] = []
                while index < lines.count, lines[index].hasPrefix("> ") {
                    quoteLines.append(String(lines[index].dropFirst(2)))
                    index += 1
                }
                output.append(
                    "<blockquote><p>"
                        + renderInline(quoteLines.joined(separator: " "))
                        + "</p></blockquote>"
                )
                continue
            }

            var paragraph = [line]
            index += 1
            while index < lines.count,
                  !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                  !startsBlock(lines, at: index)
            {
                paragraph.append(lines[index])
                index += 1
            }
            output.append("<p>\(renderInline(paragraph.joined(separator: " ")))</p>")
        }

        return output.map { "  \($0)" }.joined(separator: "\n")
    }

    private func startsBlock(_ lines: [String], at index: Int) -> Bool {
        let line = lines[index]
        if line.hasPrefix("```") || parseHeading(line) != nil || isHorizontalRule(line)
            || isUnorderedListItem(line) || orderedListItem(line) != nil || line.hasPrefix("> ")
        {
            return true
        }
        return index + 1 < lines.count && line.contains("|") && isTableDelimiter(lines[index + 1])
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else {
            return nil
        }
        var text = String(line.dropFirst(hashes + 1)).trimmingCharacters(in: .whitespaces)
        while text.last == "#" {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return (hashes, text)
    }

    private func firstHeading(in lines: [String]) -> String? {
        for line in lines {
            if let heading = parseHeading(line), heading.level == 1 {
                return stripInlineMarkdown(heading.text)
            }
        }
        return nil
    }

    private func uniqueHeadingID(for heading: String) -> String {
        let plain = stripInlineMarkdown(heading).lowercased(with: Locale(identifier: "en_US_POSIX"))
        var slug = ""
        var pendingHyphen = false
        for scalar in plain.unicodeScalars {
            let isASCIIAlphaNumeric =
                (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 97 && scalar.value <= 122)
            if isASCIIAlphaNumeric {
                if pendingHyphen, !slug.isEmpty {
                    slug.append("-")
                }
                slug.unicodeScalars.append(scalar)
                pendingHyphen = false
            } else {
                pendingHyphen = true
            }
        }
        if slug.isEmpty {
            slug = "section"
        }
        let count = (headingCounts[slug] ?? 0) + 1
        headingCounts[slug] = count
        return count == 1 ? slug : "\(slug)-\(count)"
    }

    private func stripInlineMarkdown(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"!?\[([^\]]+)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        for token in ["`", "*", "_", "~"] {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        return compact.count >= 3 && (Set(compact) == ["-"] || Set(compact) == ["*"])
    }

    private func isUnorderedListItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ")
    }

    private func orderedListItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: "."),
              dot != line.startIndex,
              line.index(after: dot) < line.endIndex,
              line[line.index(after: dot)] == " ",
              line[..<dot].allSatisfy(\.isNumber)
        else {
            return nil
        }
        return String(line[line.index(dot, offsetBy: 2)...])
    }

    private func isTableDelimiter(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else {
            return false
        }
        return cells.allSatisfy { cell in
            let compact = cell.trimmingCharacters(in: .whitespaces)
            return compact.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private func splitTableRow(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") {
            text.removeFirst()
        }
        if text.hasSuffix("|") {
            text.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in text {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
                current.append(character)
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private func renderTable(headers: [String], rows: [[String]]) -> String {
        let columnCount = headers.count
        let normalizedRows = rows.map { row -> [String] in
            if row.count == columnCount {
                return row
            }
            if row.count < columnCount {
                return row + Array(repeating: "", count: columnCount - row.count)
            }
            return Array(row.prefix(columnCount))
        }
        let headerHTML = headers.map { "      <th scope=\"col\">\(renderInline($0))</th>" }
            .joined(separator: "\n")
        let rowsHTML = normalizedRows.map { row in
            "    <tr>\n"
                + row.map { "      <td>\(renderInline($0))</td>" }.joined(separator: "\n")
                + "\n    </tr>"
        }.joined(separator: "\n")
        return """
        <table>
          <thead>
            <tr>
        \(headerHTML)
            </tr>
          </thead>
          <tbody>
        \(rowsHTML)
          </tbody>
        </table>
        """
    }

    private func renderInline(_ text: String) -> String {
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "`",
               let closing = text[text.index(after: index)...].firstIndex(of: "`")
            {
                let content = text[text.index(after: index)..<closing]
                output += "<code>\(escapeHTML(String(content)))</code>"
                index = text.index(after: closing)
                continue
            }

            if text[index] == "[",
               let closingBracket = text[index...].firstIndex(of: "]"),
               text.index(after: closingBracket) < text.endIndex,
               text[text.index(after: closingBracket)] == "(",
               let closingParenthesis = text[text.index(closingBracket, offsetBy: 2)...]
                .firstIndex(of: ")")
            {
                let label = String(text[text.index(after: index)..<closingBracket])
                let destinationStart = text.index(closingBracket, offsetBy: 2)
                let destination = String(text[destinationStart..<closingParenthesis])
                output += "<a href=\"\(escapeAttribute(rewriteLocalLink(destination)))\">"
                    + escapeHTML(label)
                    + "</a>"
                index = text.index(after: closingParenthesis)
                continue
            }

            output += escapeHTML(String(text[index]))
            index = text.index(after: index)
        }
        return output
    }

    private func rewriteLocalLink(_ destination: String) -> String {
        guard !destination.hasPrefix("#"),
              !destination.hasPrefix("/"),
              !destination.hasPrefix("//"),
              !destination.contains("://"),
              !destination.lowercased().hasPrefix("mailto:")
        else {
            return destination
        }

        let fragmentParts = destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let queryParts = String(fragmentParts[0])
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var path = String(queryParts[0])
        if path.lowercased().hasSuffix(".md") {
            path = String(path.dropLast(3)) + ".html"
        }
        if queryParts.count == 2 {
            path += "?" + queryParts[1]
        }
        if fragmentParts.count == 2 {
            path += "#" + fragmentParts[1]
        }
        return path
    }
}

private struct ProcessResult {
    let status: Int32
    let stdout: Data
    let stderr: String
}

private func run(
    executable: String,
    arguments: [String],
    currentDirectory: URL? = nil
) throws -> ProcessResult {
    let fileManager = FileManager.default
    let identifier = UUID().uuidString
    let stdoutURL = fileManager.temporaryDirectory
        .appendingPathComponent("tracker-free-docs-parity-\(identifier).stdout")
    let stderrURL = fileManager.temporaryDirectory
        .appendingPathComponent("tracker-free-docs-parity-\(identifier).stderr")
    guard fileManager.createFile(atPath: stdoutURL.path, contents: nil),
          fileManager.createFile(atPath: stderrURL.path, contents: nil)
    else {
        throw ParityFailure("Could not create temporary process-output files.")
    }
    defer {
        try? fileManager.removeItem(at: stdoutURL)
        try? fileManager.removeItem(at: stderrURL)
    }

    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle
    try process.run()
    process.waitUntilExit()
    try stdoutHandle.close()
    try stderrHandle.close()
    let stdoutData = try Data(contentsOf: stdoutURL)
    let stderrData = try Data(contentsOf: stderrURL)
    return ProcessResult(
        status: process.terminationStatus,
        stdout: stdoutData,
        stderr: String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    )
}

private func repositoryRoot(from override: String?) throws -> URL {
    if let override {
        let root = URL(fileURLWithPath: override).standardizedFileURL
        let result = try run(
            executable: "/usr/bin/git",
            arguments: ["-C", root.path, "rev-parse", "--show-toplevel"]
        )
        guard result.status == 0,
              let path = String(data: result.stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            throw ParityFailure("\(root.path) is not a Git worktree.")
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    let result = try run(
        executable: "/usr/bin/git",
        arguments: ["rev-parse", "--show-toplevel"]
    )
    guard result.status == 0,
          let path = String(data: result.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !path.isEmpty
    else {
        throw ParityFailure("Run DocsParity from inside a Git worktree.")
    }
    return URL(fileURLWithPath: path).standardizedFileURL
}

private func escapeHTML(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

private func escapeAttribute(_ text: String) -> String {
    escapeHTML(text).replacingOccurrences(of: "'", with: "&#39;")
}

do {
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard let first = arguments.first, let mode = Mode(rawValue: first) else {
        throw ParityFailure(
            "Usage: swift Scripts/DocsParity.swift (--generate|--check) [--root PATH]"
        )
    }
    arguments.removeFirst()

    var rootOverride: String?
    if !arguments.isEmpty {
        guard arguments.count == 2, arguments[0] == "--root" else {
            throw ParityFailure(
                "Usage: swift Scripts/DocsParity.swift (--generate|--check) [--root PATH]"
            )
        }
        rootOverride = arguments[1]
    }

    let root = try repositoryRoot(from: rootOverride)
    try DocsParity(root: root).run(mode: mode)
} catch {
    FileHandle.standardError.write(Data("DocsParity error: \(error)\n".utf8))
    exit(1)
}
