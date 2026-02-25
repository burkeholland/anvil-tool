import SwiftUI

enum SidebarTab: String {
    case files
    case changes
    case activity
    case search
    case history
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
    @StateObject private var fileTreeModel = FileTreeModel()
    @StateObject private var branchDiffModel = BranchDiffModel()
    @StateObject private var commitHistoryModel = CommitHistoryModel()
    @State private var notificationManager = AgentNotificationManager()
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240
    @AppStorage("previewWidth") private var previewWidth: Double = 400
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("sidebarTab") private var sidebarTab: SidebarTab = .files
    @State private var showQuickOpen = false
    @State private var showMentionPicker = false
    @State private var showCommandPalette = false
    @State private var showBranchPicker = false
    @State private var showDiffSummary = false
    @State private var isDroppingFolder = false
    @AppStorage("autoFollowChanges") private var autoFollow = true
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 14
    @StateObject private var buildVerifier = BuildVerifier()
    @State private var isDroppingFileToTerminal = false
    @State private var showTaskBanner = false
    @State private var showKeyboardShortcuts = false
    @State private var showInstructions = false
    @State private var showCopilotActions = false
    @State private var showProjectSwitcher = false
    @State private var showBranchDiff = false
    @State private var showCloneSheet = false
    @State private var showCreatePR = false

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

            // Keyboard shortcuts overlay
            if showKeyboardShortcuts {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { showKeyboardShortcuts = false }

                KeyboardShortcutsView(onDismiss: { showKeyboardShortcuts = false })
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
            onShowQuickOpen: {
                showMentionPicker = false
                showQuickOpen = true
            },
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
            onNewCopilotTab: {
                terminalTabs.addCopilotTab()
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
            onReviewAllChanges: hasChangesToNavigate ? { showDiffSummary = true } : nil,
            onShowKeyboardShortcuts: { showKeyboardShortcuts = true },
            onGoToLine: (filePreview.selectedURL != nil && filePreview.fileContent != nil && filePreview.activeTab == .source) ? {
                filePreview.showGoToLine = true
            } : nil,
            onRevealInTree: filePreview.selectedURL != nil ? {
                if let url = filePreview.selectedURL {
                    revealInFileTree(url)
                }
            } : nil,
            onMentionInTerminal: workingDirectory.directoryURL != nil ? {
                showQuickOpen = false
                showMentionPicker = true
            } : nil,
            onCloneRepository: { showCloneSheet = true },
            onSplitTerminalH: workingDirectory.directoryURL != nil ? {
                terminalTabs.splitPane(direction: .horizontal)
            } : nil,
            onSplitTerminalV: workingDirectory.directoryURL != nil ? {
                terminalTabs.splitPane(direction: .vertical)
            } : nil
        ))
        .onChange(of: workingDirectory.directoryURL) { _, newURL in
            showTaskBanner = false
            buildVerifier.cancel()
            filePreview.close(persist: false)
            filePreview.rootDirectory = newURL
            terminalTabs.reset()
            if let url = newURL {
                recentProjects.recordOpen(url)
                changesModel.start(rootURL: url)
                activityModel.start(rootURL: url)
                searchModel.setRoot(url)
                fileTreeModel.start(rootURL: url)
                commitHistoryModel.start(rootURL: url)
            }
        }
        .onChange(of: activityModel.latestFileChange) { _, change in
            guard autoFollow, activityModel.isAgentActive, let change = change else { return }
            filePreview.autoFollowChange(to: change.url)
            revealInFileTree(change.url)
        }
        .onChange(of: filePreview.selectedURL) { _, newURL in
            // Keep tree expanded to the selected file regardless of how it was opened
            if let url = newURL {
                fileTreeModel.revealFile(url: url)
            }
        }
        .onChange(of: activityModel.isAgentActive) { wasActive, isActive in
            if wasActive && !isActive && activityModel.sessionStats.totalFilesTouched > 0 {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showTaskBanner = true
                }
                if let url = workingDirectory.directoryURL {
                    buildVerifier.run(at: url)
                }
            } else if isActive {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showTaskBanner = false
                }
                buildVerifier.cancel()
            }
        }
        .onAppear {
            filePreview.rootDirectory = workingDirectory.directoryURL
            notificationManager.connect(to: activityModel)
            if let url = workingDirectory.directoryURL {
                recentProjects.recordOpen(url)
                changesModel.start(rootURL: url)
                activityModel.start(rootURL: url)
                searchModel.setRoot(url)
                fileTreeModel.start(rootURL: url)
                commitHistoryModel.start(rootURL: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openDirectoryNotification)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                openDirectory(url)
            }
        }
        .sheet(isPresented: $showCloneSheet) {
            CloneRepositoryView(
                onCloned: { url in openDirectory(url) },
                onDismiss: { showCloneSheet = false }
            )
        }
        .sheet(isPresented: $showCreatePR) {
            CreatePullRequestView(
                workingDirectory: workingDirectory,
                changesModel: changesModel,
                onDismiss: { showCreatePR = false }
            )
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
                        fileTreeModel: fileTreeModel,
                        commitHistoryModel: commitHistoryModel,
                        activeTab: $sidebarTab,
                        onReviewAll: { showDiffSummary = true },
                        onBranchDiff: {
                            if let url = workingDirectory.directoryURL {
                                branchDiffModel.load(rootURL: url)
                            }
                            showDiffSummary = false
                            showBranchDiff = true
                        },
                        onCreatePR: { showCreatePR = true }
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
                        filePreview: filePreview,
                        recentProjects: recentProjects,
                        showSidebar: $showSidebar,
                        autoFollow: $autoFollow,
                        showBranchPicker: $showBranchPicker,
                        showInstructions: $showInstructions,
                        showCopilotActions: $showCopilotActions,
                        showProjectSwitcher: $showProjectSwitcher,
                        onOpenDirectory: { browseForDirectory() },
                        onSwitchProject: { url in openDirectory(url) },
                        onCloneRepository: { showCloneSheet = true }
                    )

                    TerminalTabBar(
                        model: terminalTabs,
                        onNewShellTab: { terminalTabs.addTab() },
                        onNewCopilotTab: { terminalTabs.addCopilotTab() },
                        onSplitHorizontally: { terminalTabs.splitPane(direction: .horizontal) },
                        onSplitVertically: { terminalTabs.splitPane(direction: .vertical) },
                        onCloseSplit: { terminalTabs.closeSplit() }
                    )

                    Group {
                        if terminalTabs.isSplit, let splitTab = terminalTabs.splitTab {
                            let primaryPane = ZStack {
                                ForEach(terminalTabs.tabs) { tab in
                                    EmbeddedTerminalView(
                                        workingDirectory: workingDirectory,
                                        launchCopilotOverride: tab.launchCopilot,
                                        isActiveTab: tab.id == terminalTabs.activeTabID,
                                        onTitleChange: { title in
                                            terminalTabs.updateTitle(for: tab.id, to: title)
                                        },
                                        onOpenFile: { url, line in
                                            filePreview.select(url, line: line)
                                        }
                                    )
                                    .opacity(tab.id == terminalTabs.activeTabID ? 1 : 0)
                                    .allowsHitTesting(tab.id == terminalTabs.activeTabID)
                                }
                            }

                            let splitPane = VStack(spacing: 0) {
                                // Mini header for the split pane
                                HStack(spacing: 6) {
                                    Image(systemName: splitTab.launchCopilot ? "sparkle" : "terminal")
                                        .font(.system(size: 10))
                                        .foregroundStyle(splitTab.launchCopilot ? .purple : .secondary)
                                    Text(splitTab.title)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        terminalTabs.closeSplit()
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 16, height: 16)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Close Split")
                                    .padding(.trailing, 6)
                                }
                                .padding(.leading, 10)
                                .frame(height: 26)
                                .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)))
                                .overlay(alignment: .bottom) { Divider().opacity(0.3) }

                                EmbeddedTerminalView(
                                    workingDirectory: workingDirectory,
                                    launchCopilotOverride: splitTab.launchCopilot,
                                    isActiveTab: false,
                                    onTitleChange: { title in
                                        terminalTabs.updateSplitTitle(to: title)
                                    },
                                    onOpenFile: { url, line in
                                        filePreview.select(url, line: line)
                                    }
                                )
                                .id(splitTab.id)
                            }

                            if terminalTabs.splitDirection == .horizontal {
                                HSplitView {
                                    primaryPane
                                    splitPane
                                }
                            } else {
                                VSplitView {
                                    primaryPane
                                    splitPane
                                }
                            }
                        } else {
                            ZStack {
                                ForEach(terminalTabs.tabs) { tab in
                                    EmbeddedTerminalView(
                                        workingDirectory: workingDirectory,
                                        launchCopilotOverride: tab.launchCopilot,
                                        isActiveTab: tab.id == terminalTabs.activeTabID,
                                        onTitleChange: { title in
                                            terminalTabs.updateTitle(for: tab.id, to: title)
                                        },
                                        onOpenFile: { url, line in
                                            filePreview.select(url, line: line)
                                        }
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
                        }
                    }

                    if showTaskBanner {
                        TaskCompleteBanner(
                            changedFileCount: changesModel.changedFiles.count,
                            totalAdditions: changesModel.totalAdditions,
                            totalDeletions: changesModel.totalDeletions,
                            buildStatus: buildVerifier.status,
                            onReviewAll: {
                                showDiffSummary = true
                                showTaskBanner = false
                            },
                            onStageAllAndCommit: {
                                changesModel.commitMessage = changesModel.generateCommitMessage(allFiles: true)
                                changesModel.stageAll()
                                sidebarTab = .changes
                                showTaskBanner = false
                            },
                            onNewTask: {
                                if let tv = terminalProxy.terminalView {
                                    tv.window?.makeFirstResponder(tv)
                                }
                                showTaskBanner = false
                            },
                            onDismiss: {
                                showTaskBanner = false
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    StatusBarView(
                        workingDirectory: workingDirectory,
                        filePreview: filePreview,
                        changesModel: changesModel
                    )
                }

                if filePreview.selectedURL != nil || showDiffSummary || showBranchDiff {
                    PanelDivider(
                        width: $previewWidth,
                        minWidth: 200,
                        maxWidth: 800,
                        edge: .trailing
                    )

                    VStack(spacing: 0) {
                        if showBranchDiff {
                            BranchDiffView(
                                model: branchDiffModel,
                                onSelectFile: { path, _ in
                                    showBranchDiff = false
                                    if let root = workingDirectory.directoryURL {
                                        let url = root.appendingPathComponent(path)
                                        filePreview.select(url)
                                    }
                                },
                                onDismiss: { showBranchDiff = false }
                            )
                        } else if showDiffSummary {
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

                            FilePreviewView(model: filePreview, changesModel: changesModel)
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

            // Mention file picker overlay (⌘M)
            if showMentionPicker {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { dismissMentionPicker() }

                VStack {
                    QuickOpenView(
                        model: quickOpenModel,
                        filePreview: filePreview,
                        onDismiss: { dismissMentionPicker() },
                        onMentionSelect: { result in
                            terminalProxy.mentionFile(relativePath: result.relativePath)
                        }
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
                quickOpenModel.index(rootURL: url, recentURLs: filePreview.recentlyViewedURLs)
            }
        }
        .onChange(of: showMentionPicker) { _, isShowing in
            if isShowing, let url = workingDirectory.directoryURL {
                quickOpenModel.index(rootURL: url, recentURLs: filePreview.recentlyViewedURLs)
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

    private func dismissMentionPicker() {
        showMentionPicker = false
        quickOpenModel.reset()
    }

    private func dismissCommandPalette() {
        showCommandPalette = false
        commandPalette.reset()
    }

    /// Switches sidebar to Files tab and scrolls the file tree to the given file.
    private func revealInFileTree(_ url: URL) {
        sidebarTab = .files
        showSidebar = true
        fileTreeModel.revealFile(url: url)
    }

    private func buildCommandPalette() {
        let hasProject = workingDirectory.directoryURL != nil
        commandPalette.register([
            // Navigation
            PaletteCommand(id: "quick-open", title: "Quick Open File…", icon: "doc.text.magnifyingglass", shortcut: "⌘⇧O", category: "Navigation") {
                hasProject
            } action: { [weak quickOpenModel, weak filePreview] in
                if let url = workingDirectory.directoryURL {
                    quickOpenModel?.index(rootURL: url, recentURLs: filePreview?.recentlyViewedURLs ?? [])
                }
                showMentionPicker = false
                showQuickOpen = true
            },
            PaletteCommand(id: "mention-file", title: "Mention File in Terminal…", icon: "at", shortcut: "⌘⇧M", category: "Terminal") {
                hasProject
            } action: { [weak quickOpenModel, weak filePreview] in
                if let url = workingDirectory.directoryURL {
                    quickOpenModel?.index(rootURL: url, recentURLs: filePreview?.recentlyViewedURLs ?? [])
                }
                showQuickOpen = false
                showMentionPicker = true
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
            PaletteCommand(id: "show-history", title: "Show Commit History", icon: "clock.arrow.circlepath", shortcut: "⌘5", category: "View") {
                hasProject
            } action: {
                showSidebar = true
                sidebarTab = .history
            },
            PaletteCommand(id: "toggle-auto-follow", title: autoFollow ? "Disable Auto-Follow" : "Enable Auto-Follow", icon: autoFollow ? "eye.slash" : "eye", shortcut: nil, category: "View") {
                true
            } action: {
                autoFollow.toggle()
            },
            PaletteCommand(id: "toggle-changed-only", title: fileTreeModel.showChangedOnly ? "Show All Files" : "Show Changed Files Only", icon: "line.3.horizontal.decrease", shortcut: nil, category: "View") {
                hasProject
            } action: { [weak fileTreeModel] in
                fileTreeModel?.showChangedOnly.toggle()
                showSidebar = true
                sidebarTab = .files
            },
            PaletteCommand(id: "toggle-blame", title: filePreview.showBlame ? "Hide Blame Annotations" : "Show Blame Annotations", icon: "person.text.rectangle", shortcut: nil, category: "View") {
                filePreview.selectedURL != nil && filePreview.activeTab == .source
            } action: { [weak filePreview] in
                filePreview?.showBlame.toggle()
                if filePreview?.showBlame == true {
                    filePreview?.loadBlame()
                } else {
                    filePreview?.clearBlame()
                }
            },
            PaletteCommand(id: "reveal-in-tree", title: "Reveal in File Tree", icon: "arrow.right.circle", shortcut: "⌘⇧J", category: "Navigation") {
                filePreview.selectedURL != nil
            } action: { [weak filePreview] in
                if let url = filePreview?.selectedURL {
                    revealInFileTree(url)
                }
            },

            // Terminal
            PaletteCommand(id: "new-terminal-tab", title: "New Shell Tab", icon: "terminal", shortcut: "⌘T", category: "Terminal") {
                hasProject
            } action: { [weak terminalTabs] in
                terminalTabs?.addTab()
            },
            PaletteCommand(id: "new-copilot-tab", title: "New Copilot Tab", icon: "sparkle", shortcut: "⌘⇧T", category: "Terminal") {
                hasProject
            } action: { [weak terminalTabs] in
                terminalTabs?.addCopilotTab()
            },
            PaletteCommand(id: "split-terminal-right", title: "Split Terminal Right", icon: "rectangle.split.2x1", shortcut: "⌘D", category: "Terminal") {
                hasProject && !terminalTabs.isSplit
            } action: { [weak terminalTabs] in
                terminalTabs?.splitPane(direction: .horizontal)
            },
            PaletteCommand(id: "split-terminal-down", title: "Split Terminal Down", icon: "rectangle.split.1x2", shortcut: "⌘⇧D", category: "Terminal") {
                hasProject && !terminalTabs.isSplit
            } action: { [weak terminalTabs] in
                terminalTabs?.splitPane(direction: .vertical)
            },
            PaletteCommand(id: "close-split-terminal", title: "Close Split Terminal", icon: "rectangle", shortcut: nil, category: "Terminal") {
                terminalTabs.isSplit
            } action: { [weak terminalTabs] in
                terminalTabs?.closeSplit()
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
            PaletteCommand(id: "switch-project", title: "Switch Project…", icon: "arrow.triangle.swap", shortcut: nil, category: "File") {
                true
            } action: {
                showProjectSwitcher = true
            },
            PaletteCommand(id: "clone-repo", title: "Clone Repository…", icon: "arrow.down.circle", shortcut: nil, category: "File") {
                true
            } action: {
                showCloneSheet = true
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

            PaletteCommand(id: "branch-diff", title: "Branch Diff (PR Preview)", icon: "arrow.triangle.pull", shortcut: nil, category: "Actions") {
                hasProject && workingDirectory.gitBranch != nil
            } action: { [weak branchDiffModel, weak workingDirectory] in
                if let url = workingDirectory?.directoryURL {
                    branchDiffModel?.load(rootURL: url)
                }
                showDiffSummary = false
                showBranchDiff = true
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

            PaletteCommand(id: "next-review-file", title: "Next File in Review", icon: "chevron.right.2", shortcut: "]", category: "Review") {
                hasProject && !changesModel.changedFiles.isEmpty
            } action: { [weak changesModel] in
                changesModel?.focusNextFile()
            },

            PaletteCommand(id: "prev-review-file", title: "Previous File in Review", icon: "chevron.left.2", shortcut: "[", category: "Review") {
                hasProject && !changesModel.changedFiles.isEmpty
            } action: { [weak changesModel] in
                changesModel?.focusPreviousFile()
            },

            PaletteCommand(id: "next-hunk", title: "Next Hunk", icon: "arrow.down.to.line", shortcut: "j", category: "Review") {
                hasProject && changesModel.focusedFile != nil
            } action: { [weak changesModel] in
                changesModel?.focusNextHunk()
            },

            PaletteCommand(id: "prev-hunk", title: "Previous Hunk", icon: "arrow.up.to.line", shortcut: "k", category: "Review") {
                hasProject && changesModel.focusedFile != nil
            } action: { [weak changesModel] in
                changesModel?.focusPreviousHunk()
            },

            PaletteCommand(id: "stage-focused-hunk", title: "Stage Focused Hunk", icon: "plus.circle", shortcut: "s", category: "Review") {
                changesModel.focusedHunk != nil
            } action: { [weak changesModel] in
                changesModel?.stageFocusedHunk()
            },

            PaletteCommand(id: "discard-focused-hunk", title: "Discard Focused Hunk", icon: "arrow.uturn.backward.circle", shortcut: "⌦", category: "Review") {
                changesModel.focusedHunk != nil
            } action: { [weak changesModel] in
                changesModel?.discardFocusedHunk()
            },

            PaletteCommand(id: "toggle-file-reviewed", title: "Toggle File Reviewed", icon: "eye", shortcut: "r", category: "Review") {
                changesModel.focusedFile != nil
            } action: { [weak changesModel] in
                changesModel?.toggleFocusedFileReviewed()
            },

            PaletteCommand(id: "open-focused-file", title: "Open File in Preview", icon: "arrow.up.right.square", shortcut: "↵", category: "Review") {
                changesModel.focusedFile != nil
            } action: { [weak changesModel, weak filePreview] in
                if let url = changesModel?.focusedFile?.url {
                    filePreview?.select(url)
                }
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

            PaletteCommand(id: "create-pr", title: "Create Pull Request…", icon: "arrow.triangle.pull", shortcut: nil, category: "Git") {
                hasProject && workingDirectory.hasUpstream && workingDirectory.openPRURL == nil
            } action: {
                showSidebar = true
                sidebarTab = .changes
                showCreatePR = true
            },

            PaletteCommand(id: "view-pr", title: "View Pull Request", icon: "arrow.triangle.pull", shortcut: nil, category: "Git") {
                hasProject && workingDirectory.openPRURL != nil
            } action: { [weak workingDirectory] in
                if let urlString = workingDirectory?.openPRURL, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            },

            PaletteCommand(id: "keyboard-shortcuts", title: "Keyboard Shortcuts", icon: "keyboard", shortcut: "⌘/", category: "Help") {
                true
            } action: {
                showKeyboardShortcuts = true
            },

            PaletteCommand(id: "go-to-symbol", title: "Go to Symbol…", icon: "list.bullet.indent", shortcut: nil, category: "Navigation") {
                filePreview.selectedURL != nil && filePreview.fileContent != nil && filePreview.activeTab == .source
            } action: { [weak filePreview] in
                filePreview?.showSymbolOutline = true
            },

            PaletteCommand(id: "go-to-line", title: "Go to Line…", icon: "arrow.right.to.line", shortcut: "⌘L", category: "Navigation") {
                filePreview.selectedURL != nil && filePreview.fileContent != nil && filePreview.activeTab == .source
            } action: { [weak filePreview] in
                filePreview?.showGoToLine = true
            },

            PaletteCommand(id: "instructions", title: "Project Instructions…", icon: "doc.text", shortcut: nil, category: "Actions") {
                hasProject
            } action: {
                showInstructions = true
            },

            // Copilot CLI
            PaletteCommand(id: "copilot-actions", title: "Copilot Actions…", icon: "terminal", shortcut: nil, category: "Copilot") {
                hasProject
            } action: {
                showCopilotActions = true
            },
            PaletteCommand(id: "copilot-compact", title: "Copilot: Compact History", icon: "arrow.triangle.2.circlepath", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/compact\n")
            },
            PaletteCommand(id: "copilot-diff", title: "Copilot: Show Diff", icon: "doc.text", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/diff\n")
            },
            PaletteCommand(id: "copilot-model", title: "Copilot: Switch Model", icon: "brain", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/model\n")
            },
            PaletteCommand(id: "copilot-help", title: "Copilot: Help", icon: "questionmark.circle", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/help\n")
            },
            PaletteCommand(id: "copilot-cycle-mode", title: "Copilot: Cycle Mode", icon: "arrow.left.arrow.right", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.sendEscape("[Z")
            },
            PaletteCommand(id: "copilot-restart", title: "Copilot: Restart Session", icon: "arrow.counterclockwise", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.sendControl(0x04)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    terminalProxy?.send("copilot\n")
                }
            },
            PaletteCommand(id: "copilot-clear", title: "Copilot: Clear Screen", icon: "clear", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.sendControl(0x0C)
            },
        ])
    }

    private func closeCurrentProject() {
        showTaskBanner = false
        filePreview.close(persist: false)
        showDiffSummary = false
        showBranchDiff = false
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
    @ObservedObject var filePreview: FilePreviewModel
    @ObservedObject var recentProjects: RecentProjectsModel
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @Binding var showSidebar: Bool
    @Binding var autoFollow: Bool
    @Binding var showBranchPicker: Bool
    @Binding var showInstructions: Bool
    @Binding var showCopilotActions: Bool
    @Binding var showProjectSwitcher: Bool
    var onOpenDirectory: () -> Void
    var onSwitchProject: (URL) -> Void
    var onCloneRepository: () -> Void

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

                GitSyncControls(workingDirectory: workingDirectory)
            }

            Spacer()

            AgentActivityIndicator(
                activityModel: activityModel,
                onFocusTerminal: { terminalProxy.focusTerminal() }
            )

            Button {
                showCopilotActions.toggle()
            } label: {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Copilot Actions")
            .popover(isPresented: $showCopilotActions, arrowEdge: .bottom) {
                CopilotActionsView(onDismiss: { showCopilotActions = false })
            }

            Button {
                autoFollow.toggle()
            } label: {
                Image(systemName: autoFollow ? "eye" : "eye.slash")
                    .foregroundStyle(autoFollow ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .help(autoFollow ? "Auto-Follow Changes: On" : "Auto-Follow Changes: Off")

            Button {
                showInstructions.toggle()
            } label: {
                Image(systemName: "doc.text")
                    .foregroundStyle(hasInstructionFiles ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Project Instructions")
            .popover(isPresented: $showInstructions, arrowEdge: .bottom) {
                if let rootURL = workingDirectory.directoryURL {
                    InstructionsView(
                        rootURL: rootURL,
                        filePreview: filePreview,
                        onDismiss: { showInstructions = false }
                    )
                }
            }

            Button {
                showProjectSwitcher.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 10))
                    Text("Switch")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Switch Project")
            .popover(isPresented: $showProjectSwitcher, arrowEdge: .bottom) {
                ProjectSwitcherView(
                    recentProjects: recentProjects,
                    currentPath: workingDirectory.directoryURL?.standardizedFileURL.path,
                    onSelect: { url in onSwitchProject(url) },
                    onBrowse: { onOpenDirectory() },
                    onClone: onCloneRepository,
                    onDismiss: { showProjectSwitcher = false }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Quick check for whether any instruction files exist in the project.
    private var hasInstructionFiles: Bool {
        guard let rootURL = workingDirectory.directoryURL else { return false }
        let fm = FileManager.default
        if InstructionFileSpec.knownFiles.contains(where: { spec in
            fm.fileExists(atPath: rootURL.appendingPathComponent(spec.relativePath).path)
        }) {
            return true
        }
        // Also check for custom .instructions.md files
        let customDir = rootURL.appendingPathComponent(".github/instructions")
        return fm.fileExists(atPath: customDir.path)
    }
}

/// Compact git sync indicators and push/pull buttons shown next to the branch name.
struct GitSyncControls: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @State private var showSyncError = false

    var body: some View {
        HStack(spacing: 6) {
            // Ahead/behind badges
            if workingDirectory.hasUpstream && (workingDirectory.aheadCount > 0 || workingDirectory.behindCount > 0) {
                HStack(spacing: 3) {
                    if workingDirectory.aheadCount > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8, weight: .bold))
                            Text("\(workingDirectory.aheadCount)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(.orange)
                        .help("\(workingDirectory.aheadCount) commit\(workingDirectory.aheadCount == 1 ? "" : "s") ahead of remote")
                    }
                    if workingDirectory.behindCount > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                            Text("\(workingDirectory.behindCount)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(.cyan)
                        .help("\(workingDirectory.behindCount) commit\(workingDirectory.behindCount == 1 ? "" : "s") behind remote")
                    }
                }
            }

            if workingDirectory.hasRemotes {
                Divider()
                    .frame(height: 14)

                // Sync button group
                HStack(spacing: 2) {
                    if workingDirectory.isSyncing {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 16, height: 16)
                    } else {
                        Button {
                            workingDirectory.push()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 22, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(workingDirectory.aheadCount == 0 && workingDirectory.hasUpstream)
                        .help(workingDirectory.hasUpstream ? "Push \(workingDirectory.aheadCount) commit\(workingDirectory.aheadCount == 1 ? "" : "s")" : "Push and set upstream")

                        Button {
                            workingDirectory.pull()
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 22, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(!workingDirectory.hasUpstream)
                        .help(workingDirectory.hasUpstream ? "Pull" : "No upstream branch")

                        Button {
                            workingDirectory.fetch()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 22, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help("Fetch from remote")
                    }
                }

                // Sync error indicator
                if workingDirectory.lastSyncError != nil {
                    Button {
                        showSyncError.toggle()
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showSyncError, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sync Error")
                                .font(.headline)
                            Text(workingDirectory.lastSyncError ?? "")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Button("Dismiss") {
                                workingDirectory.lastSyncError = nil
                                showSyncError = false
                            }
                            .controlSize(.small)
                        }
                        .padding(12)
                        .frame(maxWidth: 320)
                    }
                }
            }
        }
    }
}

struct SidebarView: View {
    @ObservedObject var model: WorkingDirectoryModel
    @ObservedObject var filePreview: FilePreviewModel
    @ObservedObject var changesModel: ChangesModel
    @ObservedObject var activityModel: ActivityFeedModel
    @ObservedObject var searchModel: SearchModel
    @ObservedObject var fileTreeModel: FileTreeModel
    @ObservedObject var commitHistoryModel: CommitHistoryModel
    @Binding var activeTab: SidebarTab
    var onReviewAll: (() -> Void)?
    var onBranchDiff: (() -> Void)?
    var onCreatePR: (() -> Void)?

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

                SidebarTabButton(
                    title: "History",
                    systemImage: "clock.arrow.circlepath",
                    isActive: activeTab == .history
                ) {
                    activeTab = .history
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
                    FileTreeView(rootURL: rootURL, filePreview: filePreview, model: fileTreeModel)
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
                ChangesListView(model: changesModel, filePreview: filePreview, workingDirectory: model, onReviewAll: onReviewAll, onBranchDiff: onBranchDiff, onCreatePR: onCreatePR)

            case .activity:
                ActivityFeedView(model: activityModel, filePreview: filePreview)

            case .search:
                SearchView(model: searchModel, filePreview: filePreview)

            case .history:
                if let rootURL = model.directoryURL {
                    CommitHistoryView(
                        model: commitHistoryModel,
                        filePreview: filePreview,
                        rootURL: rootURL
                    )
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No directory selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
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
    var onNewCopilotTab: () -> Void
    var onFindInTerminal: () -> Void
    var onShowCommandPalette: () -> Void
    var onNextChange: (() -> Void)?
    var onPreviousChange: (() -> Void)?
    var onReviewAllChanges: (() -> Void)?
    var onShowKeyboardShortcuts: () -> Void
    var onGoToLine: (() -> Void)?
    var onRevealInTree: (() -> Void)?
    var onMentionInTerminal: (() -> Void)?
    var onCloneRepository: (() -> Void)?
    var onSplitTerminalH: (() -> Void)?
    var onSplitTerminalV: (() -> Void)?

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
                onReviewAllChanges: onReviewAllChanges,
                onShowKeyboardShortcuts: onShowKeyboardShortcuts,
                onGoToLine: onGoToLine
            ))
            .modifier(FocusedSceneModifierC(
                hasProject: hasProject,
                onNewCopilotTab: onNewCopilotTab,
                onRevealInTree: onRevealInTree,
                onMentionInTerminal: onMentionInTerminal,
                onCloneRepository: onCloneRepository,
                onSplitTerminalH: onSplitTerminalH,
                onSplitTerminalV: onSplitTerminalV
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
    var onShowKeyboardShortcuts: () -> Void
    var onGoToLine: (() -> Void)?

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
            .focusedSceneValue(\.showKeyboardShortcuts, onShowKeyboardShortcuts)
            .focusedSceneValue(\.goToLine, onGoToLine)
    }
}

private struct FocusedSceneModifierC: ViewModifier {
    var hasProject: Bool
    var onNewCopilotTab: () -> Void
    var onRevealInTree: (() -> Void)?
    var onMentionInTerminal: (() -> Void)?
    var onCloneRepository: (() -> Void)?
    var onSplitTerminalH: (() -> Void)?
    var onSplitTerminalV: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.newCopilotTab, hasProject ? onNewCopilotTab : nil)
            .focusedSceneValue(\.revealInTree, onRevealInTree)
            .focusedSceneValue(\.mentionInTerminal, onMentionInTerminal)
            .focusedSceneValue(\.cloneRepository, onCloneRepository)
            .focusedSceneValue(\.splitTerminalH, onSplitTerminalH)
            .focusedSceneValue(\.splitTerminalV, onSplitTerminalV)
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
    var onFocusTerminal: (() -> Void)? = nil
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
                    if activityModel.isAgentActive {
                        HStack(spacing: 4) {
                            if let change = activityModel.latestFileChange {
                                Text(change.url.lastPathComponent)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                            }
                            Text(formattedElapsed)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text(summaryText)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            if activityModel.isTaskStalled {
                                stallBadge
                            }
                        }
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

    @ViewBuilder
    private var stallBadge: some View {
        Button {
            onFocusTerminal?()
        } label: {
            Text("possibly stalled")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help("No file activity for 60 seconds — tap to check the terminal")
    }

    private var formattedElapsed: String {
        let s = activityModel.taskElapsedSeconds
        return String(format: "%02d:%02d", s / 60, s % 60)
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
