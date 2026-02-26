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
    var onUnstageHunk: ((DiffHunk) -> Void)?
    var onDiscardHunk: ((DiffHunk) -> Void)?
    /// IDs of hunks that are at least partially reflected in the staged index.
    var stagedHunkIDs: Set<Int> = []
    @AppStorage("diffViewMode") private var mode: String = DiffViewMode.unified.rawValue

    private var viewMode: DiffViewMode {
        DiffViewMode(rawValue: mode) ?? .unified
    }

    var body: some View {
        switch viewMode {
        case .unified:
            UnifiedDiffView(
                diff: diff,
                mode: $mode,
                onStageHunk: onStageHunk,
                onUnstageHunk: onUnstageHunk,
                onDiscardHunk: onDiscardHunk,
                stagedHunkIDs: stagedHunkIDs
            )
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
    var onUnstageHunk: ((DiffHunk) -> Void)?
    var onDiscardHunk: ((DiffHunk) -> Void)?
    var stagedHunkIDs: Set<Int> = []

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
                        isStaged: stagedHunkIDs.contains(hunk.id),
                        onStage: onStageHunk.map { handler in { handler(hunk) } },
                        onUnstage: onUnstageHunk.map { handler in { handler(hunk) } },
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
    /// Whether this hunk is at least partially reflected in the staged index.
    var isStaged: Bool = false
    var onStage: (() -> Void)?
    var onUnstage: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onRequestFix: (() -> Void)?
    var isFocused: Bool = false
    /// File path used to wire up inline annotation support. `nil` disables annotation UI.
    var filePath: String? = nil
    /// Map of new/old line numbers to annotation comments for this hunk's lines.
    var lineAnnotations: [Int: String] = [:]
    var onAddAnnotation: ((Int, String) -> Void)? = nil
    var onRemoveAnnotation: ((Int) -> Void)? = nil
    @State private var isHovered = false

    private var hasActions: Bool {
        onStage != nil || onUnstage != nil || onDiscard != nil || onRequestFix != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(hunk.lines) { line in
                if line.kind == .hunkHeader && hasActions {
                    DiffLineView(
                        line: line,
                        syntaxHighlight: syntaxHighlights[line.id],
                        hunkStagedTint: isStaged ? stagedHeaderTint : nil,
                        filePath: filePath,
                        onAddAnnotation: onAddAnnotation,
                        onRemoveAnnotation: removeHandler(for: line),
                        existingAnnotation: annotation(for: line)
                    )
                    .overlay(alignment: .trailing) {
                        hunkActions
                            .opacity(isHovered ? 1 : 0)
                    }
                    .onHover { hovering in
                        isHovered = hovering
                    }
                } else {
                    DiffLineView(
                        line: line,
                        syntaxHighlight: syntaxHighlights[line.id],
                        hunkStagedTint: isStaged ? stagedLineTint(for: line.kind) : nil,
                        filePath: filePath,
                        onAddAnnotation: onAddAnnotation,
                        onRemoveAnnotation: removeHandler(for: line),
                        existingAnnotation: annotation(for: line)
                    )
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

    /// Blue tint applied to the hunk header row when the hunk is staged.
    private var stagedHeaderTint: Color {
        Color.blue.opacity(0.12)
    }

    /// Returns a per-line staged tint colour, or nil when no tint should be applied.
    private func stagedLineTint(for kind: DiffLine.Kind) -> Color? {
        switch kind {
        case .addition: return Color.blue.opacity(0.08)
        case .deletion: return Color.purple.opacity(0.08)
        case .context:  return nil
        case .hunkHeader: return nil
        }
    }

    /// Returns the existing annotation comment for a diff line, or nil.
    private func annotation(for line: DiffLine) -> String? {
        guard let num = line.newLineNumber ?? line.oldLineNumber else { return nil }
        return lineAnnotations[num]
    }

    /// Returns a zero-argument remove closure bound to the line's number, or nil.
    private func removeHandler(for line: DiffLine) -> (() -> Void)? {
        guard let num = line.newLineNumber ?? line.oldLineNumber,
              let handler = onRemoveAnnotation else { return nil }
        return { handler(num) }
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
            if let onUnstage {
                Button { onUnstage() } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                .help("Unstage this hunk")
            }
            if let onDiscard {
                Button { onDiscard() } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13))
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
    /// Optional extra tint overlay applied when the containing hunk is staged.
    var hunkStagedTint: Color?
    /// File path for annotation support. `nil` disables annotation UI.
    var filePath: String? = nil
    /// Called with `(lineNumber, comment)` when the user saves an annotation.
    var onAddAnnotation: ((Int, String) -> Void)? = nil
    /// Called when the user removes an existing annotation for this line.
    var onRemoveAnnotation: (() -> Void)? = nil
    /// Existing annotation comment for this line, if any.
    var existingAnnotation: String? = nil

    @State private var isHovered = false
    @State private var showAnnotationPopover = false
    @State private var annotationDraft = ""

    private var annotationLineNumber: Int? {
        line.newLineNumber ?? line.oldLineNumber
    }

    private var canAnnotate: Bool {
        filePath != nil && onAddAnnotation != nil
            && annotationLineNumber != nil
            && line.kind != .hunkHeader
    }

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
        .overlay {
            if let tint = hunkStagedTint {
                tint
            }
        }
        // Yellow left-edge bar when an annotation is attached to this line
        .overlay(alignment: .leading) {
            if existingAnnotation != nil {
                Rectangle()
                    .fill(Color.yellow.opacity(0.85))
                    .frame(width: 3)
            }
        }
        // Trailing annotation button — visible on hover or when annotation exists
        .overlay(alignment: .trailing) {
            if canAnnotate && (isHovered || existingAnnotation != nil) {
                annotationButton
            }
        }
        .onHover { hovering in
            if canAnnotate { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var annotationButton: some View {
        Button {
            annotationDraft = existingAnnotation ?? ""
            showAnnotationPopover = true
        } label: {
            Image(systemName: existingAnnotation != nil ? "note.text" : "note.text.badge.plus")
                .font(.system(size: 10))
                .foregroundStyle(existingAnnotation != nil ? Color.yellow : Color.secondary.opacity(0.5))
        }
        .buttonStyle(.borderless)
        .help(existingAnnotation ?? "Add inline annotation")
        .popover(isPresented: $showAnnotationPopover, arrowEdge: .trailing) {
            if let lineNum = annotationLineNumber {
                AnnotationPopoverView(
                    lineNumber: lineNum,
                    draft: $annotationDraft,
                    hasExisting: existingAnnotation != nil,
                    onSubmit: { comment in
                        onAddAnnotation?(lineNum, comment)
                        showAnnotationPopover = false
                    },
                    onRemove: onRemoveAnnotation.map { handler in
                        { handler(); showAnnotationPopover = false }
                    },
                    onCancel: { showAnnotationPopover = false }
                )
            }
        }
        .padding(.trailing, 4)
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

/// A small popover for adding, editing, or removing an inline diff annotation.
struct AnnotationPopoverView: View {
    let lineNumber: Int
    @Binding var draft: String
    var hasExisting: Bool
    var onSubmit: (String) -> Void
    var onRemove: (() -> Void)?
    var onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Line \(lineNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Add note (e.g. wrong variable name)…", text: $draft)
                .font(.system(size: 12))
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .focused($isFocused)
                .onSubmit { submit() }
                .onKeyPress(.escape) { onCancel(); return .handled }

            HStack(spacing: 6) {
                Button(hasExisting ? "Update" : "Add Note") { submit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if hasExisting, let onRemove {
                    Button("Remove") { onRemove() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(.red)
                }

                Button("Cancel") { onCancel() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .onAppear { isFocused = true }
    }

    private func submit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
    }
}
