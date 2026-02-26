import SwiftUI

// MARK: - Context Collapse Helpers

/// A contiguous segment of lines within a hunk for collapsed-context rendering.
private struct HunkSection: Identifiable {
    enum Kind { case normal, collapsible }
    let id: Int    // first line's id — unique within a parsed diff
    let kind: Kind
    let lines: [DiffLine]
}

/// Splits a hunk's line array into display sections. Consecutive `.context` runs whose
/// length equals or exceeds `collapseThreshold` become `.collapsible` sections; shorter
/// runs are returned as `.normal` sections alongside non-context lines.
private func makeHunkSections(_ lines: [DiffLine], collapseThreshold: Int = 7) -> [HunkSection] {
    var sections: [HunkSection] = []
    var pending: [DiffLine] = []

    func flush() {
        guard !pending.isEmpty else { return }
        sections.append(HunkSection(id: pending[0].id, kind: .normal, lines: pending))
        pending.removeAll()
    }

    var i = 0
    while i < lines.count {
        if lines[i].kind == .context {
            var run: [DiffLine] = []
            while i < lines.count && lines[i].kind == .context {
                run.append(lines[i])
                i += 1
            }
            flush()
            let kind: HunkSection.Kind = run.count >= collapseThreshold ? .collapsible : .normal
            sections.append(HunkSection(id: run[0].id, kind: kind, lines: run))
        } else {
            pending.append(lines[i])
            i += 1
        }
    }
    flush()
    return sections
}

// MARK: -

/// Diff display mode — unified (interleaved) or side-by-side (split).
enum DiffViewMode: String, CaseIterable {
    case unified = "Unified"
    case sideBySide = "Side by Side"

    /// Returns the opposite mode.
    var toggled: DiffViewMode {
        self == .unified ? .sideBySide : .unified
    }
}

/// Renders a diff with a toggle between unified and side-by-side modes.
struct DiffView: View {
    let diff: FileDiff
    var onStageHunk: ((DiffHunk) -> Void)?
    var onUnstageHunk: ((DiffHunk) -> Void)?
    var onDiscardHunk: ((DiffHunk) -> Void)?
    /// IDs of hunks that are at least partially reflected in the staged index.
    var stagedHunkIDs: Set<Int> = []
    /// Called with the new-file start line when the user taps "Show in Preview" on a hunk.
    var onShowInPreview: ((Int) -> Void)?
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
                stagedHunkIDs: stagedHunkIDs,
                onShowInPreview: onShowInPreview
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
    /// Called with the new-file start line when the user taps "Show in Preview" on a hunk.
    var onShowInPreview: ((Int) -> Void)?

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
                        onDiscard: onDiscardHunk.map { handler in { handler(hunk) } },
                        onShowInPreview: onShowInPreview.map { handler in
                            { handler(hunk.newFileStartLine ?? 1) }
                        }
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
    @AppStorage("diffContextExpanded") private var contextExpanded = false

    var body: some View {
        HStack(spacing: 12) {
            Label("\(diff.additionCount) additions", systemImage: "plus")
                .foregroundStyle(.green)
            Label("\(diff.deletionCount) deletions", systemImage: "minus")
                .foregroundStyle(.red)

            Spacer()

            Button {
                contextExpanded.toggle()
            } label: {
                Image(systemName: contextExpanded ? "eye.slash" : "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(contextExpanded ? "Collapse context lines" : "Expand all context lines")

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
    /// Called with the fully-composed prompt string (including code context) when the user
    /// submits the hunk-level "Fix this" popover.
    var onRequestFix: ((String) -> Void)?
    var onShowInPreview: (() -> Void)?
    var isFocused: Bool = false
    /// File path used to wire up inline annotation support. `nil` disables annotation UI.
    var filePath: String? = nil
    /// Map of new/old line numbers to annotation comments for this hunk's lines.
    var lineAnnotations: [Int: String] = [:]
    var onAddAnnotation: ((Int, String) -> Void)? = nil
    var onRemoveAnnotation: ((Int) -> Void)? = nil
    @State private var isHovered = false
    @State private var showFixPopover = false

    private var hasActions: Bool {
        onStage != nil || onUnstage != nil || onDiscard != nil || onRequestFix != nil || onShowInPreview != nil
    }

    var body: some View {
        let sections = makeHunkSections(hunk.lines)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                sectionView(for: section)
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
    private func sectionView(for section: HunkSection) -> some View {
        if section.kind == .collapsible {
            CollapsibleContextRunView(
                lines: section.lines,
                syntaxHighlights: syntaxHighlights,
                filePath: filePath,
                lineAnnotations: lineAnnotations,
                onAddAnnotation: onAddAnnotation,
                onRemoveAnnotation: onRemoveAnnotation
            )
        } else {
            ForEach(section.lines) { line in
                lineRow(for: line)
            }
        }
    }

    @ViewBuilder
    private func lineRow(for line: DiffLine) -> some View {
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

    /// The hunk's non-header lines formatted as a unified diff snippet ("+"/"-"/" " prefix).
    private var hunkCodeContext: String {
        hunk.lines
            .filter { $0.kind != .hunkHeader }
            .map { line in
                switch line.kind {
                case .addition:   return "+\(line.text)"
                case .deletion:   return "-\(line.text)"
                case .context:    return " \(line.text)"
                case .hunkHeader: return ""
                }
            }
            .joined(separator: "\n")
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
                Button { showFixPopover = true } label: {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .help("Fix this hunk")
                .popover(isPresented: $showFixPopover, arrowEdge: .trailing) {
                    HunkFixPopoverView(
                        filePath: filePath,
                        lineRange: hunk.newFileLineRange,
                        codeContext: hunkCodeContext,
                        onSubmit: { prompt in
                            onRequestFix(prompt)
                            showFixPopover = false
                        },
                        onCancel: { showFixPopover = false }
                    )
                }
            }
            if let onShowInPreview {
                Button { onShowInPreview() } label: {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                .help("Show in Preview")
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

/// A full-width clickable row shown in place of a collapsed run of context lines.
struct CollapsedContextSeparator: View {
    let hiddenCount: Int
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 1)
                Image(systemName: "ellipsis")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("\(hiddenCount) unchanged line\(hiddenCount == 1 ? "" : "s") hidden")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Image(systemName: "ellipsis")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 1)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Click to expand \(hiddenCount) hidden line\(hiddenCount == 1 ? "" : "s")")
    }
}

/// Renders a run of context lines with automatic collapsing. When the run's length
/// exceeds `2 * contextLines`, the middle portion is hidden behind a clickable
/// `CollapsedContextSeparator`. Both individual sections and the global
/// "diffContextExpanded" AppStorage key can expand all hidden context at once.
struct CollapsibleContextRunView: View {
    let lines: [DiffLine]
    /// Number of visible context lines kept at each end of a collapsed region.
    var contextLines: Int = 3
    var syntaxHighlights: [Int: AttributedString] = [:]
    var filePath: String? = nil
    var lineAnnotations: [Int: String] = [:]
    var onAddAnnotation: ((Int, String) -> Void)? = nil
    var onRemoveAnnotation: ((Int) -> Void)? = nil

    @State private var isExpanded = false
    @AppStorage("diffContextExpanded") private var globalContextExpanded = false

    private var isActuallyExpanded: Bool { isExpanded || globalContextExpanded }

    private var headLines: [DiffLine] { Array(lines.prefix(contextLines)) }
    private var tailLines: [DiffLine] {
        let start = min(lines.count, max(contextLines, lines.count - contextLines))
        return Array(lines[start...])
    }
    private var hiddenCount: Int { max(0, lines.count - headLines.count - tailLines.count) }

    var body: some View {
        Group {
            if isActuallyExpanded || hiddenCount <= 0 {
                ForEach(lines) { line in contextLineView(for: line) }
            } else {
                ForEach(headLines) { line in contextLineView(for: line) }
                CollapsedContextSeparator(hiddenCount: hiddenCount) {
                    isExpanded = true
                }
                ForEach(tailLines) { line in contextLineView(for: line) }
            }
        }
        .onChange(of: globalContextExpanded) { _, newVal in
            if !newVal { isExpanded = false }
        }
    }

    @ViewBuilder
    private func contextLineView(for line: DiffLine) -> some View {
        DiffLineView(
            line: line,
            syntaxHighlight: syntaxHighlights[line.id],
            filePath: filePath,
            onAddAnnotation: onAddAnnotation,
            onRemoveAnnotation: removeHandler(for: line),
            existingAnnotation: annotation(for: line)
        )
    }

    private func annotation(for line: DiffLine) -> String? {
        guard let num = line.newLineNumber ?? line.oldLineNumber else { return nil }
        return lineAnnotations[num]
    }

    private func removeHandler(for line: DiffLine) -> (() -> Void)? {
        guard let num = line.newLineNumber ?? line.oldLineNumber,
              let handler = onRemoveAnnotation else { return nil }
        return { handler(num) }
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

/// A compact popover for sending a hunk-level corrective prompt to the agent terminal.
/// Pre-filled with the hunk's file path, line range, and code context so the agent has
/// precise information about which code needs to be changed and why.
struct HunkFixPopoverView: View {
    var filePath: String?
    var lineRange: String?
    var codeContext: String
    var onSubmit: (String) -> Void
    var onCancel: () -> Void

    @State private var instruction = ""
    @FocusState private var isFocused: Bool

    private var mentionPrefix: String {
        if let path = filePath, let range = lineRange {
            return "@\(path)#\(range)"
        } else if let path = filePath {
            return "@\(path)"
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: file + line range reference
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("Fix this hunk")
                    .font(.system(size: 11, weight: .semibold))
                if !mentionPrefix.isEmpty {
                    Text(mentionPrefix)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Code context preview
            if !codeContext.isEmpty {
                ScrollView([.horizontal, .vertical]) {
                    Text(codeContext)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Instruction field
            TextField("Describe the fix (e.g. add nil check)…", text: $instruction)
                .font(.system(size: 12))
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .focused($isFocused)
                .onSubmit { submit() }
                .onKeyPress(.escape) { onCancel(); return .handled }

            HStack(spacing: 6) {
                Button("Send Fix") { submit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
                    .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel") { onCancel() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .onAppear { isFocused = true }
    }

    private func submit() {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let prompt: String
        if !codeContext.isEmpty {
            prompt = "\(mentionPrefix) \(trimmed)\n```diff\n\(codeContext)\n```"
        } else {
            prompt = "\(mentionPrefix) \(trimmed)"
        }
        onSubmit(prompt)
    }
}
