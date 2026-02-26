import SwiftUI

/// Shows the total diff between the current branch and the default branch (main/master).
/// This is the "PR preview" — all changes the agent made across all commits on this branch.
struct BranchDiffView: View {
    @ObservedObject var model: BranchDiffModel
    @ObservedObject var annotationStore: DiffAnnotationStore
    var onSelectFile: ((String, URL) -> Void)?
    var onDismiss: (() -> Void)?
    /// Called with `(filePath, lineNumber)` when the user taps "Show in Preview" on a hunk.
    var onShowInPreview: ((String, Int) -> Void)?
    @State private var collapsedFiles: Set<String> = []
    @AppStorage("diffViewMode") private var diffMode: String = DiffViewMode.unified.rawValue
    @AppStorage("diffContextExpanded") private var contextExpanded = false
    @State private var requestFixContext: RequestFixContext?
    @EnvironmentObject var terminalProxy: TerminalInputProxy

    private var filesWithDiffs: [BranchDiffFile] {
        model.files.filter { $0.diff != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            branchDiffHeader
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

            if model.isLoading {
                loadingState
            } else if let error = model.errorMessage {
                errorState(error)
            } else if model.files.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.files) { file in
                            fileDiffSection(file)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .animation(.easeInOut(duration: 0.15), value: requestFixContext != nil)
        .onChange(of: model.isLoading) { _, isLoading in
            if !isLoading { annotationStore.clearAll() }
        }
        .focusedValue(\.toggleDiffViewMode, {
            diffMode = (DiffViewMode(rawValue: diffMode) ?? .unified).toggled.rawValue
        })
    }

    // MARK: - Header

    private var branchDiffHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.pull")
                    .foregroundStyle(.purple)
                    .font(.system(size: 12))

                Text("Branch Diff")
                    .font(.system(size: 13, weight: .semibold))

                if let current = model.currentBranch, let base = model.baseBranch {
                    HStack(spacing: 4) {
                        Text(base)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        Image(systemName: "arrow.left")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text(current)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                    }
                }

                Spacer()

                if !model.files.isEmpty {
                    if model.totalAdditions > 0 {
                        Text("+\(model.totalAdditions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    if model.totalDeletions > 0 {
                        Text("-\(model.totalDeletions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.red)
                    }

                    Picker("", selection: $diffMode) {
                        ForEach(DiffViewMode.allCases, id: \.rawValue) { m in
                            Text(m.rawValue).tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    if !annotationStore.isEmpty {
                        Button {
                            terminalProxy.sendPrompt(annotationStore.buildPrompt())
                        } label: {
                            let count = annotationStore.annotations.count
                            Label("Send \(count) Annotation\(count == 1 ? "" : "s")", systemImage: "note.text")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.yellow)
                        .help("Send all \(annotationStore.annotations.count) annotation(s) to the Copilot terminal")
                    }

                    Button {
                        contextExpanded.toggle()
                    } label: {
                        Image(systemName: contextExpanded ? "eye.slash" : "eye")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(contextExpanded ? "Collapse context lines" : "Expand all context lines")

                    Button {
                        if collapsedFiles.count == filesWithDiffs.count {
                            collapsedFiles.removeAll()
                        } else {
                            collapsedFiles = Set(filesWithDiffs.map(\.path))
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
                    .help("Close Branch Diff")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Stats bar
            if !model.files.isEmpty {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc")
                            .font(.system(size: 9))
                        Text("\(model.files.count) file\(model.files.count == 1 ? "" : "s") changed")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)

                    if model.commitCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                            Text("\(model.commitCount) commit\(model.commitCount == 1 ? "" : "s")")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.purple)
                    }

                    if let sha = model.mergeBaseSHA {
                        HStack(spacing: 4) {
                            Text("base:")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(sha)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .background(.bar)
    }

    // MARK: - File Section

    @ViewBuilder
    private func fileDiffSection(_ file: BranchDiffFile) -> some View {
        let isCollapsed = collapsedFiles.contains(file.path)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
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
                            .fill(statusColor(file.status))
                    )

                Text(file.path)
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
                    Text(file.status == "A" ? "new file" : file.status == "D" ? "deleted" : "no diff")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if let onSelectFile {
                    Button {
                        onSelectFile(file.path, URL(fileURLWithPath: file.path))
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Open in Preview")
                }

                // Request Fix button for this file
                Button {
                    requestFixContext = RequestFixContext(filePath: file.path, lineRange: nil)
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .help("Request Fix for this file")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedFiles.remove(file.path)
                    } else {
                        collapsedFiles.insert(file.path)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // Diff content (read-only — no staging controls for branch diffs)
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
                            ForEach(diff.hunks) { hunk in
                                DiffHunkView(
                                    hunk: hunk,
                                    syntaxHighlights: highlights,
                                    onRequestFix: { prompt in
                                        terminalProxy.sendPrompt(prompt)
                                    },
                                    onShowInPreview: onShowInPreview.map { handler in
                                        { handler(file.path, hunk.newFileStartLine ?? 1) }
                                    },
                                    filePath: file.path,
                                    lineAnnotations: annotationStore.lineAnnotations(forFile: file.path),
                                    onAddAnnotation: { lineNum, comment in
                                        annotationStore.add(filePath: file.path, lineNumber: lineNum, comment: comment)
                                    },
                                    onRemoveAnnotation: { lineNum in
                                        annotationStore.remove(filePath: file.path, lineNumber: lineNum)
                                    }
                                )
                            }
                        }
                    }
                } else if file.status == "A" {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.green.opacity(0.6))
                        Text("New file")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                } else if file.status == "D" {
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

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("Computing branch diff…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.green.opacity(0.6))
            Text("No changes on this branch")
                .font(.headline)
            Text("The current branch is identical to \(model.baseBranch ?? "the base branch")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "A": return "A"
        case "D": return "D"
        case "R": return "R"
        default:  return "M"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "A": return .green
        case "D": return .red
        case "R": return .blue
        default:  return .orange
        }
    }
}
