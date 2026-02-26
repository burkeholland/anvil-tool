import Foundation

/// Gutter indicator for a line in the source view.
enum GutterChangeKind {
    case added
    case modified
    case deleted  // marker at a line position where content was removed
}

/// A single line in a diff hunk.
struct DiffLine: Identifiable {
    enum Kind {
        case context
        case addition
        case deletion
        case hunkHeader
    }

    let id: Int
    let kind: Kind
    let text: String
    /// Line number in the old file (nil for additions and hunk headers).
    let oldLineNumber: Int?
    /// Line number in the new file (nil for deletions and hunk headers).
    let newLineNumber: Int?
    /// Character ranges within `text` that represent the actual inline change.
    /// Non-nil only for addition/deletion lines that are part of a matched pair.
    var inlineHighlights: [Range<Int>]?
}

/// A contiguous hunk of changes.
struct DiffHunk: Identifiable {
    let id: Int
    let header: String
    var lines: [DiffLine]
}

/// Parsed representation of a unified diff for a single file.
struct FileDiff: Identifiable {
    let id: String // file path
    let oldPath: String
    let newPath: String
    var hunks: [DiffHunk]
    /// True when the new file content does not end with a newline (synthetic diffs only).
    var noTrailingNewline: Bool = false

    var additionCount: Int {
        hunks.flatMap(\.lines).filter { $0.kind == .addition }.count
    }

    var deletionCount: Int {
        hunks.flatMap(\.lines).filter { $0.kind == .deletion }.count
    }
}

/// Parses unified diff output (from `git diff`) into structured data.
enum DiffParser {

    /// Parse the full output of `git diff` which may contain multiple file diffs.
    static func parse(_ output: String) -> [FileDiff] {
        let lines = output.components(separatedBy: "\n")
        var fileDiffs: [FileDiff] = []
        var i = 0

        while i < lines.count {
            // Look for "diff --git" header
            guard lines[i].hasPrefix("diff --git ") else {
                i += 1
                continue
            }

            let (fileDiff, nextIndex) = parseFileDiff(lines: lines, startIndex: i)
            if let fileDiff = fileDiff {
                fileDiffs.append(fileDiff)
            }
            i = nextIndex
        }

        // Post-process: compute inline highlights for matched deletion→addition pairs
        for fi in 0..<fileDiffs.count {
            for hi in 0..<fileDiffs[fi].hunks.count {
                computeInlineHighlights(for: &fileDiffs[fi].hunks[hi].lines)
            }
        }

        return fileDiffs
    }

    /// Parse a single file's diff from `git diff -- <file>`.
    static func parseSingleFile(_ output: String) -> FileDiff? {
        let diffs = parse(output)
        return diffs.first
    }

    // MARK: - Private

    private static func parseFileDiff(lines: [String], startIndex: Int) -> (FileDiff?, Int) {
        var i = startIndex
        let diffHeader = lines[i]

        // Extract paths from "diff --git a/path b/path"
        let (oldPath, newPath) = extractPaths(from: diffHeader)
        i += 1

        // Skip metadata lines (index, ---/+++ headers, mode changes)
        while i < lines.count && !lines[i].hasPrefix("@@") && !lines[i].hasPrefix("diff --git ") {
            i += 1
        }

        // Parse hunks
        var hunks: [DiffHunk] = []
        var hunkId = 0
        var lineId = 0

        while i < lines.count && lines[i].hasPrefix("@@") {
            let hunkHeader = lines[i]
            let (oldStart, newStart) = parseHunkHeader(hunkHeader)
            var hunkLines: [DiffLine] = []
            var oldLine = oldStart
            var newLine = newStart

            // Add the header as a line
            hunkLines.append(DiffLine(
                id: lineId, kind: .hunkHeader, text: hunkHeader,
                oldLineNumber: nil, newLineNumber: nil
            ))
            lineId += 1
            i += 1

            // Parse lines until next hunk or next file
            while i < lines.count && !lines[i].hasPrefix("@@") && !lines[i].hasPrefix("diff --git ") {
                let line = lines[i]

                if line.hasPrefix("+") {
                    hunkLines.append(DiffLine(
                        id: lineId, kind: .addition, text: String(line.dropFirst()),
                        oldLineNumber: nil, newLineNumber: newLine
                    ))
                    newLine += 1
                } else if line.hasPrefix("-") {
                    hunkLines.append(DiffLine(
                        id: lineId, kind: .deletion, text: String(line.dropFirst()),
                        oldLineNumber: oldLine, newLineNumber: nil
                    ))
                    oldLine += 1
                } else if line.hasPrefix(" ") {
                    let text = String(line.dropFirst())
                    hunkLines.append(DiffLine(
                        id: lineId, kind: .context, text: text,
                        oldLineNumber: oldLine, newLineNumber: newLine
                    ))
                    oldLine += 1
                    newLine += 1
                } else if line.hasPrefix("\\") {
                    // "\ No newline at end of file" — skip
                    i += 1
                    lineId += 1
                    continue
                } else {
                    break
                }

                lineId += 1
                i += 1
            }

            hunks.append(DiffHunk(id: hunkId, header: hunkHeader, lines: hunkLines))
            hunkId += 1
        }

        guard !hunks.isEmpty else {
            return (nil, i)
        }

        let fileDiff = FileDiff(
            id: newPath,
            oldPath: oldPath,
            newPath: newPath,
            hunks: hunks
        )
        return (fileDiff, i)
    }

    /// Extract old and new paths from "diff --git a/foo b/foo".
    private static func extractPaths(from header: String) -> (String, String) {
        // "diff --git a/path/to/file b/path/to/file"
        let stripped = header.replacingOccurrences(of: "diff --git ", with: "")
        let parts = stripped.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return ("", "") }

        let old = String(parts[0]).hasPrefix("a/") ? String(parts[0].dropFirst(2)) : String(parts[0])
        let new = String(parts[1]).hasPrefix("b/") ? String(parts[1].dropFirst(2)) : String(parts[1])
        return (old, new)
    }

    /// Parse "@@ -old,count +new,count @@" into (oldStart, newStart).
    static func parseHunkHeader(_ header: String) -> (Int, Int) {
        // Match @@ -<old>,<count> +<new>,<count> @@
        let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)) else {
            return (1, 1)
        }

        let oldStart = Int(header[Range(match.range(at: 1), in: header)!]) ?? 1
        let newStart = Int(header[Range(match.range(at: 2), in: header)!]) ?? 1
        return (oldStart, newStart)
    }

    // MARK: - Inline Highlighting

    /// Post-processes a hunk's lines to compute inline (character-level) highlights
    /// for matched deletion→addition pairs.
    static func computeInlineHighlights(for lines: inout [DiffLine]) {
        var i = 0
        while i < lines.count {
            guard lines[i].kind == .deletion else {
                i += 1
                continue
            }

            var deletionIndices: [Int] = []
            while i < lines.count && lines[i].kind == .deletion {
                deletionIndices.append(i)
                i += 1
            }

            var additionIndices: [Int] = []
            while i < lines.count && lines[i].kind == .addition {
                additionIndices.append(i)
                i += 1
            }

            let pairCount = min(deletionIndices.count, additionIndices.count)
            for p in 0..<pairCount {
                let delIdx = deletionIndices[p]
                let addIdx = additionIndices[p]
                let (delHL, addHL) = computeCharDiff(
                    old: lines[delIdx].text,
                    new: lines[addIdx].text
                )
                if !delHL.isEmpty { lines[delIdx].inlineHighlights = delHL }
                if !addHL.isEmpty { lines[addIdx].inlineHighlights = addHL }
            }
        }
    }

    /// Computes word-level diff between two strings using a Longest Common Subsequence
    /// algorithm on whitespace-split tokens. Changed tokens are returned as character
    /// ranges within the original strings, with adjacent changed tokens merged into a
    /// single range. Falls back to character-level prefix/suffix diff when the two
    /// strings share no tokens in common (e.g. single-token lines that differ entirely).
    static func computeCharDiff(old: String, new: String) -> ([Range<Int>], [Range<Int>]) {
        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)

        let lcsIndices = lcsTokenIndices(old: oldTokens.map(\.text), new: newTokens.map(\.text))
        if !lcsIndices.isEmpty {
            let oldMatched = Set(lcsIndices.map(\.0))
            let newMatched = Set(lcsIndices.map(\.1))
            return (
                charRanges(for: oldTokens, excluding: oldMatched),
                charRanges(for: newTokens, excluding: newMatched)
            )
        }

        // No tokens in common — fall back to character-level prefix/suffix diff so that
        // single-token changes like "foo()" → "foo(bar)" still get a useful highlight.
        let oldChars = Array(old)
        let newChars = Array(new)

        var prefixLen = 0
        while prefixLen < oldChars.count && prefixLen < newChars.count
              && oldChars[prefixLen] == newChars[prefixLen] {
            prefixLen += 1
        }

        var suffixLen = 0
        while suffixLen < (oldChars.count - prefixLen)
              && suffixLen < (newChars.count - prefixLen)
              && oldChars[oldChars.count - 1 - suffixLen] == newChars[newChars.count - 1 - suffixLen] {
            suffixLen += 1
        }

        guard prefixLen > 0 || suffixLen > 0 else { return ([], []) }

        let oldChangeStart = prefixLen
        let oldChangeEnd   = oldChars.count - suffixLen
        let newChangeStart = prefixLen
        let newChangeEnd   = newChars.count - suffixLen

        var oldRanges: [Range<Int>] = []
        var newRanges: [Range<Int>] = []
        if oldChangeEnd > oldChangeStart { oldRanges.append(oldChangeStart..<oldChangeEnd) }
        if newChangeEnd > newChangeStart { newRanges.append(newChangeStart..<newChangeEnd) }
        return (oldRanges, newRanges)
    }

    // MARK: - Word-level diff helpers

    /// A whitespace-delimited token together with its character range in the source string.
    struct WordToken {
        let text: String
        let range: Range<Int>
    }

    /// Splits `s` into non-whitespace tokens, recording each token's character range.
    static func tokenize(_ s: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var charOffset = 0
        var idx = s.startIndex

        while idx < s.endIndex {
            // Skip whitespace
            while idx < s.endIndex && s[idx].isWhitespace {
                s.formIndex(after: &idx)
                charOffset += 1
            }
            guard idx < s.endIndex else { break }

            let tokenStart = charOffset
            let startIdx = idx
            while idx < s.endIndex && !s[idx].isWhitespace {
                s.formIndex(after: &idx)
                charOffset += 1
            }
            tokens.append(WordToken(text: String(s[startIdx..<idx]), range: tokenStart..<charOffset))
        }
        return tokens
    }

    /// Returns `(oldIndex, newIndex)` pairs that form the LCS of two token arrays.
    static func lcsTokenIndices(old: [String], new: [String]) -> [(Int, Int)] {
        let m = old.count, n = new.count
        guard m > 0, n > 0 else { return [] }

        // Build DP table
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if old[i - 1] == new[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrace to recover matching index pairs
        var result: [(Int, Int)] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if old[i - 1] == new[j - 1] {
                result.append((i - 1, j - 1))
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }

    /// Merges contiguous unmatched tokens into consolidated character ranges.
    static func charRanges(for tokens: [WordToken], excluding matched: Set<Int>) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var runStart: Int? = nil
        var runEnd = 0

        for (i, token) in tokens.enumerated() {
            if !matched.contains(i) {
                if runStart == nil { runStart = token.range.lowerBound }
                runEnd = token.range.upperBound
            } else if let start = runStart {
                ranges.append(start..<runEnd)
                runStart = nil
            }
        }
        if let start = runStart { ranges.append(start..<runEnd) }
        return ranges
    }

    // MARK: - Gutter Change Region Lookup

    /// A contiguous change region within a hunk, used for gutter diff popovers.
    struct ChangeRegion {
        let hunk: DiffHunk
        let fileDiff: FileDiff
        /// The deleted lines (old content) in this region.
        let deletedLines: [String]
        /// The added lines (new content) in this region.
        let addedLines: [String]
        /// New-file line numbers covered by this region's additions/modifications.
        let newLineRange: ClosedRange<Int>
    }

    /// Finds the change region containing the given new-file line number.
    /// Returns nil if the line is not part of any change.
    static func changeRegion(forLine lineNumber: Int, in diff: FileDiff) -> ChangeRegion? {
        for hunk in diff.hunks {
            let lines = hunk.lines
            var i = 0
            while i < lines.count {
                if lines[i].kind == .deletion {
                    // Collect contiguous deletions
                    let delStart = i
                    var deleted: [String] = []
                    while i < lines.count && lines[i].kind == .deletion {
                        deleted.append(lines[i].text)
                        i += 1
                    }
                    // Collect any immediately following additions
                    var added: [String] = []
                    var addLineNumbers: [Int] = []
                    while i < lines.count && lines[i].kind == .addition {
                        added.append(lines[i].text)
                        if let n = lines[i].newLineNumber { addLineNumbers.append(n) }
                        i += 1
                    }

                    if !addLineNumbers.isEmpty && addLineNumbers.contains(lineNumber) {
                        let range = addLineNumbers.min()!...addLineNumbers.max()!
                        return ChangeRegion(hunk: hunk, fileDiff: diff,
                                            deletedLines: deleted, addedLines: added,
                                            newLineRange: range)
                    }
                    // Pure deletion — check if the marker line matches
                    if addLineNumbers.isEmpty {
                        var markerLine: Int? = nil
                        for j in i..<lines.count {
                            if let n = lines[j].newLineNumber { markerLine = n; break }
                        }
                        if markerLine == nil {
                            for j in stride(from: delStart - 1, through: 0, by: -1) {
                                if let n = lines[j].newLineNumber { markerLine = n; break }
                            }
                        }
                        if let m = markerLine, m == lineNumber {
                            return ChangeRegion(hunk: hunk, fileDiff: diff,
                                                deletedLines: deleted, addedLines: [],
                                                newLineRange: m...m)
                        }
                    }
                } else if lines[i].kind == .addition {
                    // Pure addition (not preceded by deletions)
                    var added: [String] = []
                    var addLineNumbers: [Int] = []
                    while i < lines.count && lines[i].kind == .addition {
                        added.append(lines[i].text)
                        if let n = lines[i].newLineNumber { addLineNumbers.append(n) }
                        i += 1
                    }
                    if !addLineNumbers.isEmpty && addLineNumbers.contains(lineNumber) {
                        let range = addLineNumbers.min()!...addLineNumbers.max()!
                        return ChangeRegion(hunk: hunk, fileDiff: diff,
                                            deletedLines: [], addedLines: added,
                                            newLineRange: range)
                    }
                } else {
                    i += 1
                }
            }
        }
        return nil
    }

    // MARK: - Staged Hunk Detection

    /// Returns the set of hunk IDs in `combinedDiff` that are at least partially reflected
    /// in `stagedDiff` (i.e., share an overlapping old-file line range).
    /// Both diffs must be relative to the same base (HEAD) for the old-line numbers to be comparable.
    static func stagedHunkIDs(combinedDiff: FileDiff, stagedDiff: FileDiff) -> Set<Int> {
        // Build old-file line ranges for each staged hunk using the hunk header's old count.
        let stagedRanges: [ClosedRange<Int>] = stagedDiff.hunks.compactMap { oldLineRange(for: $0) }

        guard !stagedRanges.isEmpty else { return [] }

        var result = Set<Int>()
        for hunk in combinedDiff.hunks {
            guard let hunkRange = oldLineRange(for: hunk) else { continue }
            if stagedRanges.contains(where: { $0.overlaps(hunkRange) }) {
                result.insert(hunk.id)
            }
        }
        return result
    }

    /// Returns the old-file line range covered by a hunk's context and deletion lines,
    /// or `nil` if the hunk contains no such lines (e.g. a pure-addition hunk).
    private static func oldLineRange(for hunk: DiffHunk) -> ClosedRange<Int>? {
        let (oldStart, _) = parseHunkHeader(hunk.header)
        let oldCount = hunk.lines.filter { $0.kind == .deletion || $0.kind == .context }.count
        guard oldCount > 0 else { return nil }
        return oldStart...(oldStart + oldCount - 1)
    }

    // MARK: - Patch Reconstruction

    /// Reconstructs a valid unified diff patch for a single hunk, suitable for `git apply`.
    /// Uses standard `--- a/` and `+++ b/` headers which are correct for modified files.
    /// New-file and deleted-file diffs are not candidates for hunk-level staging.
    static func reconstructPatch(fileDiff: FileDiff, hunk: DiffHunk) -> String {
        var lines: [String] = []
        let isNewFile = fileDiff.oldPath == "/dev/null"
        let oldRef = isNewFile ? "/dev/null" : "a/\(fileDiff.oldPath)"
        let newRef = "b/\(fileDiff.newPath)"
        lines.append("diff --git a/\(fileDiff.newPath) \(newRef)")
        if isNewFile { lines.append("new file mode 100644") }
        lines.append("--- \(isNewFile ? "/dev/null" : oldRef)")
        lines.append("+++ \(newRef)")
        lines.append(hunk.header)

        for line in hunk.lines {
            switch line.kind {
            case .hunkHeader:
                continue
            case .context:
                lines.append(" \(line.text)")
            case .addition:
                lines.append("+\(line.text)")
            case .deletion:
                lines.append("-\(line.text)")
            }
        }

        var result = lines.joined(separator: "\n") + "\n"
        if fileDiff.noTrailingNewline {
            result += "\\ No newline at end of file\n"
        }
        return result
    }

    // MARK: - Gutter Change Map

    /// Computes a mapping from new-file line numbers to gutter indicators.
    /// Additions paired with preceding deletions are "modified" (replacement);
    /// pure additions are "added". Deletion-only regions produce a "deleted" marker
    /// at the nearest new-file line.
    static func gutterChanges(from diff: FileDiff) -> [Int: GutterChangeKind] {
        var result: [Int: GutterChangeKind] = [:]

        for hunk in diff.hunks {
            let lines = hunk.lines

            // Single pass: detect deletion→addition pairs structurally
            var i = 0
            while i < lines.count {
                if lines[i].kind == .deletion {
                    let delStart = i
                    while i < lines.count && lines[i].kind == .deletion {
                        i += 1
                    }
                    // Collect any immediately following additions (paired replacements)
                    let addStart = i
                    while i < lines.count && lines[i].kind == .addition {
                        i += 1
                    }
                    let addEnd = i

                    if addStart < addEnd {
                        // Paired: mark additions as modified
                        for j in addStart..<addEnd {
                            if let n = lines[j].newLineNumber {
                                result[n] = .modified
                            }
                        }
                    } else {
                        // Pure deletion — place marker at nearest new-file line
                        var markerLine: Int? = nil
                        for j in i..<lines.count {
                            if let n = lines[j].newLineNumber {
                                markerLine = n
                                break
                            }
                        }
                        if markerLine == nil {
                            for j in stride(from: delStart - 1, through: 0, by: -1) {
                                if let n = lines[j].newLineNumber {
                                    markerLine = n
                                    break
                                }
                            }
                        }
                        if let m = markerLine, result[m] == nil {
                            result[m] = .deleted
                        }
                    }
                } else if lines[i].kind == .addition {
                    // Pure addition (not preceded by deletions)
                    if let n = lines[i].newLineNumber, result[n] == nil {
                        result[n] = .added
                    }
                    i += 1
                } else {
                    i += 1
                }
            }
        }

        return result
    }
}
