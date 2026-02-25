import SwiftUI
import AppKit

/// Shows all git-changed files in a list with status indicators and diff stats,
/// plus a recent commit history section.
struct ChangesListView: View {
    @ObservedObject var model: ChangesModel
    @ObservedObject var filePreview: FilePreviewModel
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @State private var fileToDiscard: ChangedFile?

    var body: some View {
        if model.isLoading && model.changedFiles.isEmpty && model.recentCommits.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Scanning changes…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                // Working changes section
                if !model.changedFiles.isEmpty {
                    Section {
                        ForEach(model.changedFiles) { file in
                            ChangedFileRow(
                                file: file,
                                isSelected: filePreview.selectedURL == file.url
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                filePreview.select(file.url)
                            }
                            .contextMenu {
                                changedFileContextMenu(file: file)
                            }
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Text("Working Changes")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                            Spacer()
                            if model.totalAdditions > 0 {
                                Text("+\(model.totalAdditions)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.green)
                            }
                            if model.totalDeletions > 0 {
                                Text("-\(model.totalDeletions)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } else if !model.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.green.opacity(0.6))
                                Text("Working tree clean")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            Spacer()
                        }
                    } header: {
                        Text("Working Changes")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }

                // Commit history section
                if !model.recentCommits.isEmpty {
                    Section {
                        ForEach(model.recentCommits) { commit in
                            CommitRow(
                                commit: commit,
                                model: model,
                                filePreview: filePreview
                            )
                        }
                    } header: {
                        Text("Recent Commits")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.sidebar)
            .alert("Discard Changes?", isPresented: Binding(
                get: { fileToDiscard != nil },
                set: { if !$0 { fileToDiscard = nil } }
            )) {
                Button("Discard", role: .destructive) {
                    if let file = fileToDiscard {
                        model.discardChanges(for: file)
                        // Close preview if showing this file's diff
                        if filePreview.selectedURL == file.url {
                            filePreview.refresh()
                        }
                    }
                    fileToDiscard = nil
                }
                Button("Cancel", role: .cancel) {
                    fileToDiscard = nil
                }
            } message: {
                if let file = fileToDiscard {
                    Text("This will permanently discard all uncommitted changes to \"\(file.fileName)\". This cannot be undone.")
                }
            }
        }
    }

    @ViewBuilder
    private func changedFileContextMenu(file: ChangedFile) -> some View {
        Button {
            terminalProxy.mentionFile(relativePath: file.relativePath)
        } label: {
            Label("Mention in Terminal", systemImage: "terminal")
        }

        Divider()

        Button {
            ExternalEditorManager.openFile(file.url)
        } label: {
            if let editor = ExternalEditorManager.preferred {
                Label("Open in \(editor.name)", systemImage: "square.and.pencil")
            } else {
                Label("Open in Default App", systemImage: "square.and.pencil")
            }
        }

        Divider()

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.relativePath, forType: .string)
        } label: {
            Label("Copy Relative Path", systemImage: "doc.on.doc")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.url.path, forType: .string)
        } label: {
            Label("Copy Absolute Path", systemImage: "doc.on.doc.fill")
        }

        Divider()

        Button {
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Divider()

        Button(role: .destructive) {
            fileToDiscard = file
        } label: {
            Label("Discard Changes…", systemImage: "arrow.uturn.backward")
        }
    }
}

// MARK: - Commit Row

struct CommitRow: View {
    let commit: GitCommit
    @ObservedObject var model: ChangesModel
    @ObservedObject var filePreview: FilePreviewModel
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Commit header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                if isExpanded && commit.files == nil {
                    model.loadCommitFiles(for: commit.sha)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(commit.message)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            Text(commit.shortSHA)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.purple.opacity(0.8))

                            Text(commit.author)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)

                            Spacer()

                            Text(commit.relativeDate)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .contextMenu {
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
            }

            // Expanded file list
            if isExpanded {
                if let files = commit.files {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(files) { file in
                            CommitFileRow(
                                file: file,
                                commitSHA: commit.sha,
                                model: model,
                                filePreview: filePreview
                            )
                        }
                    }
                    .padding(.leading, 18)
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.mini)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Commit File Row

struct CommitFileRow: View {
    let file: CommitFile
    let commitSHA: String
    @ObservedObject var model: ChangesModel
    @ObservedObject var filePreview: FilePreviewModel

    var body: some View {
        HStack(spacing: 6) {
            Text(file.status)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(statusColor)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !file.directoryPath.isEmpty {
                    Text(file.directoryPath)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            HStack(spacing: 3) {
                if file.additions > 0 {
                    Text("+\(file.additions)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.green)
                }
                if file.deletions > 0 {
                    Text("-\(file.deletions)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let rootURL = model.rootDirectory else { return }
            filePreview.selectCommitFile(
                path: file.path,
                commitSHA: commitSHA,
                rootURL: rootURL
            )
        }
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
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

struct ChangedFileRow: View {
    let file: ChangedFile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Status badge
            Text(statusLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(file.status.color)
                )

            // File name and path
            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !file.directoryPath.isEmpty {
                    Text(file.directoryPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            // Diff stats
            if let diff = file.diff {
                HStack(spacing: 4) {
                    if diff.additionCount > 0 {
                        Text("+\(diff.additionCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    if diff.deletionCount > 0 {
                        Text("-\(diff.deletionCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.2))
                : nil
        )
    }

    private var statusLabel: String {
        switch file.status {
        case .modified:   return "M"
        case .added:      return "A"
        case .deleted:    return "D"
        case .untracked:  return "?"
        case .renamed:    return "R"
        case .conflicted: return "!"
        }
    }
}
