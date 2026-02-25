import SwiftUI

struct FileTreeView: View {
    let rootURL: URL
    @State private var entries: [FileEntry] = []
    @State private var expandedDirs: Set<URL> = []

    var body: some View {
        List {
            ForEach(entries) { entry in
                FileRowView(
                    entry: entry,
                    isExpanded: expandedDirs.contains(entry.url),
                    onToggle: { toggleDirectory(entry) }
                )
            }
        }
        .listStyle(.sidebar)
        .onAppear { loadDirectory(rootURL) }
    }

    private func loadDirectory(_ url: URL) {
        entries = FileEntry.loadChildren(of: url)
    }

    private func toggleDirectory(_ entry: FileEntry) {
        guard entry.isDirectory else { return }
        if expandedDirs.contains(entry.url) {
            expandedDirs.remove(entry.url)
            collapseChildren(of: entry)
        } else {
            expandedDirs.insert(entry.url)
            expandChildren(of: entry)
        }
    }

    private func expandChildren(of entry: FileEntry) {
        guard let index = entries.firstIndex(where: { $0.url == entry.url }) else { return }
        let children = FileEntry.loadChildren(of: entry.url, depth: entry.depth + 1)
        entries.insert(contentsOf: children, at: index + 1)
    }

    private func collapseChildren(of entry: FileEntry) {
        guard let index = entries.firstIndex(where: { $0.url == entry.url }) else { return }
        // Remove all entries that are deeper than this one, until we hit a sibling or parent
        var removeCount = 0
        for i in (index + 1)..<entries.count {
            if entries[i].depth > entry.depth {
                removeCount += 1
            } else {
                break
            }
        }
        if removeCount > 0 {
            entries.removeSubrange((index + 1)..<(index + 1 + removeCount))
        }
        // Also remove from expanded set
        expandedDirs = expandedDirs.filter { url in
            !url.path.hasPrefix(entry.url.path + "/")
        }
    }
}

struct FileRowView: View {
    let entry: FileEntry
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Indentation
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
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
