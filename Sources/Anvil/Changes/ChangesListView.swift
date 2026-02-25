import SwiftUI
import AppKit

/// Shows all git-changed files in a list with status indicators and diff stats.
struct ChangesListView: View {
    @ObservedObject var model: ChangesModel
    @ObservedObject var filePreview: FilePreviewModel
    @EnvironmentObject var terminalProxy: TerminalInputProxy

    var body: some View {
        if model.isLoading && model.changedFiles.isEmpty {
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
        } else if model.changedFiles.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.green.opacity(0.6))
                Text("No changes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Working tree is clean")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Summary bar
                HStack(spacing: 12) {
                    Text("\(model.changedFiles.count) changed file\(model.changedFiles.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                Divider()

                // File list
                List {
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
                            Button {
                                terminalProxy.mentionFile(relativePath: file.relativePath)
                            } label: {
                                Label("Mention in Terminal", systemImage: "terminal")
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
                        }
                    }
                }
                .listStyle(.sidebar)
            }
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
