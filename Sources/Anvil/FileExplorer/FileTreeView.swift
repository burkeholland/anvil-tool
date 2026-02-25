import SwiftUI

struct FileTreeView: View {
    let rootURL: URL
    @ObservedObject var filePreview: FilePreviewModel
    @StateObject private var model = FileTreeModel()

    var body: some View {
        List {
            ForEach(model.entries) { entry in
                FileRowView(
                    entry: entry,
                    isExpanded: model.isExpanded(entry.url),
                    isSelected: filePreview.selectedURL == entry.url,
                    gitStatus: model.gitStatuses[entry.url.path],
                    onToggle: { handleTap(entry) }
                )
            }
        }
        .listStyle(.sidebar)
        .onAppear { model.start(rootURL: rootURL) }
        .onChange(of: model.gitStatuses) { _, _ in
            filePreview.refreshDiff()
        }
    }

    private func handleTap(_ entry: FileEntry) {
        if entry.isDirectory {
            model.toggleDirectory(entry)
        } else {
            filePreview.select(entry.url)
        }
    }
}

struct FileRowView: View {
    let entry: FileEntry
    let isExpanded: Bool
    let isSelected: Bool
    var gitStatus: GitFileStatus? = nil
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<entry.depth, id: \.self) { _ in
                Color.clear.frame(width: 16)
            }

            if entry.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }

            Image(systemName: entry.icon)
                .foregroundStyle(entry.iconColor)
                .font(.system(size: 13))

            Text(entry.name)
                .font(.system(.body, design: .default))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let status = gitStatus {
                Circle()
                    .fill(status.color)
                    .frame(width: 6, height: 6)
                    .help(status.label)
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.2))
                : nil
        )
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
