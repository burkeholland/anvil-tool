import SwiftUI

/// A unified review view that shows all changed files' diffs in a single
/// scrollable pane — similar to GitHub's pull request diff view.
/// Includes staging controls and a commit form for a complete review-to-commit workflow.
struct DiffSummaryView: View {
    @ObservedObject var changesModel: ChangesModel
    @ObservedObject var annotationStore: DiffAnnotationStore
    var onSelectFile: ((URL) -> Void)?
    var onDismiss: (() -> Void)?
    /// Called with `(url, lineNumber)` when the user taps "Show in Preview" on a hunk.
    var onShowFileAtLine: ((URL, Int) -> Void)?
    @State private var collapsedFiles: Set<URL> = []
    @State private var scrollTarget: URL?
    @AppStorage("diffViewMode") private var diffMode: String = DiffViewMode.unified.rawValue
    @State private var showCommitForm = false
    @State private var requestFixContext: RequestFixContext?
    @State private var showAnnotationsList = false
    @EnvironmentObject var terminalProxy: TerminalInputProxy

    private var filesWithDiffs: [ChangedFile] {
        changesModel.changedFiles.filter { $0.diff != nil }
    }

    /// Total risk flags detected across all hunks in all changed files.
    private var totalRiskFlagCount: Int {
        filesWithDiffs.reduce(0) { total, file in
            guard let diff = file.diff else { return total }
            return total + diff.hunks.reduce(0) { $0 + DiffRiskScanner.scan($1).count }
        }
    }
    var body: some View {
        contentWithFocusedValues
            .focusedValue(\.stageFocusedHunk, changesModel.focusedHunk != nil ? { changesModel.stageFocusedHunk() } : nil)
            .focusedValue(\.discardFocusedHunk, changesModel.focusedHunk != nil ? { changesModel.discardFocusedHunk() } : nil)
            .focusedValue(\.toggleFocusedFileReviewed, changesModel.focusedFile != nil ? { changesModel.toggleFocusedFileReviewed() } : nil)
            .focusedValue(\.openFocusedFile, changesModel.focusedFile != nil ? {
                if let url = changesModel.focusedFile?.url { onSelectFile?(url) }
            } : nil)
            .focusedValue(\.requestFix, changesModel.focusedFile != nil ? {
                if let file = changesModel.focusedFile {
                    requestFix(for: file, hunk: changesModel.focusedHunk)
                }
            } : nil)
            .focusedValue(\.toggleDiffViewMode, {
                diffMode = (DiffViewMode(rawValue: diffMode) ?? .unified).toggled.rawValue
            })
    }

    // Split from body to stay within Swift type-checker expression limits.
    private var contentWithFocusedValues: some View {
        contentView
            .focusedValue(\.nextReviewFile, { changesModel.focusNextFile() })
            .focusedValue(\.previousReviewFile, { changesModel.focusPreviousFile() })
            .focusedValue(\.nextHunk, { changesModel.focusNextHunk() })
            .focusedValue(\.previousHunk, { changesModel.focusPreviousHunk() })
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            // Header bar
            summaryHeader

            Divider()

            // Request Fix prompt bar (shown when a fix is requested)
            if let context = requestFixContext {
                RequestFixPromptView(
                    context: context,
                    onSubmit: { prompt in
                        terminalProxy.send(prompt)
                        requestFixContext = nil
                    },
                    onDismiss: { requestFixContext = nil }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if changesModel.changedFiles.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            // Inline commit form
                            if showCommitForm {
                                ReviewCommitForm(model: changesModel, onCommitted: {
                                    showCommitForm = false
                                })
                                .id("commit-form")
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            ForEach(changesModel.changedFiles) { file in
                                fileDiffSection(file)
                                    .id(file.url)
                            }
                        }
                    }
                    .onChange(of: scrollTarget) { _, target in
                        if let target {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(target, anchor: .top)
                            }
                            scrollTarget = nil
                        }
                    }
                    .onChange(of: changesModel.focusedFileIndex) { _, idx in
                        if let idx, changesModel.changedFiles.indices.contains(idx) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(changesModel.changedFiles[idx].url, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .focusable()
        .onKeyPress { keyPress in
            switch keyPress.characters {
            case "]": changesModel.focusNextFile(); return .handled
            case "[": changesModel.focusPreviousFile(); return .handled
            case "j", "n": changesModel.focusNextHunk(); return .handled
            case "k", "p": changesModel.focusPreviousHunk(); return .handled
            case "s": changesModel.stageFocusedHunk(); return .handled
            case "d": changesModel.discardFocusedHunk(); return .handled
            case "r": changesModel.toggleFocusedFileReviewed(); return .handled
            case "f":
                if let file = changesModel.focusedFile {
                    requestFix(for: file, hunk: changesModel.focusedHunk)
                }
                return .handled
            default:
                if keyPress.key == .return {
                    if let url = changesModel.focusedFile?.url { onSelectFile?(url) }
                    return .handled
                }
                return .ignored
            }
        }
        .animation(.easeInOut(duration: 0.15), value: requestFixContext != nil)
    }

    // MARK: - Request Fix helper

    private func requestFix(for file: ChangedFile, hunk: DiffHunk?) {
        requestFixContext = RequestFixContext(
            filePath: file.relativePath,
            lineRange: hunk?.newFileLineRange
        )
    }

    // MARK: - Header

    private var summaryHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))

                Text("Review All Changes")
                    .font(.system(size: 13, weight: .semibold))

                Text("\(changesModel.changedFiles.count) file\(changesModel.changedFiles.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if changesModel.reviewedCount > 0 {
                    Text("(\(changesModel.reviewedCount)/\(changesModel.changedFiles.count) reviewed)")
                        .font(.system(size: 10))
                        .foregroundStyle(changesModel.reviewedCount == changesModel.changedFiles.count ? .green : .blue.opacity(0.7))
                }

                if totalRiskFlagCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("\(totalRiskFlagCount) risk\(totalRiskFlagCount == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                    .help("Risk flags detected in diff hunks — look for ⚠ icons in the hunk headers")
                }

                Spacer()

                if changesModel.totalAdditions > 0 {
                    Text("+\(changesModel.totalAdditions)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.green)
                }
                if changesModel.totalDeletions > 0 {
                    Text("-\(changesModel.totalDeletions)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red)
                }

                if !filesWithDiffs.isEmpty {
                    Picker("", selection: $diffMode) {
                        ForEach(DiffViewMode.allCases, id: \.rawValue) { m in
                            Text(m.rawValue).tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    if !annotationStore.isEmpty {
                        Button {
                            showAnnotationsList = true
                        } label: {
                            let count = annotationStore.annotations.count
                            HStack(spacing: 3) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 10))
                                Text("\(count)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(.yellow)
                        }
                        .buttonStyle(.borderless)
                        .help("View \(annotationStore.annotations.count) inline annotation\(annotationStore.annotations.count == 1 ? "" : "s")")
                        .sheet(isPresented: $showAnnotationsList) {
                            AnnotationsListView(
                                annotationStore: annotationStore,
                                onSend: {
                                    terminalProxy.sendPrompt(annotationStore.buildPrompt())
                                    showAnnotationsList = false
                                }
                            )
                        }
                    }

                    Button {
                        if collapsedFiles.count == filesWithDiffs.count {
                            collapsedFiles.removeAll()
                        } else {
                            collapsedFiles = Set(filesWithDiffs.map(\.url))
                        }
                    } label: {
                        Image(systemName: collapsedFiles.count == filesWithDiffs.count
                              ? "chevron.down.2" : "chevron.up.2")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(collapsedFiles.count == filesWithDiffs.count ? "Expand All" : "Collapse All")
                }

                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Close Review")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Staging action bar
            HStack(spacing: 8) {
                StagingSummary(changesModel: changesModel)

                Spacer()

                Button {
                    changesModel.stageAll()
                } label: {
                    Text("Stage All")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(changesModel.unstagedFiles.isEmpty)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCommitForm.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 10))
                        Text(showCommitForm ? "Hide Commit" : "Commit…")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(changesModel.changedFiles.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    // MARK: - File Section

    @ViewBuilder
    private func fileDiffSection(_ file: ChangedFile) -> some View {
        let isCollapsed = collapsedFiles.contains(file.url)
        let isStaged = file.staging == .staged || file.staging == .partial
        let isFocusedFile = changesModel.focusedFile?.url == file.url

        // File header
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Stage/unstage toggle
                Button {
                    if isStaged {
                        changesModel.unstageFile(file)
                    } else {
                        changesModel.stageFile(file)
                    }
                } label: {
                    Image(systemName: isStaged ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(isStaged ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .help(isStaged ? "Unstage file" : "Stage file")

                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)

                // Status badge
                Text(statusLabel(file.status))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(file.status.color)
                    )

                Text(file.relativePath)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)

                Spacer()

                if let diff = file.diff {
                    HStack(spacing: 6) {
                        if diff.additionCount > 0 {
                            Text("+\(diff.additionCount)")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.green)
                        }
                        if diff.deletionCount > 0 {
                            Text("-\(diff.deletionCount)")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    Text(file.status == .untracked ? "new file" : "no diff")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Button {
                    onSelectFile?(file.url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Open in Preview")

                // Request Fix button for this file
                Button {
                    requestFix(for: file, hunk: nil)
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .help("Request Fix for this file")

                // Review toggle
                Button {
                    changesModel.toggleReviewed(file)
                } label: {
                    Image(systemName: changesModel.isReviewed(file) ? "eye.fill" : "eye")
                        .font(.system(size: 10))
                        .foregroundStyle(changesModel.isReviewed(file) ? .blue : .secondary)
                }
                .buttonStyle(.borderless)
                .help(changesModel.isReviewed(file) ? "Mark as Unreviewed" : "Mark as Reviewed")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                if let idx = changesModel.changedFiles.firstIndex(where: { $0.id == file.id }) {
                    changesModel.focusedFileIndex = idx
                    changesModel.focusedHunkIndex = nil
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedFiles.remove(file.url)
                    } else {
                        collapsedFiles.insert(file.url)
                    }
                }
            }
            .background(
                isFocusedFile
                    ? Color.accentColor.opacity(0.1)
                    : Color(nsColor: .controlBackgroundColor).opacity(0.5)
            )
            .overlay(
                isFocusedFile
                    ? Rectangle().frame(height: 1.5).foregroundStyle(Color.accentColor.opacity(0.6))
                    : nil,
                alignment: .bottom
            )

            Divider()

            // Diff content
            if !isCollapsed {
                if let diff = file.diff {
                    let viewMode = DiffViewMode(rawValue: diffMode) ?? .unified
                    let highlights = DiffSyntaxHighlighter.highlight(diff: diff)
                    if viewMode == .sideBySide {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(DiffRowPairer.pairLines(from: diff.hunks)) { row in
                                SideBySideRowView(row: row, syntaxHighlights: highlights)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(diff.hunks.enumerated()), id: \.element.id) { (hunkIdx, hunk) in
                                DiffHunkView(
                                    hunk: hunk,
                                    syntaxHighlights: highlights,
                                    onStage: file.staging != .staged ? {
                                        changesModel.stageHunk(patch: DiffParser.reconstructPatch(fileDiff: diff, hunk: hunk))
                                    } : nil,
                                    onUnstage: file.staging != .unstaged ? {
                                        changesModel.unstageHunk(patch: DiffParser.reconstructPatch(fileDiff: diff, hunk: hunk))
                                    } : nil,
                                    onDiscard: {
                                        changesModel.discardHunk(patch: DiffParser.reconstructPatch(fileDiff: diff, hunk: hunk))
                                    },
                                    onRequestFix: { prompt in
                                        terminalProxy.sendPrompt(prompt)
                                    },
                                    onShowInPreview: onShowFileAtLine.map { handler in
                                        { handler(file.url, hunk.newFileStartLine ?? 1) }
                                    },
                                    isFocused: isFocusedFile && changesModel.focusedHunkIndex == hunkIdx,
                                    filePath: file.relativePath,
                                    lineAnnotations: annotationStore.lineAnnotations(forFile: file.relativePath),
                                    onAddAnnotation: { lineNum, comment in
                                        annotationStore.add(filePath: file.relativePath, lineNumber: lineNum, comment: comment)
                                    },
                                    onRemoveAnnotation: { lineNum in
                                        annotationStore.remove(filePath: file.relativePath, lineNumber: lineNum)
                                    }
                                )
                            }
                        }
                    }
                } else if file.status == .untracked {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.green.opacity(0.6))
                        Text("New untracked file")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                } else if file.status == .deleted {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.6))
                        Text("File deleted")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                }

                Divider()
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.green.opacity(0.6))
            Text("No changes to review")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Working tree is clean")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func statusLabel(_ status: GitFileStatus) -> String {
        switch status {
        case .modified:   return "M"
        case .added:      return "A"
        case .deleted:    return "D"
        case .untracked:  return "?"
        case .renamed:    return "R"
        case .conflicted: return "!"
        }
    }
}

// MARK: - Staging Summary

/// Shows a compact summary of staging state: "3 of 5 staged".
private struct StagingSummary: View {
    @ObservedObject var changesModel: ChangesModel

    var body: some View {
        let staged = changesModel.stagedFiles.count
        let total = changesModel.changedFiles.count

        HStack(spacing: 6) {
            if staged == 0 {
                Image(systemName: "square.dashed")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("No files staged")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if staged == total {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text("All \(total) file\(total == 1 ? "" : "s") staged")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "minus.square")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("\(staged) of \(total) staged")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Review Commit Form

/// A compact inline commit form for the review pane.
private struct ReviewCommitForm: View {
    @ObservedObject var model: ChangesModel
    var onCommitted: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("Commit Changes")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }

            ZStack(alignment: .topLeading) {
                if model.commitMessage.isEmpty {
                    Text("Commit message")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                }
                TextEditor(text: $model.commitMessage)
                    .font(.system(size: 12))
                    .frame(minHeight: 36, maxHeight: 60)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .overlay(alignment: .bottomTrailing) {
                Button {
                    model.commitMessage = model.generateCommitMessage(allFiles: true)
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Generate commit message from changes")
                .padding(4)
            }

            HStack(spacing: 8) {
                Button {
                    model.stageAllAndCommit()
                } label: {
                    HStack(spacing: 4) {
                        if model.isCommitting {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text("Stage All & Commit")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.changedFiles.isEmpty || model.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isCommitting)

                if !model.stagedFiles.isEmpty {
                    Button {
                        model.commit()
                    } label: {
                        HStack(spacing: 4) {
                            if model.isCommitting {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text("Commit (\(model.stagedFiles.count))")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!model.canCommit)
                }
            }

            if let error = model.lastCommitError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(alignment: .bottom) { Divider() }
        .onChange(of: model.stagedFiles.count) { old, new in
            // Auto-dismiss after successful commit (staged goes to 0 and no files remain)
            if old > 0 && new == 0 && model.changedFiles.isEmpty {
                onCommitted?()
            }
        }
    }
}

// MARK: - Annotations List

/// A filterable list of all inline diff annotations for the current review session.
/// Accessible from the Changes panel header via the annotation badge button.
struct AnnotationsListView: View {
    @ObservedObject var annotationStore: DiffAnnotationStore
    var onSend: () -> Void

    @State private var filterText = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredAnnotations: [DiffAnnotation] {
        let sorted = annotationStore.annotations.sorted {
            if $0.filePath != $1.filePath { return $0.filePath < $1.filePath }
            return $0.lineNumber < $1.lineNumber
        }
        guard !filterText.isEmpty else { return sorted }
        let query = filterText.lowercased()
        return sorted.filter {
            $0.filePath.lowercased().contains(query) || $0.comment.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 12))
                Text("Annotations")
                    .font(.system(size: 13, weight: .semibold))
                Text("(\(annotationStore.annotations.count))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onSend()
                } label: {
                    Label("Send to Agent", systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.yellow)
                .disabled(annotationStore.isEmpty)
                .help("Send all annotations to the Copilot terminal")
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Filter field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Filter by file or note…", text: $filterText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                if !filterText.isEmpty {
                    Button { filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))

            Divider()

            if filteredAnnotations.isEmpty {
                Spacer()
                Text(annotationStore.isEmpty ? "No annotations yet" : "No results for \"\(filterText)\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filteredAnnotations) { annotation in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(annotation.filePath)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("L\(annotation.lineNumber)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Text(annotation.comment)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Button {
                            annotationStore.remove(filePath: annotation.filePath, lineNumber: annotation.lineNumber)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.borderless)
                        .help("Remove annotation")
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 480, height: 360)
    }
}
