import SwiftUI
import AppKit

struct FileTreeView: View {
    let rootURL: URL
    @ObservedObject var filePreview: FilePreviewModel
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @StateObject private var model = FileTreeModel()

    // File operation dialog state
    @State private var showNewFileDialog = false
    @State private var showNewFolderDialog = false
    @State private var showRenameDialog = false
    @State private var showDeleteConfirm = false
    @State private var operationTargetURL: URL?
    @State private var operationName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search files…", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Menu {
                    Button {
                        operationTargetURL = rootURL
                        operationName = ""
                        showNewFileDialog = true
                    } label: {
                        Label("New File…", systemImage: "doc.badge.plus")
                    }
                    Button {
                        operationTargetURL = rootURL
                        operationName = ""
                        showNewFolderDialog = true
                    } label: {
                        Label("New Folder…", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 16)
                .help("New File or Folder")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // Content: search results or tree
            if model.isSearching {
                if model.searchResults.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("No files matching \"\(model.searchText)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(model.searchResults) { result in
                            SearchResultRow(
                                result: result,
                                query: model.searchText,
                                isSelected: filePreview.selectedURL == result.url,
                                gitStatus: model.gitStatuses[result.url.path]
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                filePreview.select(result.url)
                            }
                            .contextMenu {
                                fileContextMenu(url: result.url, isDirectory: false)
                            }
                            .draggable(result.url)
                        }
                    }
                    .listStyle(.sidebar)
                }
            } else {
                List {
                    ForEach(model.entries) { entry in
                        FileRowView(
                            entry: entry,
                            isExpanded: model.isExpanded(entry.url),
                            isSelected: filePreview.selectedURL == entry.url,
                            gitStatus: model.gitStatuses[entry.url.path],
                            onToggle: { handleTap(entry) }
                        )
                        .contextMenu {
                            fileContextMenu(url: entry.url, isDirectory: entry.isDirectory)
                        }
                        .draggable(entry.url)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onAppear { model.start(rootURL: rootURL) }
        .onChange(of: model.gitStatuses) { _, _ in
            filePreview.refresh()
        }
        .alert("New File", isPresented: $showNewFileDialog) {
            TextField("File name", text: $operationName)
            Button("Create") {
                if let dir = operationTargetURL {
                    if let newURL = model.createFile(named: operationName, in: dir) {
                        filePreview.select(newURL)
                    }
                }
                operationName = ""
                operationTargetURL = nil
            }
            Button("Cancel", role: .cancel) {
                operationName = ""
                operationTargetURL = nil
            }
        } message: {
            if let dir = operationTargetURL {
                Text("Create a new file in \(dir.lastPathComponent)/")
            }
        }
        .alert("New Folder", isPresented: $showNewFolderDialog) {
            TextField("Folder name", text: $operationName)
            Button("Create") {
                if let dir = operationTargetURL {
                    model.createFolder(named: operationName, in: dir)
                }
                operationName = ""
                operationTargetURL = nil
            }
            Button("Cancel", role: .cancel) {
                operationName = ""
                operationTargetURL = nil
            }
        } message: {
            if let dir = operationTargetURL {
                Text("Create a new folder in \(dir.lastPathComponent)/")
            }
        }
        .alert("Rename", isPresented: $showRenameDialog) {
            TextField("New name", text: $operationName)
            Button("Rename") {
                if let url = operationTargetURL {
                    let wasSelected = filePreview.selectedURL == url
                    if let newURL = model.renameItem(at: url, to: operationName), wasSelected {
                        filePreview.select(newURL)
                    }
                }
                operationName = ""
                operationTargetURL = nil
            }
            Button("Cancel", role: .cancel) {
                operationName = ""
                operationTargetURL = nil
            }
        } message: {
            if let url = operationTargetURL {
                Text("Rename \"\(url.lastPathComponent)\"")
            }
        }
        .alert("Move to Trash?", isPresented: $showDeleteConfirm) {
            Button("Move to Trash", role: .destructive) {
                if let url = operationTargetURL {
                    let wasSelected = filePreview.selectedURL == url
                    if model.deleteItem(at: url), wasSelected {
                        filePreview.closeTab(url)
                    }
                }
                operationTargetURL = nil
            }
            Button("Cancel", role: .cancel) {
                operationTargetURL = nil
            }
        } message: {
            if let url = operationTargetURL {
                Text("\"\(url.lastPathComponent)\" will be moved to the Trash.")
            }
        }
    }

    private func handleTap(_ entry: FileEntry) {
        if entry.isDirectory {
            model.toggleDirectory(entry)
        } else {
            filePreview.select(entry.url)
        }
    }

    private func relativePath(of url: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        if filePath.hasPrefix(rootPath) {
            var rel = String(filePath.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
            return rel
        }
        return url.lastPathComponent
    }

    @ViewBuilder
    private func fileContextMenu(url: URL, isDirectory: Bool) -> some View {
        if isDirectory {
            Button {
                operationTargetURL = url
                operationName = ""
                showNewFileDialog = true
            } label: {
                Label("New File…", systemImage: "doc.badge.plus")
            }

            Button {
                operationTargetURL = url
                operationName = ""
                showNewFolderDialog = true
            } label: {
                Label("New Folder…", systemImage: "folder.badge.plus")
            }

            Divider()
        }

        if !isDirectory {
            Button {
                terminalProxy.mentionFile(relativePath: relativePath(of: url))
            } label: {
                Label("Mention in Terminal", systemImage: "terminal")
            }

            Divider()
        }

        Button {
            operationTargetURL = url
            operationName = url.lastPathComponent
            showRenameDialog = true
        } label: {
            Label("Rename…", systemImage: "pencil")
        }

        Button(role: .destructive) {
            operationTargetURL = url
            showDeleteConfirm = true
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }

        Divider()

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(relativePath(of: url), forType: .string)
        } label: {
            Label("Copy Relative Path", systemImage: "doc.on.doc")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        } label: {
            Label("Copy Absolute Path", systemImage: "doc.on.doc.fill")
        }

        Divider()

        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        if !isDirectory {
            Divider()

            Button {
                ExternalEditorManager.openFile(url)
            } label: {
                if let editor = ExternalEditorManager.preferred {
                    Label("Open in \(editor.name)", systemImage: "square.and.pencil")
                } else {
                    Label("Open in Default App", systemImage: "square.and.pencil")
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let result: FileSearchResult
    let query: String
    let isSelected: Bool
    var gitStatus: GitFileStatus? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconForFile(result.name))
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 1) {
                Text(result.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !result.directoryPath.isEmpty {
                    Text(result.directoryPath)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            if let status = gitStatus {
                Circle()
                    .fill(status.color)
                    .frame(width: 6, height: 6)
                    .help(status.label)
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

    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":                       return "swift"
        case "js", "ts", "jsx", "tsx":      return "curlybraces"
        case "json":                        return "curlybraces.square"
        case "md", "txt":                   return "doc.text"
        case "py":                          return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh":           return "terminal"
        case "png", "jpg", "jpeg", "gif":   return "photo"
        case "yml", "yaml", "toml":         return "gearshape"
        default:                            return "doc"
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
