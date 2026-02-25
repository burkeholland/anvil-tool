import SwiftUI

/// Renders the diff lines for a single file, with optional search-term highlighting.
struct DiffView: View {
    let fileDiff: FileDiff
    var searchTerm: String = ""
    var highlightedMatch: (hunkIndex: Int, lineIndex: Int)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(fileDiff.hunks.enumerated()), id: \.offset) { hunkIndex, hunk in
                // Hunk header
                Text(hunk.header)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))

                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { lineIndex, line in
                    let isCurrentMatch = highlightedMatch.map {
                        $0.hunkIndex == hunkIndex && $0.lineIndex == lineIndex
                    } ?? false

                    DiffLineRow(
                        line: line,
                        searchTerm: searchTerm,
                        isCurrentMatch: isCurrentMatch
                    )
                    .id(lineAnchor(hunkIndex: hunkIndex, lineIndex: lineIndex))
                }
            }
        }
    }

    /// Stable identifier for scroll-to-match.
    func lineAnchor(hunkIndex: Int, lineIndex: Int) -> String {
        "\(fileDiff.id)-\(hunkIndex)-\(lineIndex)"
    }
}

// MARK: - DiffLineRow

/// A single diff line with optional search-term highlighting.
struct DiffLineRow: View {
    let line: DiffLine
    var searchTerm: String = ""
    var isCurrentMatch: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Line numbers
            Group {
                Text(line.oldLineNumber.map(String.init) ?? "")
                    .frame(width: 40, alignment: .trailing)
                Text(line.newLineNumber.map(String.init) ?? "")
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.trailing, 4)

            // Prefix character
            Text(prefixCharacter)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(prefixColor)
                .frame(width: 14, alignment: .center)

            // Line content with search highlighting
            highlightedText
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(rowBackground)
    }

    private var prefixCharacter: String {
        switch line.type {
        case .addition: return "+"
        case .deletion: return "-"
        case .context: return " "
        }
    }

    private var prefixColor: Color {
        switch line.type {
        case .addition: return .green
        case .deletion: return .red
        case .context: return .secondary
        }
    }

    private var rowBackground: Color {
        if isCurrentMatch {
            return .yellow.opacity(0.25)
        }
        switch line.type {
        case .addition: return .green.opacity(0.08)
        case .deletion: return .red.opacity(0.08)
        case .context: return .clear
        }
    }

    @ViewBuilder
    private var highlightedText: some View {
        if searchTerm.isEmpty {
            Text(line.text)
        } else {
            Text(buildHighlightedString())
        }
    }

    /// Builds an AttributedString with highlighted search matches.
    private func buildHighlightedString() -> AttributedString {
        var result = AttributedString(line.text)
        guard !searchTerm.isEmpty else { return result }

        let content = line.text
        let searchLowered = searchTerm.lowercased()
        let contentLowered = content.lowercased()

        var searchStart = contentLowered.startIndex
        while let range = contentLowered.range(of: searchLowered, range: searchStart..<contentLowered.endIndex) {
            // Convert String range to AttributedString range
            let offset = content.distance(from: content.startIndex, to: range.lowerBound)
            let length = content.distance(from: range.lowerBound, to: range.upperBound)

            let attrStart = result.index(result.startIndex, offsetByCharacters: offset)
            let attrEnd = result.index(attrStart, offsetByCharacters: length)

            result[attrStart..<attrEnd].backgroundColor = .yellow.opacity(0.4)
            result[attrStart..<attrEnd].foregroundColor = .black

            searchStart = range.upperBound
        }

        return result
    }
}
