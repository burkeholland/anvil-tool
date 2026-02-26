import SwiftUI

/// Shows the git commit history for the currently selected file in the preview pane.
/// Each commit can be tapped to view the file's diff at that commit.
struct FileHistoryView: View {
    @ObservedObject var model: FilePreviewModel
    let rootURL: URL

    var body: some View {
        if model.fileHistory.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("No history")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("This file has no git commits yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.fileHistory.enumerated()), id: \.element.id) { index, commit in
                            FileHistoryRow(
                                commit: commit,
                                isFirst: index == 0,
                                isSelected: commit.sha == model.selectedHistoryCommitSHA,
                                onSelect: {
                                    if let relativePath = model.selectedURL.map({ FilePreviewModel.relativePath(of: $0, from: rootURL) }) {
                                        model.selectCommitFile(path: relativePath, commitSHA: commit.sha, rootURL: rootURL)
                                    }
                                }
                            )
                            .id(commit.sha)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: model.selectedHistoryCommitSHA) { _, sha in
                    guard let sha,
                          let match = model.fileHistory.first(where: { $0.sha == sha }) else { return }
                    withAnimation { proxy.scrollTo(match.sha, anchor: .center) }
                }
            }
        }
    }
}

private struct FileHistoryRow: View {
    let commit: GitCommit
    var isFirst: Bool = false
    var isSelected: Bool = false
    let onSelect: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                // Timeline indicator
                VStack(spacing: 0) {
                    Circle()
                        .fill(isFirst ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 1)
                }
                .frame(width: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(commit.message)
                        .font(.system(size: 12))
                        .lineLimit(2)
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
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.15)
                            : isHovering ? Color.accentColor.opacity(0.06) : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
    }
}
