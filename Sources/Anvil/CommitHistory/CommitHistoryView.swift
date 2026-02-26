import SwiftUI

/// Project-wide git commit history sidebar tab.
/// Shows a paginated list of commits with author filter and date-range filter.
/// Expanding a commit reveals the changed files; clicking a file opens its diff
/// in the file-preview panel via `filePreview.selectCommitFile`.
struct CommitHistoryView: View {
    @ObservedObject var model: CommitHistoryModel
    @ObservedObject var filePreview: FilePreviewModel
    var rootURL: URL
    /// Called when the user requests the full diff for a commit.
    var onViewCommitDiff: ((GitCommit) -> Void)?

    /// Set of commit SHAs that are currently expanded to show their file list.
    @State private var expandedSHAs: Set<String> = []
    @State private var showDateFilter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterBar
            Divider()

            if model.commits.isEmpty && !model.isLoading {
                emptyState
            } else {
                commitList
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Filter by author…", text: $model.authorFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !model.authorFilter.isEmpty {
                    Button {
                        model.authorFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                Divider().frame(height: 14)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showDateFilter.toggle()
                    }
                    if !showDateFilter {
                        model.sinceDate = nil
                        model.untilDate = nil
                    }
                } label: {
                    Image(systemName: showDateFilter ? "calendar.badge.minus" : "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(
                            (showDateFilter || model.sinceDate != nil || model.untilDate != nil)
                                ? Color.accentColor : .secondary
                        )
                }
                .buttonStyle(.borderless)
                .help(showDateFilter ? "Hide date filter" : "Filter by date range")
            }

            if showDateFilter {
                HStack(spacing: 6) {
                    Text("From")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { model.sinceDate ?? Calendar.current.date(byAdding: .month, value: -1, to: Date())! },
                            set: { model.sinceDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .font(.system(size: 11))

                    Text("to")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    DatePicker(
                        "",
                        selection: Binding(
                            get: { model.untilDate ?? Date() },
                            set: { model.untilDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .font(.system(size: 11))

                    if model.sinceDate != nil || model.untilDate != nil {
                        Button {
                            model.sinceDate = nil
                            model.untilDate = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Clear date range")
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Commit List

    private var commitList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.commits) { commit in
                    CommitRowView(
                        commit: commit,
                        isExpanded: expandedSHAs.contains(commit.sha),
                        rootURL: rootURL,
                        onToggle: {
                            if expandedSHAs.contains(commit.sha) {
                                expandedSHAs.remove(commit.sha)
                            } else {
                                expandedSHAs.insert(commit.sha)
                                model.loadFiles(for: commit)
                            }
                        },
                        onSelectFile: { path in
                            filePreview.selectCommitFile(
                                path: path,
                                commitSHA: commit.sha,
                                rootURL: rootURL
                            )
                        },
                        onViewDiff: { onViewCommitDiff?(commit) }
                    )
                    Divider().padding(.leading, 12)
                }

                // Pagination footer
                if model.hasMore || model.isLoading {
                    HStack {
                        if model.isLoading {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Load more") {
                                model.loadNextPage()
                            }
                            .font(.system(size: 12))
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    // Trigger load-more automatically when the footer appears
                    .onAppear {
                        if !model.isLoading {
                            model.loadNextPage()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            if model.authorFilter.isEmpty && model.sinceDate == nil && model.untilDate == nil {
                Text("No commits yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Commits will appear here\nas the agent works")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No matching commits")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Try adjusting the filters")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Commit Row

private struct CommitRowView: View {
    let commit: GitCommit
    let isExpanded: Bool
    let rootURL: URL
    let onToggle: () -> Void
    let onSelectFile: (String) -> Void
    var onViewDiff: (() -> Void)?

    @State private var isHeaderHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — tap to expand/collapse
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12, alignment: .center)
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(commit.message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
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

                            // File count badge
                            if let files = commit.files {
                                Text("\(files.count)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.secondary.opacity(0.6)))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHeaderHovered = $0 }
            .overlay(alignment: .topTrailing) {
                if let onViewDiff, isHeaderHovered {
                    Button(action: onViewDiff) {
                        Label("View Diff", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("View full diff for this commit")
                    .padding(.trailing, 10)
                    .padding(.top, 8)
                }
            }
            .contextMenu {
                if let onViewDiff {
                    Button(action: onViewDiff) {
                        Label("View Diff", systemImage: "doc.text.magnifyingglass")
                    }
                    Divider()
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commit.sha, forType: .string)
                } label: {
                    Label("Copy Full SHA", systemImage: "doc.on.doc")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commit.shortSHA, forType: .string)
                } label: {
                    Label("Copy Short SHA", systemImage: "doc.on.doc")
                }

                Divider()

                Button {
                    GitHubURLBuilder.openCommit(rootURL: rootURL, sha: commit.sha)
                } label: {
                    Label("Open Commit in GitHub", systemImage: "arrow.up.right.square")
                }
            }

            // Expanded file list
            if isExpanded {
                if let files = commit.files {
                    if files.isEmpty {
                        Text("No files changed")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 32)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(files) { file in
                                CommitFileRowView(file: file) {
                                    onSelectFile(file.path)
                                }
                            }
                        }
                        .padding(.bottom, 4)
                    }
                } else {
                    // Loading spinner while files are being fetched
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Loading files…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 32)
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - Commit File Row

private struct CommitFileRowView: View {
    let file: CommitFile
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Status badge
                Text(file.status)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(RoundedRectangle(cornerRadius: 2).fill(statusColor))

                VStack(alignment: .leading, spacing: 1) {
                    Text(file.fileName)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !file.directoryPath.isEmpty {
                        Text(file.directoryPath)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // +/- stats
                if file.additions > 0 || file.deletions > 0 {
                    HStack(spacing: 3) {
                        if file.additions > 0 {
                            Text("+\(file.additions)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        if file.deletions > 0 {
                            Text("-\(file.deletions)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(.leading, 32)
            .padding(.trailing, 12)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .onHover { hovering in
            // Visual hover feedback is provided by the system for .plain button style
            _ = hovering
        }
    }

    private var statusColor: Color {
        switch file.status {
        case "A": return .green
        case "D": return .red
        case "R": return .blue
        default:  return .orange
        }
    }
}
