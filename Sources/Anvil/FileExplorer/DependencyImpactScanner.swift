import Foundation

/// Scans project source files for import/reference relationships to modified files.
/// Results are stored in `FileTreeModel.impactedFiles` and refreshed after each
/// git status update (which is triggered by file-system change events).
enum DependencyImpactScanner {

    /// Source file extensions eligible for scanning.
    private static let sourceExtensions: Set<String> = [
        "swift", "js", "ts", "jsx", "tsx", "py", "go", "rs", "kt", "java"
    ]

    /// Directory names to skip during enumeration.
    private static let skippedDirs: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", "build", "dist"
    ]

    /// Pre-compiled regex matching the keywords `import` or `require` as whole words.
    private static let importKeywordRegex = try? NSRegularExpression(pattern: "\\b(import|require)\\b")

    /// Scans all source files under `rootURL` and returns a map of
    /// absolute file path → tooltip message for files that import or
    /// reference any of the given modified files.
    ///
    /// - Parameters:
    ///   - modifiedPaths: Absolute paths of modified (non-deleted) source files.
    ///   - rootURL: Project root directory — scanning is limited to this subtree.
    /// - Returns: `[absolutePath: tooltipMessage]` for indirectly impacted files.
    static func scan(modifiedPaths: [String], rootURL: URL) -> [String: String] {
        guard !modifiedPaths.isEmpty else { return [:] }

        // Build lookup: (stem, displayName) for modified source files only
        let modifiedEntries: [(stem: String, display: String)] = modifiedPaths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()
            guard sourceExtensions.contains(ext) else { return nil }
            let stem = url.deletingPathExtension().lastPathComponent
            guard !stem.isEmpty else { return nil }
            return (stem, url.lastPathComponent)
        }
        guard !modifiedEntries.isEmpty else { return [:] }

        let modifiedSet = Set(modifiedPaths)
        var result: [String: String] = [:]

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if skippedDirs.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let ext = fileURL.pathExtension.lowercased()
            guard sourceExtensions.contains(ext) else { continue }

            let absPath = fileURL.standardizedFileURL.path
            // Don't flag directly-modified files as impacted
            guard !modifiedSet.contains(absPath) else { continue }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            for entry in modifiedEntries where containsImport(content: content, stem: entry.stem) {
                result[absPath] = "Imports \(entry.display) (modified)"
                break
            }
        }

        return result
    }

    // MARK: - Private

    /// Returns true if `content` has an import/require line that references `stem`
    /// as a whole word.
    static func containsImport(content: String, stem: String) -> Bool {
        // Quick pre-check: stem must appear somewhere in the file
        guard content.contains(stem) else { return false }

        let stemPattern = "\\b" + NSRegularExpression.escapedPattern(for: stem) + "\\b"
        guard let stemRegex = try? NSRegularExpression(pattern: stemPattern) else { return false }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip pure comment lines
            guard !trimmed.hasPrefix("//"),
                  !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix("*"),
                  !trimmed.hasPrefix("/*") else { continue }

            // Strip trailing inline // comments so they don't produce false positives
            let codePart: String
            if let commentRange = trimmed.range(of: "//") {
                codePart = String(trimmed[..<commentRange.lowerBound])
            } else {
                codePart = trimmed
            }
            guard !codePart.isEmpty else { continue }

            // Only consider lines that contain import/require as whole words
            let codeRange = NSRange(codePart.startIndex..., in: codePart)
            guard importKeywordRegex?.firstMatch(in: codePart, range: codeRange) != nil else { continue }

            let stemRange = NSRange(codePart.startIndex..., in: codePart)
            if stemRegex.firstMatch(in: codePart, range: stemRange) != nil {
                return true
            }
        }
        return false
    }
}
