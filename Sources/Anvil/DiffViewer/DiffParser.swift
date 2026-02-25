import Foundation

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

    /// Computes character-level diff between two strings by finding the common
    /// prefix and suffix, marking the middle as the changed region.
    static func computeCharDiff(old: String, new: String) -> ([Range<Int>], [Range<Int>]) {
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

        let oldChangeStart = prefixLen
        let oldChangeEnd = oldChars.count - suffixLen
        let newChangeStart = prefixLen
        let newChangeEnd = newChars.count - suffixLen

        // Only highlight if the change is partial (not the entire line)
        guard prefixLen > 0 || suffixLen > 0 else { return ([], []) }

        var oldRanges: [Range<Int>] = []
        var newRanges: [Range<Int>] = []
        if oldChangeEnd > oldChangeStart {
            oldRanges.append(oldChangeStart..<oldChangeEnd)
        }
        if newChangeEnd > newChangeStart {
            newRanges.append(newChangeStart..<newChangeEnd)
        }
        return (oldRanges, newRanges)
    }
}
