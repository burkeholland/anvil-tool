import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var workingDirectory = WorkingDirectoryModel()
    @StateObject private var recentProjects = RecentProjectsModel()
    @StateObject private var terminalProxy = TerminalInputProxy()
    @StateObject private var quickOpenModel = QuickOpenModel()
    @StateObject private var terminalTabs = TerminalTabsModel()
    @StateObject private var commandPalette = CommandPaletteModel()
    @StateObject private var promptHistoryStore = PromptHistoryStore()
    @StateObject private var promptMarkerStore = PromptMarkerStore()
    @StateObject private var sessionTranscriptStore = SessionTranscriptStore()
    @StateObject private var sessionHealthMonitor = SessionHealthMonitor()
    @StateObject private var sessionListModel = SessionListModel()
    @StateObject private var buildVerifier = BuildVerifier()
    @StateObject private var testRunner = TestRunner()
    @State private var notificationManager = AgentNotificationManager()
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("autoFollowChanges") private var autoFollow = true
    @AppStorage("autoBuildOnTaskComplete") private var autoBuildOnTaskComplete = true
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 14
    @AppStorage("agentSoundEnabled") private var agentSoundEnabled = true
    @AppStorage("agentSoundName") private var agentSoundName = "Glass"
    @State private var showQuickOpen = false
    @State private var showMentionPicker = false
    @State private var showCommandPalette = false
    @State private var showBranchPicker = false
    @State private var isDroppingFolder = false
    @State private var isDroppingFileToTerminal = false
    @State private var showTaskBanner = false
    @State private var agentCompletionSound: NSSound?
    @State private var showKeyboardShortcuts = false
    @State private var showInstructions = false
    @State private var showCopilotActions = false
    @State private var showProjectSwitcher = false
    @State private var showCloneSheet = false
    @State private var showPromptHistory = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var overlayStack: some View {
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
        .background {
            // ⌘K opens the command palette without a menu item (supplements ⌘⇧P)
            Button("") {
                buildCommandPalette()
                showCommandPalette = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    // Split into five levels (≤6 modifiers each) to stay within Swift's type-checker limit.
    private var bodyBase: some View {
        bodyBaseB
        .focusedSceneValue(\.exportSession, workingDirectory.directoryURL != nil ? exportSessionAsMarkdown : nil)
        .focusedSceneObject(recentProjects)
        .focusedSceneValue(\.openRecentProject, { url in openDirectory(url) })
    }

    private var bodyBaseB: some View {
        bodyBaseC
        .focusedSceneValue(\.showCommandPalette, { buildCommandPalette(); showCommandPalette = true })
        .focusedSceneValue(\.showKeyboardShortcuts, { showKeyboardShortcuts = true })
        .focusedSceneValue(\.cloneRepository, { showCloneSheet = true })
        .focusedSceneValue(\.splitTerminalH, workingDirectory.directoryURL != nil ? { terminalTabs.splitPane(direction: .horizontal) } : nil)
        .focusedSceneValue(\.splitTerminalV, workingDirectory.directoryURL != nil ? { terminalTabs.splitPane(direction: .vertical) } : nil)
        .focusedSceneValue(\.showPromptHistory, workingDirectory.directoryURL != nil ? { showPromptHistory = true } : nil)
    }

    private var bodyBaseC: some View {
        bodyBaseD
        .focusedSceneValue(\.resetFontSize, { terminalFontSize = EmbeddedTerminalView.defaultFontSize })
        .focusedSceneValue(\.newTerminalTab, workingDirectory.directoryURL != nil ? { terminalTabs.addTab() } : nil)
        .focusedSceneValue(\.newCopilotTab, workingDirectory.directoryURL != nil ? { terminalTabs.addCopilotTab() } : nil)
        .focusedSceneValue(\.findInTerminal, workingDirectory.directoryURL != nil ? { terminalProxy.showFindBar() } : nil)
        .focusedSceneValue(\.findTerminalNext, workingDirectory.directoryURL != nil ? { terminalProxy.findTerminalNext() } : nil)
        .focusedSceneValue(\.findTerminalPrevious, workingDirectory.directoryURL != nil ? { terminalProxy.findTerminalPrevious() } : nil)
    }

    private var bodyBaseD: some View {
        bodyBaseE
        .focusedSceneValue(\.quickOpen, workingDirectory.directoryURL != nil ? { showMentionPicker = false; showQuickOpen = true } : nil)
        .focusedSceneValue(\.autoFollow, $autoFollow)
        .focusedSceneValue(\.findInProject, workingDirectory.directoryURL != nil ? { quickOpenModel.reset(); showQuickOpen = true } : nil)
        .focusedSceneValue(\.closeProject, workingDirectory.directoryURL != nil ? closeCurrentProject : nil)
        .focusedSceneValue(\.increaseFontSize, { terminalFontSize = min(terminalFontSize + 1, EmbeddedTerminalView.maxFontSize) })
        .focusedSceneValue(\.decreaseFontSize, { terminalFontSize = max(terminalFontSize - 1, EmbeddedTerminalView.minFontSize) })
    }

    private var bodyBaseE: some View {
        overlayStack
        .environmentObject(terminalProxy)
        .toolbar { projectToolbar }
        .focusedSceneValue(\.sidebarVisible, $showSidebar)
        .focusedSceneValue(\.openDirectory, browseForDirectory)
        .focusedSceneValue(\.refresh, nil)
    }

    @ToolbarContentBuilder
    private var projectToolbar: some ToolbarContent {
        if workingDirectory.directoryURL != nil {
            ToolbarView(
                workingDirectory: workingDirectory,
                recentProjects: recentProjects,
                promptHistoryStore: promptHistoryStore,
                sessionHealthMonitor: sessionHealthMonitor,
                showSidebar: $showSidebar,
                autoFollow: $autoFollow,
                showBranchPicker: $showBranchPicker,
                showInstructions: $showInstructions,
                showCopilotActions: $showCopilotActions,
                showPromptHistory: $showPromptHistory,
                showProjectSwitcher: $showProjectSwitcher,
                isAgentWaitingForInput: terminalTabs.isAnyTabWaitingForInput,
                agentMode: terminalTabs.agentMode,
                agentModel: terminalTabs.agentModel,
                onOpenDirectory: { browseForDirectory() },
                onSwitchProject: { url in openDirectory(url) },
                onCloneRepository: { showCloneSheet = true },
                onCompact: {
                    terminalProxy.send("/compact\n")
                    sessionHealthMonitor.reset()
                },
                onFocusTerminal: {
                    if let tv = terminalProxy.terminalView {
                        tv.window?.makeFirstResponder(tv)
                    }
                }
            )
        }
    }

    var body: some View {
        bodyBase
        .onChange(of: terminalTabs.isAnyTabWaitingForInput) { _, isWaiting in
            if isWaiting { NSSound.beep() }
        }
        .onChange(of: workingDirectory.directoryURL) { _, newURL in
            showTaskBanner = false
            buildVerifier.cancel()
            testRunner.cancel()
            terminalTabs.reset()
            sessionHealthMonitor.reset()
            promptMarkerStore.clear()
            promptHistoryStore.configure(projectPath: newURL?.standardizedFileURL.path)
            sessionTranscriptStore.configure(projectPath: newURL?.standardizedFileURL.path)
            sessionListModel.projectCWD = newURL?.standardizedFileURL.path
            if let url = newURL {
                recentProjects.recordOpen(url)
            }
        }
        .onChange(of: buildVerifier.status) { _, newStatus in
            if case .passed = newStatus, let url = workingDirectory.directoryURL {
                testRunner.run(at: url)
            }
            if case .failed = newStatus, showTaskBanner {
                notificationManager.notifyTaskComplete(
                    changedFileCount: 0,
                    buildStatus: newStatus,
                    testStatus: testRunner.status
                )
            }
        }
        .onChange(of: testRunner.status) { _, newStatus in
            switch newStatus {
            case .passed, .failed:
                if showTaskBanner {
                    notificationManager.notifyTaskComplete(
                        changedFileCount: 0,
                        buildStatus: buildVerifier.status,
                        testStatus: newStatus
                    )
                }
            default:
                break
            }
        }
        .onChange(of: terminalProxy.promptSentCount) { _, _ in
            if showTaskBanner {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showTaskBanner = false
                }
            }
        }
        .onAppear {
            terminalProxy.historyStore = promptHistoryStore
            terminalProxy.sessionMonitor = sessionHealthMonitor
            terminalProxy.markerStore = promptMarkerStore
            promptHistoryStore.configure(projectPath: workingDirectory.directoryURL?.standardizedFileURL.path)
            sessionTranscriptStore.configure(projectPath: workingDirectory.directoryURL?.standardizedFileURL.path)
            sessionListModel.projectCWD = workingDirectory.directoryURL?.standardizedFileURL.path
            sessionListModel.start()
            if let url = workingDirectory.directoryURL {
                recentProjects.recordOpen(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openDirectoryNotification)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                openDirectory(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.focusTerminalTabNotification)) { notification in
            if let tabID = notification.userInfo?["tabID"] as? UUID {
                terminalTabs.selectTab(tabID)
            }
        }
        .sheet(isPresented: $showCloneSheet) {
            CloneRepositoryView(
                onCloned: { url in openDirectory(url) },
                onDismiss: { showCloneSheet = false }
            )
        }
        .sheet(isPresented: $showInstructions) {
            if let rootURL = workingDirectory.directoryURL {
                InstructionsView(
                    rootURL: rootURL,
                    onDismiss: { showInstructions = false }
                )
            }
        }
        .sheet(isPresented: $showPromptHistory) {
            PromptHistoryView(
                store: promptHistoryStore,
                onDismiss: { showPromptHistory = false }
            )
            .environmentObject(terminalProxy)
        }
        .sheet(isPresented: $showProjectSwitcher) {
            ProjectSwitcherView(
                recentProjects: recentProjects,
                currentPath: workingDirectory.directoryURL?.standardizedFileURL.path,
                onSelect: { url in
                    showProjectSwitcher = false
                    openDirectory(url)
                },
                onBrowse: {
                    showProjectSwitcher = false
                    browseForDirectory()
                },
                onClone: {
                    showProjectSwitcher = false
                    showCloneSheet = true
                },
                onDismiss: { showProjectSwitcher = false }
            )
        }
    }

    /// Updates the "waiting for input" state for a tab and fires a macOS notification
    /// when the agent transitions into the waiting state while Anvil is in the background.
    private func handleAgentWaitingForInput(_ waiting: Bool, for tab: TerminalTab) {
        terminalTabs.setWaitingForInput(waiting, tabID: tab.id)
        if waiting {
            notificationManager.notifyWaitingForInput(tabID: tab.id, tabTitle: tab.title)
        }
    }

    /// Returns an EmbeddedTerminalView configured for the given tab.
    private func makeTabTerminalView(for tab: TerminalTab) -> some View {
        EmbeddedTerminalView(
            workingDirectory: workingDirectory,
            launchCopilotOverride: tab.launchCopilot,
            isActiveTab: tab.id == terminalTabs.activeTabID,
            onTitleChange: { title in
                terminalTabs.updateTitle(for: tab.id, to: title)
            },
            onOpenFile: { _, _ in },
            onOutputFilePath: { _ in },
            onAgentWaitingForInput: { waiting in
                handleAgentWaitingForInput(waiting, for: tab)
            },
            onAgentModeChanged: { mode in
                if tab.id == terminalTabs.activeTabID {
                    terminalTabs.agentMode = mode
                }
            },
            onAgentModelChanged: { model in
                if tab.id == terminalTabs.activeTabID {
                    terminalTabs.agentModel = model
                }
            },
            markerStore: promptMarkerStore
        )
        .opacity(tab.id == terminalTabs.activeTabID ? 1 : 0)
        .allowsHitTesting(tab.id == terminalTabs.activeTabID)
    }

    private var terminalAreaView: some View {
        VStack(spacing: 0) {
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
                            makeTabTerminalView(for: tab)
                        }
                    }

                    let splitPane = VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: splitTab.launchCopilot ? "sparkle" : "terminal")
                                .font(.system(size: 10))
                                .foregroundStyle(splitTab.launchCopilot ? .purple : .secondary)
                            Text(splitTab.title)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                            if terminalTabs.waitingForInputTabIDs.contains(splitTab.id) {
                                SplitPaneInputBadge()
                            }
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
                        .background(Color(nsColor: NSColor(red: 0.09, green: 0.08, blue: 0.08, alpha: 1.0)))
                        .overlay(alignment: .bottom) { Divider().opacity(0.3) }

                        EmbeddedTerminalView(
                            workingDirectory: workingDirectory,
                            launchCopilotOverride: splitTab.launchCopilot,
                            isActiveTab: false,
                            onTitleChange: { title in
                                terminalTabs.updateSplitTitle(to: title)
                            },
                            onOpenFile: { _, _ in },
                            onOutputFilePath: { _ in },
                            onAgentWaitingForInput: { waiting in
                                handleAgentWaitingForInput(waiting, for: splitTab)
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
                            makeTabTerminalView(for: tab)
                        }

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
                    changedFileCount: 0,
                    totalAdditions: 0,
                    totalDeletions: 0,
                    buildStatus: buildVerifier.status,
                    buildDiagnostics: buildVerifier.diagnostics,
                    onOpenDiagnostic: { _ in },
                    onFixDiagnostic: { diagnostic in
                        let location = "\(diagnostic.filePath):\(diagnostic.line)"
                        let prompt = "Fix this build error: \(diagnostic.message)\n\nFile: \(location)"
                        terminalProxy.sendPrompt(prompt)
                        showTaskBanner = false
                    },
                    testStatus: testRunner.status,
                    onRunTests: workingDirectory.directoryURL != nil ? {
                        if let url = workingDirectory.directoryURL {
                            testRunner.run(at: url)
                        }
                    } : nil,
                    onFixTestFailure: { output in
                        let prompt = "The test suite failed. Please fix the failing tests.\n\nTest output:\n\(output)"
                        terminalProxy.sendPrompt(prompt)
                        showTaskBanner = false
                    },
                    onFixTestCase: { testName in
                        let prompt = "Fix this failing test: \(testName)"
                        terminalProxy.sendPrompt(prompt)
                        showTaskBanner = false
                    },
                    gitBranch: workingDirectory.gitBranch,
                    aheadCount: workingDirectory.aheadCount,
                    hasOpenPR: workingDirectory.openPRURL != nil,
                    onReviewAll: { showTaskBanner = false },
                    onStageAllAndCommit: { showTaskBanner = false },
                    onNewTask: {
                        if let tv = terminalProxy.terminalView {
                            tv.window?.makeFirstResponder(tv)
                        }
                        showTaskBanner = false
                    },
                    onDismiss: { showTaskBanner = false },
                    onExportSession: workingDirectory.directoryURL != nil ? exportSessionAsMarkdown : nil,
                    taskPrompt: promptHistoryStore.entries.first?.text,
                    isSaturated: sessionHealthMonitor.isSaturated,
                    onSelectSuggestion: { prompt in
                        terminalProxy.sendPrompt(prompt)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            StatusBarView(workingDirectory: workingDirectory)
        }
    }

    private var projectView: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SessionListView(model: sessionListModel)
                    .navigationSplitViewColumnWidth(min: 140, ideal: 240, max: 500)
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                terminalAreaView
            }

            // Quick Open overlay
            if showQuickOpen {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { dismissQuickOpen() }

                VStack {
                    QuickOpenView(
                        model: quickOpenModel,
                        onDismiss: { dismissQuickOpen() },
                        onSwitchToCommands: { query in
                            buildCommandPalette()
                            commandPalette.query = query
                            showCommandPalette = true
                        }
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
                quickOpenModel.index(rootURL: url, recentURLs: [])
            }
        }
        .onChange(of: showMentionPicker) { _, isShowing in
            if isShowing, let url = workingDirectory.directoryURL {
                quickOpenModel.index(rootURL: url, recentURLs: [])
            }
        }
        .onChange(of: showSidebar) { _, show in
            withAnimation { columnVisibility = show ? .all : .detailOnly }
        }
        .onChange(of: columnVisibility) { _, vis in
            showSidebar = vis != .detailOnly
        }
    }

    private func openDirectory(_ url: URL) {
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

    private func buildCommandPalette() {
        let hasProject = workingDirectory.directoryURL != nil
        commandPalette.register([
            // Navigation
            PaletteCommand(id: "quick-open", title: "Quick Open File…", icon: "doc.text.magnifyingglass", shortcut: "⌘⇧O", category: "Navigation") {
                hasProject
            } action: { [weak quickOpenModel] in
                if let url = workingDirectory.directoryURL {
                    quickOpenModel?.index(rootURL: url, recentURLs: [])
                }
                showMentionPicker = false
                showQuickOpen = true
            },
            PaletteCommand(id: "mention-file", title: "Mention File in Terminal…", icon: "at", shortcut: "⌘⇧M", category: "Terminal") {
                hasProject
            } action: { [weak quickOpenModel] in
                if let url = workingDirectory.directoryURL {
                    quickOpenModel?.index(rootURL: url, recentURLs: [])
                }
                showQuickOpen = false
                showMentionPicker = true
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
            PaletteCommand(id: "toggle-auto-follow", title: autoFollow ? "Disable Follow Agent" : "Enable Follow Agent", icon: autoFollow ? "eye.slash" : "eye", shortcut: "⌘⇧A", category: "View") {
                true
            } action: {
                autoFollow.toggle()
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
            PaletteCommand(id: "close-project", title: "Close Project", icon: "xmark.circle", shortcut: "⌘⇧W", category: "File") {
                hasProject
            } action: {
                closeCurrentProject()
            },

            // Git
            PaletteCommand(id: "switch-branch", title: "Switch Branch…", icon: "arrow.triangle.branch", shortcut: nil, category: "Git") {
                hasProject && workingDirectory.gitBranch != nil
            } action: {
                showBranchPicker = true
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

            PaletteCommand(id: "keyboard-shortcuts", title: "Keyboard Shortcuts", icon: "keyboard", shortcut: "⌘/", category: "Help") {
                true
            } action: {
                showKeyboardShortcuts = true
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
            PaletteCommand(id: "prompt-history", title: "Prompt History…", icon: "clock.arrow.circlepath", shortcut: "⌘Y", category: "Copilot") {
                hasProject
            } action: {
                showPromptHistory = true
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
            PaletteCommand(id: "copilot-model", title: "Copilot: Switch Model", icon: "brain", shortcut: nil, category: "Copilot",
                           argumentPrompt: "Model name (leave blank to list models)") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/model\n")
            } actionWithArgument: { [weak terminalProxy] arg in
                let trimmed = arg.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    terminalProxy?.send("/model\n")
                } else {
                    terminalProxy?.send("/model \(trimmed)\n")
                }
            },
            PaletteCommand(id: "copilot-help", title: "Copilot: Help", icon: "questionmark.circle", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/help\n")
            },
            PaletteCommand(id: "copilot-context", title: "Copilot: Show Context", icon: "scope", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/context\n")
            },
            PaletteCommand(id: "copilot-review", title: "Copilot: Review Changes", icon: "eye", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/review\n")
            },
            PaletteCommand(id: "copilot-tasks", title: "Copilot: Show Tasks", icon: "checklist", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/tasks\n")
            },
            PaletteCommand(id: "copilot-session", title: "Copilot: Session Info", icon: "clock.arrow.circlepath", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/session\n")
            },
            PaletteCommand(id: "copilot-instructions", title: "Copilot: View Instructions", icon: "doc.plaintext", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/instructions\n")
            },
            PaletteCommand(id: "copilot-agent", title: "Copilot: Agent Mode", icon: "cpu", shortcut: nil, category: "Copilot",
                           argumentPrompt: "Agent name or command (optional)") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/agent\n")
            } actionWithArgument: { [weak terminalProxy] arg in
                let trimmed = arg.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    terminalProxy?.send("/agent\n")
                } else {
                    terminalProxy?.send("/agent \(trimmed)\n")
                }
            },
            PaletteCommand(id: "copilot-mcp", title: "Copilot: MCP Tools", icon: "wrench.and.screwdriver", shortcut: nil, category: "Copilot") {
                hasProject
            } action: { [weak terminalProxy] in
                terminalProxy?.send("/mcp\n")
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
        ] + buildQuickActionCommands())
    }

    /// Builds PaletteCommand entries for auto-detected and custom quick actions.
    private func buildQuickActionCommands() -> [PaletteCommand] {
        guard let rootURL = workingDirectory.directoryURL else { return [] }
        let actions = QuickActionsProvider.load(rootURL: rootURL)
        return actions.map { action in
            PaletteCommand(
                id: "quick-action-\(action.id)",
                title: action.name,
                icon: action.icon,
                shortcut: action.keybinding,
                category: "Quick Actions"
            ) {
                self.workingDirectory.directoryURL != nil
            } action: { [weak terminalProxy] in
                terminalProxy?.sendPrompt(action.command)
            }
        }
    }

    private func closeCurrentProject() {
        showTaskBanner = false
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
            let parent = url.deletingLastPathComponent()
            openDirectory(parent)
            return true
        }
    }

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
        return handleDrop(urls)
    }

    private func exportSessionAsMarkdown() {
        let transcript = terminalProxy.readTranscript()
        let markdown = SessionTranscriptStore.makeMarkdown(
            transcript: transcript,
            prompts: promptMarkerStore.markers,
            projectName: workingDirectory.projectName
        )
        guard let path = workingDirectory.directoryURL?.standardizedFileURL.path else { return }
        if let url = sessionTranscriptStore.save(markdown: markdown, projectPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

struct ToolbarView: ToolbarContent {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @ObservedObject var recentProjects: RecentProjectsModel
    @ObservedObject var promptHistoryStore: PromptHistoryStore
    @ObservedObject var sessionHealthMonitor: SessionHealthMonitor
    @Binding var showSidebar: Bool
    @Binding var autoFollow: Bool
    @Binding var showBranchPicker: Bool
    @Binding var showInstructions: Bool
    @Binding var showCopilotActions: Bool
    @Binding var showPromptHistory: Bool
    @Binding var showProjectSwitcher: Bool
    var isAgentWaitingForInput: Bool = false
    var agentMode: AgentMode? = nil
    var agentModel: String? = nil
    var onOpenDirectory: () -> Void
    var onSwitchProject: (URL) -> Void
    var onCloneRepository: () -> Void
    var onCompact: () -> Void
    var onFocusTerminal: (() -> Void)?

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showSidebar.toggle()
                }
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .help("Toggle Sidebar (⌘B)")
        }

        ToolbarItem(placement: .navigation) {
            HStack(spacing: Spacing.xs) {
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
                        HStack(spacing: Spacing.xs) {
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
                                onBranchChanged: {},
                                workingDirectory: workingDirectory
                            )
                        }
                    }

                    GitSyncControls(workingDirectory: workingDirectory)
                }
            }
        }

        ToolbarItem(placement: .principal) {
            UnifiedAgentStatusPill(
                sessionHealthMonitor: sessionHealthMonitor,
                isAgentWaitingForInput: isAgentWaitingForInput,
                agentMode: agentMode,
                agentModel: agentModel,
                onFocusTerminal: onFocusTerminal ?? {},
                onCompact: onCompact
            )
        }

        ToolbarItem(placement: .primaryAction) {
            ToolbarOverflowMenu(
                autoFollow: $autoFollow,
                showCopilotActions: $showCopilotActions,
                showPromptHistory: $showPromptHistory,
                showInstructions: $showInstructions,
                showProjectSwitcher: $showProjectSwitcher,
                workingDirectory: workingDirectory,
                recentProjects: recentProjects,
                promptHistoryStore: promptHistoryStore,
                onOpenDirectory: onOpenDirectory,
                onSwitchProject: onSwitchProject,
                onCloneRepository: onCloneRepository
            )
        }
    }
}

// MARK: - Unified Agent Status Pill

private struct UnifiedAgentStatusPill: View {
    @ObservedObject var sessionHealthMonitor: SessionHealthMonitor
    var isAgentWaitingForInput: Bool
    var agentMode: AgentMode?
    var agentModel: String?
    var onFocusTerminal: () -> Void
    var onCompact: () -> Void

    @EnvironmentObject private var terminalProxy: TerminalInputProxy
    @State private var showPopover = false
    @State private var isPulsing = false

    private var dotColor: Color {
        if isAgentWaitingForInput { return .orange }
        return Color.secondary.opacity(0.3)
    }

    private var pillBackground: Color {
        if isAgentWaitingForInput { return .orange.opacity(0.12) }
        return Color.secondary.opacity(0.07)
    }

    private var contextBarColor: Color {
        if sessionHealthMonitor.contextFillness > 0.8 { return .orange }
        if sessionHealthMonitor.contextFillness > 0.5 { return .yellow }
        return Color(nsColor: .systemGreen)
    }

    var body: some View {
        Button {
            if isAgentWaitingForInput {
                onFocusTerminal()
            } else {
                showPopover.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .scaleEffect(isPulsing ? 1.35 : 1.0)
                    .animation(
                        isAgentWaitingForInput
                            ? .easeInOut(duration: 0.65).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )
                    .onChange(of: isAgentWaitingForInput) { _, new in isPulsing = new }
                    .onAppear { isPulsing = isAgentWaitingForInput }

                if let mode = agentMode {
                    Text(mode.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Text(isAgentWaitingForInput ? "Needs input" : "Idle")
                    .font(.system(size: 10))
                    .foregroundStyle(isAgentWaitingForInput ? .orange : .secondary)
                    .lineLimit(1)

                Text(sessionHealthMonitor.elapsedString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(contextBarColor)
                            .frame(width: max(0, geo.size.width * sessionHealthMonitor.contextFillness))
                            .animation(.easeInOut(duration: 0.4), value: sessionHealthMonitor.contextFillness)
                    }
                }
                .frame(width: 28, height: 5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(pillBackground)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            UnifiedAgentPopover(
                sessionHealthMonitor: sessionHealthMonitor,
                agentMode: agentMode,
                agentModel: agentModel,
                onJumpToTerminal: {
                    showPopover = false
                    onFocusTerminal()
                },
                onCompact: onCompact
            )
        }
        .animation(.easeInOut(duration: 0.2), value: isAgentWaitingForInput)
    }
}

private struct UnifiedAgentPopover: View {
    @ObservedObject var sessionHealthMonitor: SessionHealthMonitor
    var agentMode: AgentMode?
    var agentModel: String?
    var onJumpToTerminal: () -> Void
    var onCompact: () -> Void

    @EnvironmentObject private var terminalProxy: TerminalInputProxy

    private var contextBarColor: Color {
        if sessionHealthMonitor.contextFillness > 0.8 { return .orange }
        if sessionHealthMonitor.contextFillness > 0.5 { return .yellow }
        return Color(nsColor: .systemGreen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text("Agent Idle")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let mode = agentMode {
                    Button {
                        terminalProxy.send(mode.next.activateCommand)
                    } label: {
                        Text(mode.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Mode: \(mode.displayName) — click to cycle")
                }
                if let model = agentModel {
                    Text(model)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            HStack(spacing: 8) {
                Text("Session")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(sessionHealthMonitor.elapsedString)
                    .font(.system(size: 11, design: .monospaced))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(contextBarColor)
                            .frame(width: max(0, geo.size.width * sessionHealthMonitor.contextFillness))
                            .animation(.easeInOut(duration: 0.4), value: sessionHealthMonitor.contextFillness)
                    }
                }
                .frame(width: 52, height: 5)
                Text("\(Int(sessionHealthMonitor.contextFillness * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if sessionHealthMonitor.isSaturated {
                    Button(action: onCompact) {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                            Text("Compact")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Context may be saturated — send /compact to the terminal")
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            Button(action: onJumpToTerminal) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                    Text("Jump to Terminal")
                        .font(.system(size: 12))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .frame(width: 300)
        .animation(.easeInOut(duration: 0.3), value: sessionHealthMonitor.isSaturated)
    }
}

// MARK: - Toolbar Overflow Menu

private struct ToolbarOverflowMenu: View {
    @Binding var autoFollow: Bool
    @Binding var showCopilotActions: Bool
    @Binding var showPromptHistory: Bool
    @Binding var showInstructions: Bool
    @Binding var showProjectSwitcher: Bool
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @ObservedObject var recentProjects: RecentProjectsModel
    @ObservedObject var promptHistoryStore: PromptHistoryStore
    var onOpenDirectory: () -> Void
    var onSwitchProject: (URL) -> Void
    var onCloneRepository: () -> Void

    @State private var showCopilotActionsPopover = false

    var body: some View {
        Menu {
            Toggle(isOn: $autoFollow) {
                Label(autoFollow ? "Follow Agent: On" : "Follow Agent: Off",
                      systemImage: autoFollow ? "eye" : "eye.slash")
            }
            Divider()
            Button {
                showCopilotActionsPopover = true
            } label: {
                Label("Copilot Actions", systemImage: "terminal")
            }
            Button {
                showPromptHistory = true
            } label: {
                Label("Prompt History", systemImage: "clock.arrow.circlepath")
            }
            Button {
                showInstructions = true
            } label: {
                Label("Instructions", systemImage: "doc.text")
            }
            Divider()
            Button {
                showProjectSwitcher = true
            } label: {
                Label("Switch Project", systemImage: "arrow.triangle.swap")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More Options")
        .popover(isPresented: $showCopilotActionsPopover, arrowEdge: .bottom) {
            CopilotActionsView(onDismiss: { showCopilotActionsPopover = false })
        }
        .onChange(of: showCopilotActions) { _, v in if v != showCopilotActionsPopover { showCopilotActionsPopover = v } }
        .onChange(of: showCopilotActionsPopover) { _, v in if showCopilotActions != v { showCopilotActions = v } }
    }
}

/// Compact git sync indicators and push/pull buttons shown next to the branch name.
struct GitSyncControls: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @State private var showSyncError = false

    var body: some View {
        HStack(spacing: 6) {
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

/// Small pulsing badge shown in the split-pane mini-header when that pane's
/// agent is waiting for input.
private struct SplitPaneInputBadge: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 6, height: 6)
            .scaleEffect(isPulsing ? 1.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .help("Agent is waiting for your input")
            .onAppear { isPulsing = true }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
