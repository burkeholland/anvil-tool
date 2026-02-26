import SwiftUI
import AppKit

struct FileTreeView: View {
    let rootURL: URL
    @ObservedObject var filePreview: FilePreviewModel
    @ObservedObject var model: FileTreeModel
    @ObservedObject var activityModel: ActivityFeedModel
    @EnvironmentObject var terminalProxy: TerminalInputProxy

    // File operation dialog state
    @State private var showNewFileDialog = false
    @State private var showNewFolderDialog = false
    @State private var showRenameDialog = false
    @State private var showDeleteConfirm = false
    @State private var operationTargetURL: URL?
    @State private var operationName = ""

    // Quick Look diff popover state
    @State private var quickLookURL: URL?
    @State private var quickLookDiff: FileDiff?
    @State private var treeScrollProxy: ScrollViewProxy?

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
                Button {
                    model.showChangedOnly.toggle()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 11, weight: .medium))
                        if model.showChangedOnly {
                            Text("\(model.changedFileCount)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                    }
                    .foregroundStyle(model.showChangedOnly ? Color.orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(model.showChangedOnly ? "Show All Files" : "Show Changed Files Only")
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
            } else if model.showChangedOnly && model.entries.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(.green.opacity(0.5))
                    Text("No changed files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.showChangedOnly = false
                    } label: {
                        Text("Show All Files")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(model.entries) { entry in
                            FileRowView(
                                entry: entry,
                                isExpanded: model.isExpanded(entry.url),
                                isSelected: filePreview.selectedURL == entry.url,
                                gitStatus: model.gitStatuses[entry.url.path],
                                dirChangeCount: entry.isDirectory ? model.dirChangeCounts[entry.url.path] : nil,
                                diffStat: entry.isDirectory ? nil : model.diffStats[entry.url.path],
                                pulseToken: activityModel.activePulses[entry.url.standardizedFileURL.path],
                                onToggle: { handleTap(entry) }
                            )
                            .id(entry.url)
                            .contextMenu {
                                fileContextMenu(url: entry.url, isDirectory: entry.isDirectory)
                            }
                            .draggable(entry.url)
                            .popover(
                                isPresented: Binding(
                                    get: { quickLookURL == entry.url },
                                    set: { if !$0 { dismissQuickLook() } }
                                ),
                                arrowEdge: .trailing
                            ) {
                                quickLookPopoverContent(for: entry.url)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .onKeyPress { keyPress in
                        handleTreeKeyPress(keyPress)
                    }
                    .onAppear { treeScrollProxy = proxy }
                    .onChange(of: model.revealTarget) { _, target in
                        if let target {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(target.url, anchor: .center)
                            }
                        }
                    }
                }
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

    // MARK: - Quick Look

    /// Flat list of modified (non-directory) file entries in current tree order.
    private var changedFileEntries: [FileEntry] {
        model.entries.filter {
            !$0.isDirectory && model.gitStatuses[$0.url.standardizedFileURL.path] != nil
        }
    }

    private func openQuickLook(for url: URL) {
        quickLookURL = url
        quickLookDiff = nil
        let root = rootURL
        DispatchQueue.global(qos: .userInteractive).async {
            let diff = DiffProvider.diff(for: url, in: root)
            DispatchQueue.main.async {
                guard self.quickLookURL == url else { return }
                self.quickLookDiff = diff
            }
        }
    }

    private func dismissQuickLook() {
        quickLookURL = nil
        quickLookDiff = nil
    }

    private func navigateQuickLook(forward: Bool) {
        let entries = changedFileEntries
        guard !entries.isEmpty else { return }
        let newEntry: FileEntry
        if let current = quickLookURL,
           let idx = entries.firstIndex(where: { $0.url == current }) {
            let newIdx = forward
                ? min(idx + 1, entries.count - 1)
                : max(idx - 1, 0)
            newEntry = entries[newIdx]
        } else {
            newEntry = forward ? entries[0] : entries[entries.count - 1]
        }
        filePreview.select(newEntry.url)
        openQuickLook(for: newEntry.url)
        treeScrollProxy?.scrollTo(newEntry.url, anchor: .center)
    }

    private func handleTreeKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.characters {
        case " ":
            if let url = filePreview.selectedURL {
                if quickLookURL == url {
                    dismissQuickLook()
                } else if model.gitStatuses[url.standardizedFileURL.path] != nil {
                    openQuickLook(for: url)
                }
            }
            return .handled
        default:
            guard quickLookURL != nil else { return .ignored }
            if keyPress.key == .downArrow || keyPress.key == .rightArrow {
                navigateQuickLook(forward: true)
                return .handled
            }
            if keyPress.key == .upArrow || keyPress.key == .leftArrow {
                navigateQuickLook(forward: false)
                return .handled
            }
            if keyPress.key == .escape {
                dismissQuickLook()
                return .handled
            }
            return .ignored
        }
    }

    @ViewBuilder
    private func quickLookPopoverContent(for url: URL) -> some View {
        if let diff = quickLookDiff {
            DiffPreviewPopover(
                diff: diff,
                onOpenFull: {
                    filePreview.select(url)
                    dismissQuickLook()
                }
            )
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading diff…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 200)
        }
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
                terminalProxy.addToContext(relativePath: relativePath(of: url))
            } label: {
                Label("Add to Copilot Context", systemImage: "scope")
            }

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

        Divider()

        Button {
            GitHubURLBuilder.openFile(rootURL: rootURL, relativePath: relativePath(of: url))
        } label: {
            Label("Open in GitHub", systemImage: "arrow.up.right.square")
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
    var dirChangeCount: Int? = nil
    var diffStat: DiffStat? = nil
    /// A token that changes each time this path receives a new activity pulse.
    /// When non-nil, the row plays a short green flash that fades out.
    var pulseToken: UUID? = nil
    let onToggle: () -> Void

    @State private var pulseOpacity: Double = 0

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

            if let count = dirChangeCount, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.orange.opacity(0.12))
                    )
            }

            if let stat = diffStat, stat.additions > 0 || stat.deletions > 0 {
                HStack(spacing: 3) {
                    if stat.additions > 0 {
                        Text("+\(stat.additions)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    if stat.deletions > 0 {
                        Text("-\(stat.deletions)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
            }

            if let status = gitStatus {
                Circle()
                    .fill(status.color)
                    .frame(width: 6, height: 6)
                    .help(entry.isDirectory ? status.label : "\(status.label) · Press Space for Quick Look diff")
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.2))
                : nil
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green.opacity((entry.isDirectory ? 0.15 : 0.3) * pulseOpacity))
        )
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .onChange(of: pulseToken) { _, token in
            if token != nil {
                withAnimation(.linear(duration: 0)) { pulseOpacity = 1.0 }
                withAnimation(.easeOut(duration: 2.5)) {
                    pulseOpacity = 0.0
                }
            } else {
                pulseOpacity = 0.0
            }
        }
    }
}
