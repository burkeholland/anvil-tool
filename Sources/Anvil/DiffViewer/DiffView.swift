import SwiftUI

/// Diff display mode — unified (interleaved) or side-by-side (split).
enum DiffViewMode: String, CaseIterable {
    case unified = "Unified"
    case sideBySide = "Side by Side"
}

/// Renders a diff with a toggle between unified and side-by-side modes.
struct DiffView: View {
    let diff: FileDiff
    var onStageHunk: ((DiffHunk) -> Void)?
    var onDiscardHunk: ((DiffHunk) -> Void)?
    @AppStorage("diffViewMode") private var mode: String = DiffViewMode.unified.rawValue

    private var viewMode: DiffViewMode {
        DiffViewMode(rawValue: mode) ?? .unified
    }

    var body: some View {
        switch viewMode {
        case .unified:
            UnifiedDiffView(diff: diff, mode: $mode, onStageHunk: onStageHunk, onDiscardHunk: onDiscardHunk)
        case .sideBySide:
            SideBySideDiffView(diff: diff, mode: $mode)
        }
    }
}

/// The original unified diff renderer, now extracted as its own view.
struct UnifiedDiffView: View {
    let diff: FileDiff
    @Binding var mode: String
    var onStageHunk: ((DiffHunk) -> Void)?
    var onDiscardHunk: ((DiffHunk) -> Void)?

    var body: some View {
        let highlights = DiffSyntaxHighlighter.highlight(diff: diff)
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                DiffStatsBar(diff: diff, mode: $mode)

                Divider()

                // Hunks
                ForEach(diff.hunks) { hunk in
                    DiffHunkView(
                        hunk: hunk,
                        syntaxHighlights: highlights,
                        onStage: onStageHunk.map { handler in { handler(hunk) } },
                        onDiscard: onDiscardHunk.map { handler in { handler(hunk) } }
                    )
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Shared stats bar with diff mode toggle, used by both unified and side-by-side views.
struct DiffStatsBar: View {
    let diff: FileDiff
    @Binding var mode: String

    var body: some View {
        HStack(spacing: 12) {
            Label("\(diff.additionCount) additions", systemImage: "plus")
                .foregroundStyle(.green)
            Label("\(diff.deletionCount) deletions", systemImage: "minus")
                .foregroundStyle(.red)

            Spacer()

            Picker("", selection: $mode) {
                ForEach(DiffViewMode.allCases, id: \.rawValue) { m in
                    Text(m.rawValue).tag(m.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct DiffHunkView: View {
    let hunk: DiffHunk
    var syntaxHighlights: [Int: AttributedString] = [:]
    var onStage: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onRequestFix: (() -> Void)?
    var isFocused: Bool = false
    @State private var isHovered = false

    private var hasActions: Bool {
        onStage != nil || onDiscard != nil || onRequestFix != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(hunk.lines) { line in
                if line.kind == .hunkHeader && hasActions {
                    DiffLineView(line: line, syntaxHighlight: syntaxHighlights[line.id])
                        .overlay(alignment: .trailing) {
                            hunkActions
                                .opacity(isHovered ? 1 : 0)
                        }
                        .onHover { hovering in
                            isHovered = hovering
                        }
                } else {
                    DiffLineView(line: line, syntaxHighlight: syntaxHighlights[line.id])
                }
            }
        }
        .overlay(alignment: .leading) {
            if isFocused {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: 3)
            }
        }
        .onHover { hovering in
            if hasActions { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var hunkActions: some View {
        HStack(spacing: 2) {
            if let onStage {
                Button { onStage() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
                .help("Stage this hunk")
            }
            if let onDiscard {
                Button { onDiscard() } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Discard this hunk")
            }
            if let onRequestFix {
                Button { onRequestFix() } label: {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .help("Request Fix for this hunk")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
        )
        .padding(.trailing, 8)
    }
}

struct DiffLineView: View {
    let line: DiffLine
    var syntaxHighlight: AttributedString?

    var body: some View {
        HStack(spacing: 0) {
            // Old line number
            Text(line.oldLineNumber.map { String($0) } ?? "")
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.tertiary)
                .font(.system(size: 11, design: .monospaced))

            // New line number
            Text(line.newLineNumber.map { String($0) } ?? "")
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.tertiary)
                .font(.system(size: 11, design: .monospaced))

            // Gutter marker
            Text(gutterMarker)
                .frame(width: 20, alignment: .center)
                .foregroundStyle(gutterColor)
                .font(.system(size: 12, design: .monospaced))

            // Content — syntax highlighted with optional inline highlights
            contentView
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: 20)
        .background(backgroundColor)
    }

    @ViewBuilder
    private var contentView: some View {
        if let syntax = syntaxHighlight {
            if let highlights = line.inlineHighlights, !highlights.isEmpty {
                Text(applyInlineHighlights(to: syntax, highlights: highlights))
            } else {
                Text(syntax)
            }
        } else if let highlights = line.inlineHighlights, !highlights.isEmpty {
            Text(highlightedContent(highlights))
        } else {
            Text(line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor)
        }
    }

    private func applyInlineHighlights(to syntax: AttributedString, highlights: [Range<Int>]) -> AttributedString {
        var result = syntax
        let charCount = result.characters.count
        for range in highlights {
            let clampedStart = max(0, range.lowerBound)
            let clampedEnd = min(charCount, range.upperBound)
            guard clampedStart < clampedEnd else { continue }

            let startIdx = result.index(result.startIndex, offsetByCharacters: clampedStart)
            let endIdx = result.index(result.startIndex, offsetByCharacters: clampedEnd)
            result[startIdx..<endIdx].backgroundColor = inlineHighlightColor
        }
        return result
    }

    private func highlightedContent(_ highlights: [Range<Int>]) -> AttributedString {
        let chars = Array(line.text)
        var result = AttributedString(line.text)
        result.font = .system(size: 12, design: .monospaced)
        result.foregroundColor = textNSColor

        for range in highlights {
            let clampedStart = max(0, range.lowerBound)
            let clampedEnd = min(chars.count, range.upperBound)
            guard clampedStart < clampedEnd else { continue }

            let startIdx = result.index(result.startIndex, offsetByCharacters: clampedStart)
            let endIdx = result.index(result.startIndex, offsetByCharacters: clampedEnd)
            result[startIdx..<endIdx].backgroundColor = inlineHighlightColor
        }

        return result
    }

    private var gutterMarker: String {
        switch line.kind {
        case .addition:   return "+"
        case .deletion:   return "-"
        case .hunkHeader: return "…"
        case .context:    return " "
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .addition:   return Color.green.opacity(0.1)
        case .deletion:   return Color.red.opacity(0.1)
        case .hunkHeader: return Color(nsColor: .controlBackgroundColor)
        case .context:    return .clear
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .addition:   return Color.green
        case .deletion:   return Color.red
        case .hunkHeader: return Color.secondary
        case .context:    return Color(nsColor: .textColor)
        }
    }

    private var gutterColor: Color {
        switch line.kind {
        case .addition:   return .green
        case .deletion:   return .red
        default:          return .secondary
        }
    }

    private var inlineHighlightColor: Color {
        switch line.kind {
        case .addition:   return Color.green.opacity(0.25)
        case .deletion:   return Color.red.opacity(0.25)
        default:          return .clear
        }
    }

    private var textNSColor: Color {
        textColor
    }
}
