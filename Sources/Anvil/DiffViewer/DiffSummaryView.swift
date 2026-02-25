import SwiftUI

/// A unified review view that shows all changed files' diffs in a single
/// scrollable pane — similar to GitHub's pull request diff view.
struct DiffSummaryView: View {
    @ObservedObject var changesModel: ChangesModel
    var onSelectFile: ((URL) -> Void)?
    var onDismiss: (() -> Void)?
    @State private var collapsedFiles: Set<URL> = []
    @State private var scrollTarget: URL?

    private var filesWithDiffs: [ChangedFile] {
        changesModel.changedFiles.filter { $0.diff != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            summaryHeader

            Divider()

            if changesModel.changedFiles.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
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
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Header

    private var summaryHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.orange)
                .font(.system(size: 12))

            Text("Review All Changes")
                .font(.system(size: 13, weight: .semibold))

            Text("\(changesModel.changedFiles.count) file\(changesModel.changedFiles.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

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
        .background(.bar)
    }

    // MARK: - File Section

    @ViewBuilder
    private func fileDiffSection(_ file: ChangedFile) -> some View {
        let isCollapsed = collapsedFiles.contains(file.url)

        // File header
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedFiles.remove(file.url)
                    } else {
                        collapsedFiles.insert(file.url)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // Diff content
            if !isCollapsed {
                if let diff = file.diff {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(diff.hunks) { hunk in
                            DiffHunkView(hunk: hunk)
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
