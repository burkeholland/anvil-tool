import SwiftUI

/// Shows the full diff for a single git commit — all files changed, with collapsible
/// sections, side-by-side toggle, and word-level highlights. Mirrors the layout of
/// BranchDiffView but scoped to one commit rather than a whole branch.
struct CommitDiffView: View {
    @ObservedObject var model: CommitDiffModel
    /// Called when the user clicks a file path to jump to it in the source preview.
    var onSelectFile: ((String, URL) -> Void)?
    var onDismiss: (() -> Void)?
    /// Root URL of the repository, used to build absolute file URLs.
    var rootURL: URL?

    @State private var collapsedFiles: Set<String> = []
    @AppStorage("diffViewMode") private var diffMode: String = DiffViewMode.unified.rawValue

    private var filesWithDiffs: [CommitDiffFile] {
        model.files.filter { $0.diff != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            commitDiffHeader
            Divider()

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
    }

    // MARK: - Header

    private var commitDiffHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))

                if let commit = model.commit {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(commit.message)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(commit.shortSHA)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(commit.author)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(commit.relativeDate)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Text("Commit Diff")
                        .font(.system(size: 13, weight: .semibold))
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

                    Button {
                        if collapsedFiles.count == filesWithDiffs.count {
                            collapsedFiles.removeAll()
                        } else {
                            collapsedFiles = Set(filesWithDiffs.map(\.path))
                        }
                    } label: {
                        Image(
                            systemName: collapsedFiles.count == filesWithDiffs.count
                                ? "chevron.down.2" : "chevron.up.2"
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(
                        collapsedFiles.count == filesWithDiffs.count
                            ? "Expand All" : "Collapse All"
                    )
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
                    .help("Close Commit Diff")
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
    private func fileDiffSection(_ file: CommitDiffFile) -> some View {
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
                    Text(noDiffLabel(file.status))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if let onSelectFile, let root = rootURL {
                    Button {
                        onSelectFile(file.path, root.appendingPathComponent(file.path))
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Open in Preview")
                }
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
                                    syntaxHighlights: highlights
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
            Text("Loading commit diff…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
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
            Text("No files changed in this commit")
                .font(.headline)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func noDiffLabel(_ status: String) -> String {
        switch status {
        case "A": return "new file"
        case "D": return "deleted"
        default:  return "no diff"
        }
    }

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
