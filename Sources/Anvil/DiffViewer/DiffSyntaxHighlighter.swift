import Foundation
import Highlightr

/// Computes syntax-highlighted AttributedStrings for diff lines.
/// Highlights are computed per-hunk (not per-line) so the highlighter
/// has proper language context for multi-line constructs.
enum DiffSyntaxHighlighter {

    private static let highlightr: Highlightr? = {
        let h = Highlightr()
        h?.setTheme(to: "atom-one-dark")
        return h
    }()

    // Cache keyed by diff ID to avoid redundant recomputation across SwiftUI body re-evaluations.
    private static var cache: [String: [Int: AttributedString]] = [:]
    private static let maxCacheEntries = 20

    /// Compute syntax highlights for all lines in a FileDiff.
    /// Returns a mapping from DiffLine.id to a syntax-colored AttributedString.
    static func highlight(diff: FileDiff) -> [Int: AttributedString] {
        if let cached = cache[diff.id] { return cached }

        guard let language = languageForPath(diff.newPath.isEmpty ? diff.oldPath : diff.newPath) else {
            return [:]
        }

        var result: [Int: AttributedString] = [:]
        for hunk in diff.hunks {
            let hunkResult = highlightHunk(hunk, language: language)
            result.merge(hunkResult) { _, new in new }
        }

        if cache.count >= maxCacheEntries { cache.removeAll() }
        cache[diff.id] = result
        return result
    }

    // MARK: - Per-hunk highlighting

    private static func highlightHunk(_ hunk: DiffHunk, language: String) -> [Int: AttributedString] {
        // Build old-side and new-side code blocks for context-aware highlighting.
        var oldLines: [(id: Int, text: String)] = []
        var newLines: [(id: Int, text: String)] = []

        for line in hunk.lines {
            switch line.kind {
            case .context:
                oldLines.append((line.id, line.text))
                newLines.append((line.id, line.text))
            case .deletion:
                oldLines.append((line.id, line.text))
            case .addition:
                newLines.append((line.id, line.text))
            case .hunkHeader:
                break
            }
        }

        let oldHighlighted = highlightBlock(oldLines.map(\.text), language: language)
        let newHighlighted = highlightBlock(newLines.map(\.text), language: language)

        var result: [Int: AttributedString] = [:]

        // New-side covers context + addition lines.
        for (i, item) in newLines.enumerated() where i < newHighlighted.count {
            result[item.id] = newHighlighted[i]
        }

        // Old-side fills in deletion lines (context already set above).
        for (i, item) in oldLines.enumerated() where i < oldHighlighted.count {
            if result[item.id] == nil {
                result[item.id] = oldHighlighted[i]
            }
        }

        return result
    }

    // MARK: - Block highlighting

    private static func highlightBlock(_ lines: [String], language: String) -> [AttributedString] {
        guard !lines.isEmpty, let highlightr = highlightr else { return [] }

        let block = lines.joined(separator: "\n")
        guard let highlighted = highlightr.highlight(block, as: language) else { return [] }

        return splitAttributedString(highlighted, expectedLines: lines.count)
    }

    /// Splits an NSAttributedString on newline characters into per-line
    /// SwiftUI AttributedStrings with background colors stripped.
    private static func splitAttributedString(
        _ attrStr: NSAttributedString,
        expectedLines: Int
    ) -> [AttributedString] {
        let nsString = attrStr.string as NSString
        var results: [AttributedString] = []
        var searchStart = 0

        for _ in 0..<expectedLines {
            guard searchStart <= nsString.length else { break }

            let remaining = NSRange(location: searchStart, length: nsString.length - searchStart)
            let newlineRange = nsString.range(of: "\n", range: remaining)

            let lineEnd = newlineRange.location != NSNotFound ? newlineRange.location : nsString.length
            let lineRange = NSRange(location: searchStart, length: lineEnd - searchStart)
            let lineNS = attrStr.attributedSubstring(from: lineRange)

            results.append(toSwiftUI(lineNS))

            searchStart = lineEnd + 1
        }

        return results
    }

    /// Converts an NSAttributedString to SwiftUI AttributedString, keeping
    /// syntax foreground colors but stripping backgrounds and normalizing font.
    private static func toSwiftUI(_ ns: NSAttributedString) -> AttributedString {
        var result = AttributedString(ns)
        if result.startIndex < result.endIndex {
            result[result.startIndex..<result.endIndex].font = .system(size: 12, design: .monospaced)
            result[result.startIndex..<result.endIndex].backgroundColor = nil
        }
        return result
    }

    // MARK: - Language detection

    static func languageForPath(_ path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        if let lang = extensionToLanguage[ext] { return lang }
        // Fallback for extensionless files like Dockerfile, Makefile
        let name = (path as NSString).lastPathComponent.lowercased()
        return filenameToLanguage[name]
    }

    private static let filenameToLanguage: [String: String] = [
        "dockerfile": "dockerfile",
        "makefile": "makefile",
        "gnumakefile": "makefile",
    ]

    private static let extensionToLanguage: [String: String] = [
        "swift": "swift", "js": "javascript", "jsx": "javascript",
        "ts": "typescript", "tsx": "typescript", "py": "python",
        "rb": "ruby", "rs": "rust", "go": "go",
        "java": "java", "kt": "kotlin", "c": "c", "h": "c",
        "cpp": "cpp", "cc": "cpp", "cs": "csharp",
        "m": "objectivec", "mm": "objectivec",
        "sh": "bash", "bash": "bash", "zsh": "bash",
        "json": "json", "yaml": "yaml", "yml": "yaml",
        "toml": "ini", "xml": "xml", "html": "xml",
        "css": "css", "scss": "scss", "sql": "sql",
        "md": "markdown", "dockerfile": "dockerfile", "makefile": "makefile",
        "r": "r", "lua": "lua", "php": "php", "pl": "perl",
        "ex": "elixir", "exs": "elixir", "hs": "haskell",
        "scala": "scala", "dart": "dart", "vim": "vim",
    ]
}
