import Foundation

/// Represents a single line in a diff.
struct DiffLine: Identifiable, Equatable {
    enum LineType: Equatable {
        case context
        case addition
        case deletion
    }

    let id = UUID()
    let text: String
    let type: LineType
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

/// Represents a hunk (contiguous block of changes) in a diff.
struct DiffHunk: Identifiable, Equatable {
    let id = UUID()
    let header: String
    let lines: [DiffLine]
}

/// Represents the diff for a single file.
struct FileDiff: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let hunks: [DiffHunk]
    let additions: Int
    let deletions: Int

    /// Returns true if any addition or deletion line contains the search term (case-insensitive).
    func containsSearchTerm(_ term: String) -> Bool {
        guard !term.isEmpty else { return true }
        let lowered = term.lowercased()
        return hunks.contains { hunk in
            hunk.lines.contains { line in
                (line.type == .addition || line.type == .deletion) &&
                line.text.lowercased().contains(lowered)
            }
        }
    }

    /// Returns all matching (hunkIndex, lineIndex) pairs for a search term within changed lines.
    func matchingLineIndices(for term: String) -> [(hunkIndex: Int, lineIndex: Int)] {
        guard !term.isEmpty else { return [] }
        let lowered = term.lowercased()
        var results: [(hunkIndex: Int, lineIndex: Int)] = []
        for (hi, hunk) in hunks.enumerated() {
            for (li, line) in hunk.lines.enumerated() {
                if (line.type == .addition || line.type == .deletion),
                   line.text.lowercased().contains(lowered) {
                    results.append((hunkIndex: hi, lineIndex: li))
                }
            }
        }
        return results
    }
}
