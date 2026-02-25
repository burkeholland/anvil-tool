import SwiftUI

enum SidebarTab {
    case files
    case changes
    case activity
    case search
}

struct ContentView: View {
    @StateObject private var workingDirectory = WorkingDirectoryModel()
    @StateObject private var filePreview = FilePreviewModel()
    @StateObject private var changesModel = ChangesModel()
    @StateObject private var activityModel = ActivityFeedModel()
    @StateObject private var recentProjects = RecentProjectsModel()
    @StateObject private var terminalProxy = TerminalInputProxy()
    @StateObject private var quickOpenModel = QuickOpenModel()
    @StateObject private var searchModel = SearchModel()
    @StateObject private var terminalTabs = TerminalTabsModel()
    @StateObject private var commandPalette = CommandPaletteModel()
    @State private var notificationManager = AgentNotificationManager()
    @State private var sidebarWidth: CGFloat = 240
    @State private var previewWidth: CGFloat = 400
    @State private var showSidebar = true
    @State private var sidebarTab: SidebarTab = .files
    @State private var showQuickOpen = false
    @State private var showCommandPalette = false
    @State private var showBranchPicker = false
    @State private var showDiffSummary = false
    @State private var isDroppingFolder = false
    @AppStorage("autoFollowChanges") private var autoFollow = true
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 14
    @State private var isDroppingFileToTerminal = false

    var body: some View {
        ZStack {
            Group {
                if workingDirectory.directoryURL != nil {
                    projectView
                        .environmentObject(terminalProxy)
                } else {
                    WelcomeView(
                        recentProjects: recentProjects,
                        isDroppingFolder: isDroppingFolder,
                        onOpen: { url in openDirectory(url) },
                        onBrowse: { browseForDirectory() }
                    )
                }
            }

            // Command Palette overlay (available on all screens)
            if showCommandPalette {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { dismissCommandPalette() }

                VStack {
                    CommandPaletteView(
                        model: commandPalette,
                        onDismiss: { dismissCommandPalette() }
                    )
                    .padding(.top, 60)

                    Spacer()
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        } isTargeted: { targeted in
            isDroppingFolder = targeted
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(workingDirectory.projectName)
        .modifier(FocusedSceneModifier(
            showSidebar: $showSidebar,
            sidebarTab: $sidebarTab,
            autoFollow: $autoFollow,
            filePreview: filePreview,
            changesModel: changesModel,
            workingDirectory: workingDirectory,
            hasProject: workingDirectory.directoryURL != nil,
            onShowQuickOpen: { showQuickOpen = true },
            onFindInProject: {
                showSidebar = true
                sidebarTab = .search
            },
            onBrowse: { browseForDirectory() },
            onCloseProject: { closeCurrentProject() },
            onIncreaseFontSize: {
                terminalFontSize = min(terminalFontSize + 1, EmbeddedTerminalView.maxFontSize)
            },
            onDecreaseFontSize: {
                terminalFontSize = max(terminalFontSize - 1, EmbeddedTerminalView.minFontSize)
            },
            onResetFontSize: {
                terminalFontSize = EmbeddedTerminalView.defaultFontSize
            },
            onNewTerminalTab: {
                terminalTabs.addTab()
            },
            onFindInTerminal: {
                terminalProxy.showFindBar()
            },
            onShowCommandPalette: {
                buildCommandPalette()
                showCommandPalette = true
            },
            onNextChange: hasChangesToNavigate ? { navigateToNextChange() } : nil,
            onPreviousChange: hasChangesToNavigate ? { navigateToPreviousChange() } : nil,
            onReviewAllChanges: hasChangesToNavigate ? { showDiffSummary = true } : nil
        ))
        .onChange(of: workingDirectory.directoryURL) { _, newURL in
            filePreview.close()
            filePreview.rootDirectory = newURL
            terminalTabs.reset()
            if let url = newURL {
                recentProjects.recordOpen(url)
                changesModel.start(rootURL: url)
                activityModel.start(rootURL: url)
                searchModel.setRoot(url)
            }
        }
        .onChange(of: activityModel.latestFileChange) { _, change in
            guard autoFollow, let change = change else { return }
            filePreview.select(change.url)
        }
        .onAppear {
            filePreview.rootDirectory = workingDirectory.directoryURL
            notificationManager.connect(to: activityModel)
            if let url = workingDirectory.directoryURL {
                recentProjects.recordOpen(url)
                changesModel.start(rootURL: url)
                activityModel.start(rootURL: url)
                searchModel.setRoot(url)
            }
        }
    }

    private var projectView: some View {
        ZStack {
            HStack(spacing: 0) {
                if showSidebar {
                    SidebarView(
                        model: workingDirectory,
                        filePreview: filePreview,
                        changesModel: changesModel,
                        activityModel: activityModel,
                        searchModel: searchModel,
                        activeTab: $sidebarTab,
                        onReviewAll: { showDiffSummary = true }
                    )
                        .frame(width: max(sidebarWidth, 0))

                    PanelDivider(
                        width: $sidebarWidth,
                        minWidth: 140,
                        maxWidth: 500,
                        edge: .leading
                    )
                }

                VStack(spacing: 0) {
                    ToolbarView(
                        workingDirectory: workingDirectory,
                        changesModel: changesModel,
                        activityModel: activityModel,
                        showSidebar: $showSidebar,
                        autoFollow: $autoFollow,
                        showBranchPicker: $showBranchPicker,
                        onOpenDirectory: { browseForDirectory() }
                    )

                    if terminalTabs.tabs.count > 1 {
                        TerminalTabBar(model: terminalTabs) {
                            terminalTabs.addTab()
                        }
                    }

                    ZStack {
                        ForEach(terminalTabs.tabs) { tab in
                            EmbeddedTerminalView(
                                workingDirectory: workingDirectory,
                                launchCopilotOverride: tab.launchCopilot,
                                isActiveTab: tab.id == terminalTabs.activeTabID
                            )
                            .opacity(tab.id == terminalTabs.activeTabID ? 1 : 0)
                            .allowsHitTesting(tab.id == terminalTabs.activeTabID)
                        }

                        // Drop overlay for file → terminal @ mentions
                        if isDroppingFileToTerminal {
                            VStack(spacing: 6) {
                                Image(systemName: "at")
                                    .font(.system(size: 28, weight: .medium))
                                Text("Drop to @mention in terminal")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.accentColor.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                            )
                            .allowsHitTesting(false)
                        }
                    }
                    .id(workingDirectory.directoryURL)
                    .dropDestination(for: URL.self) { urls, _ in
                        handleTerminalFileDrop(urls)
                    } isTargeted: { targeted in
                        isDroppingFileToTerminal = targeted
                    }

                    StatusBarView(
                        workingDirectory: workingDirectory,
                        filePreview: filePreview,
                        changesModel: changesModel
                    )
                }

                if filePreview.selectedURL != nil || showDiffSummary {
                    PanelDivider(
                        width: $previewWidth,
                        minWidth: 200,
                        maxWidth: 800,
                        edge: .trailing
                    )

                    VStack(spacing: 0) {
                        if showDiffSummary {
                            DiffSummaryView(
                                changesModel: changesModel,
                                onSelectFile: { url in
                                    showDiffSummary = false
                                    filePreview.select(url)
                                },
                                onDismiss: { showDiffSummary = false }
                            )
                        } else {
                            if let idx = currentChangeIndex {
                                ChangesNavigationBar(
                                    currentIndex: idx,
                                    totalCount: changesModel.changedFiles.count,
                                    onPrevious: { navigateToPreviousChange() },
                                    onNext: { navigateToNextChange() }
                                )
                            }

                            FilePreviewView(model: filePreview)
                        }
                    }
                    .frame(width: max(previewWidth, 0))
                }
            }

            // Quick Open overlay
            if showQuickOpen {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { dismissQuickOpen() }

                VStack {
                    QuickOpenView(
                        model: quickOpenModel,
                        filePreview: filePreview,
                        onDismiss: { dismissQuickOpen() }
                    )
                    .padding(.top, 60)

                    Spacer()
                }
            }

            // Drop overlay
            if isDroppingFolder {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .background(Color.accentColor.opacity(0.05))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: showQuickOpen) { _, isShowing in
            if isShowing, let url = workingDirectory.directoryURL {
                quickOpenModel.index(rootURL: url)
            }
        }
    }

    private func openDirectory(_ url: URL) {
        // Validate directory still exists before switching
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            recentProjects.remove(
                RecentProjectsModel.RecentProject(path: url.standardizedFileURL.path, name: url.lastPathComponent, lastOpened: Date())
            )
            return
        }
        workingDirectory.setDirectory(url)
    }

    private func browseForDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a working directory for the Copilot CLI"
        if panel.runModal() == .OK, let url = panel.url {
            openDirectory(url)
        }
    }

    private func dismissQuickOpen() {
        showQuickOpen = false
        quickOpenModel.reset()
    }

    private func dismissCommandPalette() {
        showCommandPalette = false
        commandPalette.reset()
    }

    private func buildCommandPalette() {
        let hasProject = workingDirectory.directoryURL != nil
        commandPalette.register([
            // Navigation
            PaletteCommand(id: "quick-open", title: "Quick Open File…", icon: "doc.text.magnifyingglass", shortcut: "⌘⇧O", category: "Navigation") {
                hasProject
            } action: { [weak quickOpenModel] in
                if let url = workingDirectory.directoryURL {
                    quickOpenModel?.index(rootURL: url)
                }
                showQuickOpen = true
            },
            PaletteCommand(id: "find-in-project", title: "Find in Project…", icon: "magnifyingglass", shortcut: "⌘⇧F", category: "Navigation") {
                hasProject
            } action: {
                showSidebar = true
                sidebarTab = .search
            },
            PaletteCommand(id: "find-in-terminal", title: "Find in Terminal…", icon: "text.magnifyingglass", shortcut: "⌘F", category: "Navigation") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.showFindBar()
            },

            // View
            PaletteCommand(id: "toggle-sidebar", title: "Toggle Sidebar", icon: "sidebar.leading", shortcut: "⌘B", category: "View") {
                true
            } action: {
                showSidebar.toggle()
            },
            PaletteCommand(id: "show-files", title: "Show Files", icon: "folder", shortcut: "⌘1", category: "View") {
                hasProject
            } action: {
                showSidebar = true
                sidebarTab = .files
            },
            PaletteCommand(id: "show-changes", title: "Show Changes", icon: "arrow.triangle.2.circlepath", shortcut: "⌘2", category: "View") {
                hasProject
            } action: {
                showSidebar = true
                sidebarTab = .changes
            },
            PaletteCommand(id: "show-activity", title: "Show Activity", icon: "clock", shortcut: "⌘3", category: "View") {
                hasProject
            } action: {
                showSidebar = true
                sidebarTab = .activity
            },
            PaletteCommand(id: "show-search", title: "Show Search", icon: "magnifyingglass", shortcut: "⌘4", category: "View") {
                hasProject
            } action: {
                showSidebar = true
                sidebarTab = .search
            },
            PaletteCommand(id: "toggle-auto-follow", title: autoFollow ? "Disable Auto-Follow" : "Enable Auto-Follow", icon: autoFollow ? "eye.slash" : "eye", shortcut: nil, category: "View") {
                true
            } action: {
                autoFollow.toggle()
            },

            // Terminal
            PaletteCommand(id: "new-terminal-tab", title: "New Terminal Tab", icon: "plus.rectangle", shortcut: "⌘T", category: "Terminal") {
                hasProject
            } action: { [weak terminalTabs] in
                terminalTabs?.addTab()
            },
            PaletteCommand(id: "increase-font", title: "Increase Font Size", icon: "plus.magnifyingglass", shortcut: "⌘+", category: "Terminal") {
                true
            } action: {
                terminalFontSize = min(terminalFontSize + 1, EmbeddedTerminalView.maxFontSize)
            },
            PaletteCommand(id: "decrease-font", title: "Decrease Font Size", icon: "minus.magnifyingglass", shortcut: "⌘-", category: "Terminal") {
                true
            } action: {
                terminalFontSize = max(terminalFontSize - 1, EmbeddedTerminalView.minFontSize)
            },
            PaletteCommand(id: "reset-font", title: "Reset Font Size", icon: "textformat.size", shortcut: "⌘0", category: "Terminal") {
                true
            } action: {
                terminalFontSize = EmbeddedTerminalView.defaultFontSize
            },

            // File
            PaletteCommand(id: "open-directory", title: "Open Directory…", icon: "folder.badge.plus", shortcut: "⌘O", category: "File") {
                true
            } action: {
                browseForDirectory()
            },
            PaletteCommand(id: "close-tab", title: "Close Preview Tab", icon: "xmark", shortcut: "⌘W", category: "File") {
                filePreview.selectedURL != nil
            } action: { [weak filePreview] in
                if let url = filePreview?.selectedURL {
                    filePreview?.closeTab(url)
                }
            },
            PaletteCommand(id: "close-project", title: "Close Project", icon: "xmark.circle", shortcut: "⌘⇧W", category: "File") {
                hasProject
            } action: {
                closeCurrentProject()
            },

            // Actions
            PaletteCommand(id: "refresh", title: "Refresh Changes", icon: "arrow.clockwise", shortcut: "⌘⇧R", category: "Actions") {
                hasProject
            } action: { [weak changesModel, weak workingDirectory] in
                if let url = workingDirectory?.directoryURL {
                    changesModel?.start(rootURL: url)
                }
            },

            PaletteCommand(id: "review-all", title: "Review All Changes", icon: "doc.text.magnifyingglass", shortcut: "⌘⇧D", category: "Actions") {
                hasProject && !changesModel.changedFiles.isEmpty
            } action: {
                showDiffSummary = true
            },

            PaletteCommand(id: "next-change", title: "Next Changed File", icon: "chevron.down", shortcut: "⌃⌘↓", category: "Actions") {
                hasChangesToNavigate
            } action: {
                navigateToNextChange()
            },

            PaletteCommand(id: "prev-change", title: "Previous Changed File", icon: "chevron.up", shortcut: "⌃⌘↑", category: "Actions") {
                hasChangesToNavigate
            } action: {
                navigateToPreviousChange()
            },

            // Git
            PaletteCommand(id: "switch-branch", title: "Switch Branch…", icon: "arrow.triangle.branch", shortcut: nil, category: "Git") {
                hasProject && workingDirectory.gitBranch != nil
            } action: {
                showBranchPicker = true
            },

            PaletteCommand(id: "discard-all", title: "Discard All Changes", icon: "arrow.uturn.backward", shortcut: nil, category: "Git") {
                hasProject && !changesModel.changedFiles.isEmpty
            } action: { [weak changesModel] in
                changesModel?.discardAll()
            },

            PaletteCommand(id: "git-push", title: "Push", icon: "arrow.up", shortcut: nil, category: "Git") {
                hasProject && workingDirectory.hasRemotes && !workingDirectory.isPushing
            } action: { [weak workingDirectory] in
                workingDirectory?.push()
            },

            PaletteCommand(id: "git-pull", title: "Pull", icon: "arrow.down", shortcut: nil, category: "Git") {
                hasProject && workingDirectory.hasUpstream && !workingDirectory.isPulling
            } action: { [weak workingDirectory] in
                workingDirectory?.pull()
            },

            PaletteCommand(id: "git-fetch", title: "Fetch", icon: "arrow.clockwise", shortcut: nil, category: "Git") {
                hasProject && workingDirectory.hasRemotes
            } action: { [weak workingDirectory] in
                workingDirectory?.fetch()
            },
        ])
    }

    private func closeCurrentProject() {
        filePreview.close()
        showDiffSummary = false
        changesModel.stop()
        activityModel.stop()
        searchModel.clear()
        terminalTabs.reset()
        workingDirectory.closeProject()
    }

    // MARK: - Changes Navigation

    /// The index of the currently previewed file within the changed files list, or nil.
    private var currentChangeIndex: Int? {
        guard let selected = filePreview.selectedURL else { return nil }
        return changesModel.changedFiles.firstIndex(where: { $0.url == selected })
    }

    private var hasChangesToNavigate: Bool {
        !changesModel.changedFiles.isEmpty && workingDirectory.directoryURL != nil
    }

    private func navigateToNextChange() {
        let files = changesModel.changedFiles
        guard !files.isEmpty else { return }
        let nextIndex: Int
        if let current = currentChangeIndex {
            nextIndex = (current + 1) % files.count
        } else {
            nextIndex = 0
        }
        showSidebar = true
        sidebarTab = .changes
        filePreview.select(files[nextIndex].url)
    }

    private func navigateToPreviousChange() {
        let files = changesModel.changedFiles
        guard !files.isEmpty else { return }
        let prevIndex: Int
        if let current = currentChangeIndex {
            prevIndex = current > 0 ? current - 1 : files.count - 1
        } else {
            prevIndex = files.count - 1
        }
        showSidebar = true
        sidebarTab = .changes
        filePreview.select(files[prevIndex].url)
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return false
        }
        if isDir.boolValue {
            openDirectory(url)
            return true
        } else {
            // Dropped a file — open its parent directory and preview the file
            let parent = url.deletingLastPathComponent()
            openDirectory(parent)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak workingDirectory, weak filePreview] in
                guard workingDirectory?.directoryURL == parent else { return }
                filePreview?.select(url)
            }
            return true
        }
    }

    /// Handles file drops on the terminal area.
    /// Project files → @mention in terminal. External files → open as project.
    private func handleTerminalFileDrop(_ urls: [URL]) -> Bool {
        guard let rootURL = workingDirectory.directoryURL else {
            return handleDrop(urls)
        }
        let rootPath = rootURL.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        var mentioned = false
        for url in urls {
            let filePath = url.standardizedFileURL.path
            if filePath.hasPrefix(rootPrefix) {
                let relativePath = String(filePath.dropFirst(rootPrefix.count))
                if !relativePath.isEmpty {
                    terminalProxy.mentionFile(relativePath: relativePath)
                    mentioned = true
                }
            }
        }

        if mentioned { return true }

        // Non-project files fall through to standard drop behavior
        return handleDrop(urls)
    }
}

struct ToolbarView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @ObservedObject var changesModel: ChangesModel
    @ObservedObject var activityModel: ActivityFeedModel
    @Binding var showSidebar: Bool
    @Binding var autoFollow: Bool
    @Binding var showBranchPicker: Bool
    var onOpenDirectory: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                showSidebar.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .buttonStyle(.borderless)
            .help("Toggle Sidebar (⌘B)")

            Divider()
                .frame(height: 16)

            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(workingDirectory.displayPath)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)

            if let branch = workingDirectory.gitBranch {
                Divider()
                    .frame(height: 16)

                Button {
                    showBranchPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(branch)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .help("Switch Branch")
                .popover(isPresented: $showBranchPicker, arrowEdge: .bottom) {
                    if let rootURL = workingDirectory.directoryURL {
                        BranchPickerView(
                            rootURL: rootURL,
                            currentBranch: workingDirectory.gitBranch,
                            onDismiss: { showBranchPicker = false },
                            onBranchChanged: {
                                changesModel.refresh()
                            }
                        )
                    }
                }
            }

            Spacer()

            AgentActivityIndicator(activityModel: activityModel)

            Button {
                autoFollow.toggle()
            } label: {
                Image(systemName: autoFollow ? "eye" : "eye.slash")
                    .foregroundStyle(autoFollow ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .help(autoFollow ? "Auto-Follow Changes: On" : "Auto-Follow Changes: Off")

            Button("Open…") {
                onOpenDirectory()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct SidebarView: View {
    @ObservedObject var model: WorkingDirectoryModel
    @ObservedObject var filePreview: FilePreviewModel
    @ObservedObject var changesModel: ChangesModel
    @ObservedObject var activityModel: ActivityFeedModel
    @ObservedObject var searchModel: SearchModel
    @Binding var activeTab: SidebarTab
    var onReviewAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                SidebarTabButton(
                    title: "Files",
                    systemImage: "folder",
                    isActive: activeTab == .files
                ) {
                    activeTab = .files
                }

                SidebarTabButton(
                    title: "Changes",
                    systemImage: "arrow.triangle.2.circlepath",
                    isActive: activeTab == .changes,
                    badge: changesModel.changedFiles.isEmpty ? nil : changesModel.changedFiles.count
                ) {
                    activeTab = .changes
                }

                SidebarTabButton(
                    title: "Activity",
                    systemImage: "clock",
                    isActive: activeTab == .activity,
                    badge: activityModel.events.isEmpty ? nil : activityModel.events.count
                ) {
                    activeTab = .activity
                }

                SidebarTabButton(
                    title: "Search",
                    systemImage: "magnifyingglass",
                    isActive: activeTab == .search
                ) {
                    activeTab = .search
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Content
            switch activeTab {
            case .files:
                if let rootURL = model.directoryURL {
                    FileTreeView(rootURL: rootURL, filePreview: filePreview)
                        .id(rootURL)
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No directory selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Use Open… to choose a project")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }

            case .changes:
                ChangesListView(model: changesModel, filePreview: filePreview, workingDirectory: model, onReviewAll: onReviewAll)

            case .activity:
                ActivityFeedView(model: activityModel, filePreview: filePreview)

            case .search:
                SearchView(model: searchModel, filePreview: filePreview)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct SidebarTabButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    var badge: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))

                if let badge = badge {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isActive
                    ? RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor))
                    : nil
            )
        }
        .buttonStyle(.plain)
    }
}

/// Extracts focusedSceneValue modifiers to reduce type-checker complexity in ContentView.body.
/// Split into two modifiers so neither exceeds the Swift type-checker expression limit.
private struct FocusedSceneModifier: ViewModifier {
    @Binding var showSidebar: Bool
    @Binding var sidebarTab: SidebarTab
    @Binding var autoFollow: Bool
    var filePreview: FilePreviewModel
    var changesModel: ChangesModel
    var workingDirectory: WorkingDirectoryModel
    var hasProject: Bool
    var onShowQuickOpen: () -> Void
    var onFindInProject: () -> Void
    var onBrowse: () -> Void
    var onCloseProject: () -> Void
    var onIncreaseFontSize: () -> Void
    var onDecreaseFontSize: () -> Void
    var onResetFontSize: () -> Void
    var onNewTerminalTab: () -> Void
    var onFindInTerminal: () -> Void
    var onShowCommandPalette: () -> Void
    var onNextChange: (() -> Void)?
    var onPreviousChange: (() -> Void)?
    var onReviewAllChanges: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .modifier(FocusedSceneModifierA(
                showSidebar: $showSidebar,
                sidebarTab: $sidebarTab,
                autoFollow: $autoFollow,
                filePreview: filePreview,
                changesModel: changesModel,
                workingDirectory: workingDirectory,
                hasProject: hasProject,
                onShowQuickOpen: onShowQuickOpen,
                onFindInProject: onFindInProject,
                onBrowse: onBrowse
            ))
            .modifier(FocusedSceneModifierB(
                hasProject: hasProject,
                onCloseProject: onCloseProject,
                onIncreaseFontSize: onIncreaseFontSize,
                onDecreaseFontSize: onDecreaseFontSize,
                onResetFontSize: onResetFontSize,
                onNewTerminalTab: onNewTerminalTab,
                onFindInTerminal: onFindInTerminal,
                onShowCommandPalette: onShowCommandPalette,
                onNextChange: onNextChange,
                onPreviousChange: onPreviousChange,
                onReviewAllChanges: onReviewAllChanges
            ))
    }
}

private struct FocusedSceneModifierA: ViewModifier {
    @Binding var showSidebar: Bool
    @Binding var sidebarTab: SidebarTab
    @Binding var autoFollow: Bool
    var filePreview: FilePreviewModel
    var changesModel: ChangesModel
    var workingDirectory: WorkingDirectoryModel
    var hasProject: Bool
    var onShowQuickOpen: () -> Void
    var onFindInProject: () -> Void
    var onBrowse: () -> Void

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.sidebarVisible, $showSidebar)
            .focusedSceneValue(\.sidebarTab, $sidebarTab)
            .focusedSceneValue(\.previewOpen, filePreview.selectedURL != nil)
            .focusedSceneValue(\.closePreview, { [weak filePreview] in
                if let url = filePreview?.selectedURL {
                    filePreview?.closeTab(url)
                }
            })
            .focusedSceneValue(\.openDirectory, onBrowse)
            .focusedSceneValue(\.refresh, { [weak changesModel, weak workingDirectory] in
                if let url = workingDirectory?.directoryURL {
                    changesModel?.start(rootURL: url)
                }
            })
            .focusedSceneValue(\.quickOpen, hasProject ? onShowQuickOpen : nil)
            .focusedSceneValue(\.autoFollow, $autoFollow)
            .focusedSceneValue(\.findInProject, hasProject ? onFindInProject : nil)
    }
}

private struct FocusedSceneModifierB: ViewModifier {
    var hasProject: Bool
    var onCloseProject: () -> Void
    var onIncreaseFontSize: () -> Void
    var onDecreaseFontSize: () -> Void
    var onResetFontSize: () -> Void
    var onNewTerminalTab: () -> Void
    var onFindInTerminal: () -> Void
    var onShowCommandPalette: () -> Void
    var onNextChange: (() -> Void)?
    var onPreviousChange: (() -> Void)?
    var onReviewAllChanges: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.closeProject, hasProject ? onCloseProject : nil)
            .focusedSceneValue(\.increaseFontSize, onIncreaseFontSize)
            .focusedSceneValue(\.decreaseFontSize, onDecreaseFontSize)
            .focusedSceneValue(\.resetFontSize, onResetFontSize)
            .focusedSceneValue(\.newTerminalTab, hasProject ? onNewTerminalTab : nil)
            .focusedSceneValue(\.findInTerminal, hasProject ? onFindInTerminal : nil)
            .focusedSceneValue(\.showCommandPalette, onShowCommandPalette)
            .focusedSceneValue(\.nextChange, onNextChange)
            .focusedSceneValue(\.previousChange, onPreviousChange)
            .focusedSceneValue(\.reviewAllChanges, onReviewAllChanges)
    }
}

/// Compact navigation bar shown above the file preview when the selected file is a changed file.
/// Shows position (e.g. "3 of 7 changes") with previous/next buttons.
struct ChangesNavigationBar: View {
    let currentIndex: Int
    let totalCount: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(.orange)

            Text("\(currentIndex + 1) of \(totalCount) change\(totalCount == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                onPrevious()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Previous Changed File (⌃⌘↑)")

            Button {
                onNext()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Next Changed File (⌃⌘↓)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Compact indicator in the toolbar showing whether the agent is actively making changes.
struct AgentActivityIndicator: View {
    @ObservedObject var activityModel: ActivityFeedModel
    @State private var isPulsing = false

    var body: some View {
        if activityModel.sessionStats.isActive {
            HStack(spacing: 5) {
                Circle()
                    .fill(activityModel.isAgentActive ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
                    .scaleEffect(isPulsing && activityModel.isAgentActive ? 1.3 : 1.0)
                    .animation(
                        activityModel.isAgentActive
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )
                    .onChange(of: activityModel.isAgentActive) { _, active in
                        isPulsing = active
                    }

                VStack(alignment: .leading, spacing: 0) {
                    if activityModel.isAgentActive, let change = activityModel.latestFileChange {
                        Text(change.url.lastPathComponent)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    } else {
                        Text(summaryText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(activityModel.isAgentActive
                          ? Color.green.opacity(0.08)
                          : Color.clear)
            )
            .help(activityModel.isAgentActive ? "Agent is actively making changes" : "Agent idle — \(activityModel.sessionStats.totalFilesTouched) files touched this session")
        }
    }

    private var summaryText: String {
        let stats = activityModel.sessionStats
        var parts: [String] = []
        parts.append("\(stats.totalFilesTouched) file\(stats.totalFilesTouched == 1 ? "" : "s")")
        if stats.commitCount > 0 {
            parts.append("\(stats.commitCount) commit\(stats.commitCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}
