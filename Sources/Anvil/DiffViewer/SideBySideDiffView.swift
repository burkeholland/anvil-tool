import SwiftUI

/// A row in the side-by-side diff: an optional old line on the left
/// and an optional new line on the right. Context lines appear on both sides.
struct DiffRowPair: Identifiable {
    let id: Int
    let left: DiffLine?
    let right: DiffLine?
}

/// Converts hunk lines into paired rows for side-by-side rendering.
/// Deletions are placed on the left, additions on the right.
/// When a block of deletions is immediately followed by additions, they are
/// matched 1:1 so the reader can see old→new on the same row.
enum DiffRowPairer {
    static func pairLines(from hunks: [DiffHunk]) -> [DiffRowPair] {
        var rows: [DiffRowPair] = []
        var rowID = 0

        for hunk in hunks {
            let lines = hunk.lines
            var i = 0
            while i < lines.count {
                let line = lines[i]

                switch line.kind {
                case .hunkHeader:
                    rows.append(DiffRowPair(id: rowID, left: line, right: line))
                    rowID += 1
                    i += 1

                case .context:
                    rows.append(DiffRowPair(id: rowID, left: line, right: line))
                    rowID += 1
                    i += 1

                case .deletion:
                    // Collect consecutive deletions
                    var deletions: [DiffLine] = []
                    while i < lines.count && lines[i].kind == .deletion {
                        deletions.append(lines[i])
                        i += 1
                    }
                    // Collect consecutive additions that follow
                    var additions: [DiffLine] = []
                    while i < lines.count && lines[i].kind == .addition {
                        additions.append(lines[i])
                        i += 1
                    }
                    // Pair them
                    let maxCount = max(deletions.count, additions.count)
                    for p in 0..<maxCount {
                        let del = p < deletions.count ? deletions[p] : nil
                        let add = p < additions.count ? additions[p] : nil
                        rows.append(DiffRowPair(id: rowID, left: del, right: add))
                        rowID += 1
                    }

                case .addition:
                    // Standalone addition (no preceding deletion)
                    rows.append(DiffRowPair(id: rowID, left: nil, right: line))
                    rowID += 1
                    i += 1
                }
            }
        }

        return rows
    }
}

/// Renders a file diff in side-by-side (split) mode.
struct SideBySideDiffView: View {
    let diff: FileDiff
    @Binding var mode: String

    private var rows: [DiffRowPair] {
        DiffRowPairer.pairLines(from: diff.hunks)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                DiffStatsBar(diff: diff, mode: $mode)

                Divider()

                // Column headers
                HStack(spacing: 0) {
                    Text("Original")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)

                    Divider()
                        .frame(height: 16)

                    Text("Modified")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                Divider()

                // Rows
                ForEach(rows) { row in
                    SideBySideRowView(row: row)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct SideBySideRowView: View {
    let row: DiffRowPair

    var body: some View {
        if row.left?.kind == .hunkHeader {
            // Hunk header spans both columns
            HStack(spacing: 0) {
                Text(row.left?.text ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
            .frame(height: 22)
            .background(Color(nsColor: .controlBackgroundColor))
        } else {
            HStack(spacing: 0) {
                // Left (old) side
                SideBySideCellView(line: row.left, side: .old)

                // Center divider
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)

                // Right (new) side
                SideBySideCellView(line: row.right, side: .new)
            }
            .frame(height: 20)
        }
    }
}

enum DiffSide {
    case old, new
}

struct SideBySideCellView: View {
    let line: DiffLine?
    let side: DiffSide

    var body: some View {
        HStack(spacing: 0) {
            if let line = line {
                // Line number
                Text(lineNumber(line))
                    .frame(width: 40, alignment: .trailing)
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 11, design: .monospaced))

                // Gutter
                Text(gutterMarker(line))
                    .frame(width: 16, alignment: .center)
                    .foregroundStyle(gutterColor(line))
                    .font(.system(size: 12, design: .monospaced))

                // Content with inline highlights
                if let highlights = line.inlineHighlights, !highlights.isEmpty {
                    Text(highlightedContent(line, highlights: highlights))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Text(line.text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(textColor(line))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                // Empty placeholder for missing side
                Spacer()
                    .frame(minWidth: 56) // line number + gutter width
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(backgroundColor(line))
    }

    private func lineNumber(_ line: DiffLine) -> String {
        switch side {
        case .old:
            return line.oldLineNumber.map { String($0) } ?? (line.newLineNumber.map { String($0) } ?? "")
        case .new:
            return line.newLineNumber.map { String($0) } ?? (line.oldLineNumber.map { String($0) } ?? "")
        }
    }

    private func gutterMarker(_ line: DiffLine) -> String {
        switch line.kind {
        case .addition:   return "+"
        case .deletion:   return "-"
        case .context:    return " "
        case .hunkHeader: return "…"
        }
    }

    private func backgroundColor(_ line: DiffLine?) -> Color {
        guard let line = line else {
            return Color(nsColor: .textBackgroundColor).opacity(0.3)
        }
        switch line.kind {
        case .addition:   return Color.green.opacity(0.1)
        case .deletion:   return Color.red.opacity(0.1)
        case .context:    return .clear
        case .hunkHeader: return Color(nsColor: .controlBackgroundColor)
        }
    }

    private func textColor(_ line: DiffLine) -> Color {
        switch line.kind {
        case .addition:   return .green
        case .deletion:   return .red
        case .context:    return Color(nsColor: .textColor)
        case .hunkHeader: return .secondary
        }
    }

    private func gutterColor(_ line: DiffLine) -> Color {
        switch line.kind {
        case .addition:   return .green
        case .deletion:   return .red
        default:          return .secondary
        }
    }

    private func highlightedContent(_ line: DiffLine, highlights: [Range<Int>]) -> AttributedString {
        var result = AttributedString(line.text)
        result.font = .system(size: 12, design: .monospaced)
        result.foregroundColor = textColor(line)

        let chars = Array(line.text)
        for range in highlights {
            let clampedStart = max(0, range.lowerBound)
            let clampedEnd = min(chars.count, range.upperBound)
            guard clampedStart < clampedEnd else { continue }

            let startIdx = result.index(result.startIndex, offsetByCharacters: clampedStart)
            let endIdx = result.index(result.startIndex, offsetByCharacters: clampedEnd)
            result[startIdx..<endIdx].backgroundColor = inlineHighlightColor(line)
        }

        return result
    }

    private func inlineHighlightColor(_ line: DiffLine) -> Color {
        switch line.kind {
        case .addition:   return Color.green.opacity(0.25)
        case .deletion:   return Color.red.opacity(0.25)
        default:          return .clear
        }
    }
}
