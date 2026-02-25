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
    @State private var isDroppingFolder = false
    @AppStorage("autoFollowChanges") private var autoFollow = true
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 14

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
            }
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
                        activeTab: $sidebarTab
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
                        showSidebar: $showSidebar,
                        autoFollow: $autoFollow,
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
                    }
                    .id(workingDirectory.directoryURL)

                    StatusBarView(
                        workingDirectory: workingDirectory,
                        filePreview: filePreview,
                        changesModel: changesModel
                    )
                }

                if filePreview.selectedURL != nil {
                    PanelDivider(
                        width: $previewWidth,
                        minWidth: 200,
                        maxWidth: 800,
                        edge: .trailing
                    )

                    FilePreviewView(model: filePreview)
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
        ])
    }

    private func closeCurrentProject() {
        filePreview.close()
        changesModel.stop()
        activityModel.stop()
        searchModel.clear()
        terminalTabs.reset()
        workingDirectory.closeProject()
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
}

struct ToolbarView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @Binding var showSidebar: Bool
    @Binding var autoFollow: Bool
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

                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(branch)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

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
                ChangesListView(model: changesModel, filePreview: filePreview)

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
                onShowCommandPalette: onShowCommandPalette
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

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.closeProject, hasProject ? onCloseProject : nil)
            .focusedSceneValue(\.increaseFontSize, onIncreaseFontSize)
            .focusedSceneValue(\.decreaseFontSize, onDecreaseFontSize)
            .focusedSceneValue(\.resetFontSize, onResetFontSize)
            .focusedSceneValue(\.newTerminalTab, hasProject ? onNewTerminalTab : nil)
            .focusedSceneValue(\.findInTerminal, hasProject ? onFindInTerminal : nil)
            .focusedSceneValue(\.showCommandPalette, onShowCommandPalette)
    }
}
