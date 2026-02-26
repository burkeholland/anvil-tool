import AppKit
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
    @StateObject private var filePreview2 = FilePreviewModel()
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
    @AppStorage("splitPreview") private var splitPreview = false
    @State private var showQuickOpen = false
    @State private var showSecondaryQuickOpen = false
    @State private var showMentionPicker = false
    @State private var showCommandPalette = false
    @State private var showBranchPicker = false
    @State private var showDiffSummary = false
    @State private var isDroppingFolder = false
    @AppStorage("autoFollowChanges") private var autoFollow = true
    @AppStorage("autoBuildOnTaskComplete") private var autoBuildOnTaskComplete = true
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 14
    @StateObject private var buildVerifier = BuildVerifier()
    @StateObject private var testRunner = TestRunner()
    @State private var isDroppingFileToTerminal = false
    @State private var showTaskBanner = false
    @State private var showBranchGuardBanner = false
    @State private var branchGuardTriggered = false
    @AppStorage("branchGuardBehavior") private var branchGuardBehavior = "warn"
    @AppStorage("agentSoundEnabled") private var agentSoundEnabled = true
    @AppStorage("agentSoundName") private var agentSoundName = "Glass"
    @State private var agentCompletionSound: NSSound?
    @State private var showKeyboardShortcuts = false
    @State private var showInstructions = false
    @State private var showCopilotActions = false
    @State private var showProjectSwitcher = false
    @State private var showBranchDiff = false
    @State private var showCloneSheet = false
    @State private var showCreatePR = false
    @State private var showMergeConflict = false
    @StateObject private var mergeConflictModel = MergeConflictModel()
    @StateObject private var promptHistoryStore = PromptHistoryStore()
    @StateObject private var promptMarkerStore = PromptMarkerStore()
    @StateObject private var sessionTranscriptStore = SessionTranscriptStore()
    @StateObject private var sessionHealthMonitor = SessionHealthMonitor()
    @StateObject private var diffAnnotationStore = DiffAnnotationStore()
    @StateObject private var contextStore = ContextStore()
    @State private var showPromptHistory = false
    @State private var reviewDwellTask: Task<Void, Never>? = nil
    /// Debounces auto-follow navigation to avoid thrashing the preview pane
    /// during burst file writes.
    @StateObject private var followAgent = FollowAgentController()
    /// Floating diff toast stack shown on every agent file write.
    @StateObject private var diffToastController = DiffToastController()
    @AppStorage("autoDiffToasts") private var autoDiffToasts = true

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

            // Floating diff toasts (bottom-right, only when a project is open)
            if workingDirectory.directoryURL != nil {
                DiffToastOverlay(
                    controller: diffToastController,
                    onOpenInChanges: { item in
                        if let idx = changesModel.changedFiles.firstIndex(where: { $0.url == item.fileURL }) {
                            changesModel.focusedFileIndex = idx
                        }
                        sidebarTab = .changes
                        showSidebar = true
                        showDiffSummary = true
                        diffToastController.dismiss(id: item.id)
                    }
                )
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

    private var bodyBase: some View {
        overlayStack
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
            onFindTerminalNext: {
                terminalProxy.findTerminalNext()
            },
            onFindTerminalPrevious: {
                terminalProxy.findTerminalPrevious()
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
            } : nil,
            onNextPreviewTab: filePreview.openTabs.count > 1 ? { [weak filePreview] in
                filePreview?.selectNextTab()
            } : nil,
            onPreviousPreviewTab: filePreview.openTabs.count > 1 ? { [weak filePreview] in
                filePreview?.selectPreviousTab()
            } : nil,
            onShowPromptHistory: workingDirectory.directoryURL != nil ? {
                showPromptHistory = true
            } : nil,
            onGoToTestFile: filePreview.testFileCounterpart != nil ? {
                [weak filePreview] in
                if let counterpart = filePreview?.testFileCounterpart {
                    filePreview?.select(counterpart)
                }
            } : nil,
            onToggleSplitPreview: workingDirectory.directoryURL != nil ? {
                splitPreview.toggle()
            } : nil,
            onExportSession: workingDirectory.directoryURL != nil ? {
                exportSessionAsMarkdown()
            } : nil,
            recentProjects: recentProjects,
            onOpenRecentProject: { url in openDirectory(url) },
            onAskAboutSelection: filePreview.selectedURL != nil ? { [weak filePreview, weak terminalProxy] in
                guard let model = filePreview, !model.selectionCode.isEmpty else { return }
                terminalProxy?.composeCodeQuestion(
                    intent: "Ask about this",
                    relativePath: model.relativePath,
                    language: model.highlightLanguage,
                    startLine: model.selectionStartLine,
                    endLine: model.selectionEndLine,
                    code: model.selectionCode
                )
            } : nil
        ))
    }

    var body: some View {
        bodyBase
        .onChange(of: workingDirectory.directoryURL) { _, newURL in
            showTaskBanner = false
            showBranchGuardBanner = false
            branchGuardTriggered = false
            buildVerifier.cancel()
            testRunner.cancel()
            filePreview.close(persist: false)
            filePreview.rootDirectory = newURL
            filePreview2.close(persist: false)
            filePreview2.rootDirectory = newURL
            terminalTabs.reset()
            sessionHealthMonitor.reset()
            promptMarkerStore.clear()
            fileTreeModel.clearAgentReferences()
            contextStore.clear()
            promptHistoryStore.configure(projectPath: newURL?.standardizedFileURL.path)
            sessionTranscriptStore.configure(projectPath: newURL?.standardizedFileURL.path)
            if let url = newURL {
                recentProjects.recordOpen(url)
                changesModel.start(rootURL: url)
                activityModel.start(rootURL: url)
                searchModel.setRoot(url)
                fileTreeModel.start(rootURL: url)
                commitHistoryModel.start(rootURL: url)
            }
            diffToastController.dismissAll()
        }
        .onChange(of: activityModel.latestFileChange) { _, change in
            guard autoFollow, let change = change else { return }
            followAgent.reportChange(change.url)
        }
        .onChange(of: followAgent.followEvent) { _, event in
            guard let event = event else { return }
            filePreview.autoFollowChange(to: event.url)
            revealInFileTree(event.url)
        }
        .onChange(of: activityModel.latestFileChange) { _, change in
            guard change != nil else { return }
            checkBranchGuard()
        }
        .onChange(of: activityModel.latestFileChange) { _, change in
            // Only show diff toasts during active agent sessions (after the user
            // has sent at least one prompt), so startup filesystem scans don't
            // trigger spurious toasts on project open.
            guard autoDiffToasts, let change = change,
                  let rootURL = workingDirectory.directoryURL,
                  terminalProxy.promptSentCount > 0 else { return }
            diffToastController.reportFileChange(change.url, rootURL: rootURL)
        }
        .onChange(of: filePreview.selectedURL) { _, newURL in
            // Keep tree expanded to the selected file regardless of how it was opened
            if let url = newURL {
                fileTreeModel.revealFile(url: url)
            }
            // Auto-mark as reviewed after dwell time (2 s) when viewing a changed file
            reviewDwellTask?.cancel()
            if let url = newURL,
               let file = changesModel.changedFiles.first(where: { $0.url == url }),
               !changesModel.isReviewed(file) {
                let dwellURL = url
                reviewDwellTask = Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled, filePreview.selectedURL == dwellURL else { return }
                    if let current = changesModel.changedFiles.first(where: { $0.url == dwellURL }),
                       !changesModel.isReviewed(current) {
                        changesModel.toggleReviewed(current)
                    }
                }
            }
        }
        .onChange(of: activityModel.isAgentActive) { wasActive, isActive in
            if wasActive && !isActive && activityModel.sessionStats.totalFilesTouched > 0 {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showTaskBanner = true
                }
                if agentSoundEnabled {
                    agentCompletionSound?.stop()
                    agentCompletionSound = NSSound(named: agentSoundName)
                    agentCompletionSound?.play()
                }
                if autoBuildOnTaskComplete, let url = workingDirectory.directoryURL {
                    buildVerifier.run(at: url)
                }
                // Auto-select the first unreviewed changed file to kick off review workflow.
                if autoFollow, let first = changesModel.changedFiles.first(where: { !changesModel.isReviewed($0) }) {
                    filePreview.select(first.url)
                    sidebarTab = .changes
                    showSidebar = true
                    fileTreeModel.revealFile(url: first.url)
                }
            } else if isActive {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showTaskBanner = false
                }
                buildVerifier.cancel()
                testRunner.cancel()
            }
        }
        .onChange(of: buildVerifier.status) { _, newStatus in
            // Auto-run tests once the build passes.
            if case .passed = newStatus, let url = workingDirectory.directoryURL {
                testRunner.run(at: url)
            }
            // Send task-complete notification when the build fails (tests won't follow).
            if case .failed = newStatus, showTaskBanner {
                notificationManager.notifyTaskComplete(
                    changedFileCount: changesModel.changedFiles.count,
                    buildStatus: newStatus,
                    testStatus: testRunner.status
                )
            }
        }
        .onChange(of: testRunner.status) { _, newStatus in
            // Send task-complete notification once test results are final.
            switch newStatus {
            case .passed, .failed:
                if showTaskBanner {
                    notificationManager.notifyTaskComplete(
                        changedFileCount: changesModel.changedFiles.count,
                        buildStatus: buildVerifier.status,
                        testStatus: newStatus
                    )
                }
            default:
                break
            }
        }
        .onChange(of: terminalProxy.promptSentCount) { _, _ in
            // Record the current change set as the task-start baseline for scoped review.
            changesModel.recordTaskStart()
            // Auto-dismiss the task-complete banner when the user starts a new prompt.
            if showTaskBanner {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showTaskBanner = false
                }
            }
        }
        .onAppear {
            let screenshotMode = UserDefaults.standard.bool(forKey: "anvil.screenshotMode")
            if screenshotMode {
                showSidebar = true
                let tabName = UserDefaults.standard.string(forKey: "anvil.screenshotTab") ?? "files"
                switch tabName {
                case "changes": sidebarTab = .changes
                case "activity": sidebarTab = .activity
                case "search": sidebarTab = .search
                case "history": sidebarTab = .history
                default: sidebarTab = .files
                }
                // Clear the flag so normal launches aren't affected
                UserDefaults.standard.removeObject(forKey: "anvil.screenshotMode")
                UserDefaults.standard.removeObject(forKey: "anvil.screenshotTab")
            }
            filePreview.rootDirectory = workingDirectory.directoryURL
            filePreview2.rootDirectory = workingDirectory.directoryURL
            notificationManager.connect(to: activityModel)
            terminalProxy.historyStore = promptHistoryStore
            terminalProxy.sessionMonitor = sessionHealthMonitor
            terminalProxy.markerStore = promptMarkerStore
            terminalProxy.contextStore = contextStore
            promptHistoryStore.configure(projectPath: workingDirectory.directoryURL?.standardizedFileURL.path)
            sessionTranscriptStore.configure(projectPath: workingDirectory.directoryURL?.standardizedFileURL.path)
            if let url = workingDirectory.directoryURL {
                recentProjects.recordOpen(url)
                changesModel.start(rootURL: url)
                activityModel.start(rootURL: url)
                searchModel.setRoot(url)
                fileTreeModel.start(rootURL: url)
                commitHistoryModel.start(rootURL: url)

                // In screenshot mode, auto-select a file so the preview shows content.
                // Reset any persisted tab / pin state so the screenshot is deterministic
                // regardless of what the developer had previously open.
                if screenshotMode {
                    filePreview.close(persist: false)
                    let candidates = ["README.md", "Package.swift", "ContentView.swift"]
                    for name in candidates {
                        if let entry = fileTreeModel.entries.first(where: { $0.name == name }) {
                            filePreview.select(entry.url)
                            break
                        }
                    }
                }
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
        .sheet(isPresented: $showCreatePR) {
            CreatePullRequestView(
                workingDirectory: workingDirectory,
                changesModel: changesModel,
                activityFeedModel: activityModel,
                onDismiss: { showCreatePR = false }
            )
        }
    }

    @ViewBuilder private var taskCompleteBannerView: some View {
        let sensitiveCount = changesModel.changedFiles.filter { SensitiveFileClassifier.isSensitive($0.relativePath) }.count
        TaskCompleteBanner(
            changedFileCount: changesModel.changedFiles.count,
            totalAdditions: changesModel.totalAdditions,
            totalDeletions: changesModel.totalDeletions,
            buildStatus: buildVerifier.status,
            sensitiveFileCount: sensitiveCount,
            buildDiagnostics: buildVerifier.diagnostics,
            onOpenDiagnostic: { diagnostic in
                let rootURL = workingDirectory.directoryURL
                let url: URL
                if (diagnostic.filePath as NSString).isAbsolutePath {
                    url = URL(fileURLWithPath: diagnostic.filePath)
                } else if let root = rootURL {
                    url = root.appendingPathComponent(diagnostic.filePath)
                } else {
                    return
                }
                filePreview.select(url, line: diagnostic.line)
            },
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
            onCreatePR: {
                showCreatePR = true
                showTaskBanner = false
            },
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
            },
            onExportSession: workingDirectory.directoryURL != nil ? {
                exportSessionAsMarkdown()
            } : nil,
            taskPrompt: promptHistoryStore.entries.first?.text,
            changedFiles: changesModel.changedFiles,
            onOpenFileDiff: { file in
                if let idx = changesModel.changedFiles.firstIndex(where: { $0.id == file.id }) {
                    changesModel.focusedFileIndex = idx
                }
                showDiffSummary = true
                showTaskBanner = false
            },
            unreviewedCount: changesModel.changedFiles.count - changesModel.reviewedCount,
            annotationCount: diffAnnotationStore.annotations.count,
            annotationPrompt: diffAnnotationStore.buildPrompt(),
            isSaturated: sessionHealthMonitor.isSaturated,
            onSelectSuggestion: { prompt in
                terminalProxy.sendPrompt(prompt)
            }
        )
    }

    /// Updates the "waiting for input" state for a tab and fires a macOS notification
    /// when the agent transitions into the waiting state while Anvil is in the background.
    private func handleAgentWaitingForInput(_ waiting: Bool, for tab: TerminalTab) {
        terminalTabs.setWaitingForInput(waiting, tabID: tab.id)
        if waiting {
            notificationManager.notifyWaitingForInput(tabID: tab.id, tabTitle: tab.title)
        }
    }

    /// Returns an EmbeddedTerminalView configured for the given tab, with the
    /// active/inactive styling applied.  Extracted as a helper to keep `projectView`
    /// under the Swift type-checker complexity limit.
    private func makeTabTerminalView(for tab: TerminalTab) -> some View {
        EmbeddedTerminalView(
            workingDirectory: workingDirectory,
            launchCopilotOverride: tab.launchCopilot,
            isActiveTab: tab.id == terminalTabs.activeTabID,
            onTitleChange: { title in
                terminalTabs.updateTitle(for: tab.id, to: title)
            },
            onOpenFile: { url, line in
                filePreview.select(url, line: line)
            },
            onOutputFilePath: { url in
                fileTreeModel.markAgentReference(url)
                guard autoFollow else { return }
                followAgent.reportChange(url)
            },
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
                        contextStore: contextStore,
                        activeTab: $sidebarTab,
                        onReviewAll: { showDiffSummary = true },
                        onBranchDiff: {
                            if let url = workingDirectory.directoryURL {
                                branchDiffModel.load(rootURL: url)
                            }
                            showDiffSummary = false
                            showBranchDiff = true
                        },
                        onCreatePR: { showCreatePR = true },
                        onResolveConflicts: { fileURL in
                            if let rootURL = workingDirectory.directoryURL {
                                let allConflictURLs = changesModel.conflictedFiles.map { $0.url }
                                mergeConflictModel.load(fileURL: fileURL, rootURL: rootURL, allConflictURLs: allConflictURLs)
                            }
                            showDiffSummary = false
                            showBranchDiff = false
                            showMergeConflict = true
                        },
                        lastTaskPrompt: promptHistoryStore.entries.first?.text
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
                    .onChange(of: terminalTabs.isAnyTabWaitingForInput) { _, isWaiting in
                        if isWaiting { NSSound.beep() }
                    }

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
                                // Mini header for the split pane
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
                                    },
                                    onOutputFilePath: { url in
                                        fileTreeModel.markAgentReference(url)
                                        guard autoFollow else { return }
                                        followAgent.reportChange(url)
                                    },
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

                    if showBranchGuardBanner, let rootURL = workingDirectory.directoryURL,
                       let branch = workingDirectory.gitBranch {
                        BranchGuardBanner(
                            branchName: branch,
                            rootURL: rootURL,
                            onBranchCreated: { _ in
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showBranchGuardBanner = false
                                }
                            },
                            onDismiss: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showBranchGuardBanner = false
                                }
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if showTaskBanner {
                        taskCompleteBannerView
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    StatusBarView(
                        workingDirectory: workingDirectory,
                        filePreview: filePreview,
                        changesModel: changesModel
                    )
                }

                if filePreview.selectedURL != nil || showDiffSummary || showBranchDiff || showMergeConflict || splitPreview {
                    PanelDivider(
                        width: $previewWidth,
                        minWidth: 200,
                        maxWidth: 800,
                        edge: .trailing
                    )

                    Group {
                        if !showMergeConflict && !showBranchDiff && !showDiffSummary && splitPreview {
                            // Split file preview: two independent panels side by side
                            HSplitView {
                                VStack(spacing: 0) {
                                    if let idx = currentChangeIndex {
                                        ChangesNavigationBar(
                                            currentIndex: idx,
                                            totalCount: changesModel.changedFiles.count,
                                            onPrevious: { navigateToPreviousChange() },
                                            onNext: { navigateToNextChange() }
                                        )
                                    }
                                    FilePreviewView(model: filePreview, changesModel: changesModel, buildDiagnostics: buildVerifier.diagnostics)
                                }
                                FilePreviewView(
                                    model: filePreview2,
                                    changesModel: changesModel,
                                    buildDiagnostics: buildVerifier.diagnostics,
                                    onOpenFile: {
                                        if let url = workingDirectory.directoryURL {
                                            quickOpenModel.index(rootURL: url, recentURLs: filePreview2.recentlyViewedURLs)
                                        }
                                        showSecondaryQuickOpen = true
                                    }
                                )
                            }
                        } else {
                            VStack(spacing: 0) {
                                if showMergeConflict {
                                    MergeConflictView(
                                        model: mergeConflictModel,
                                        onDismiss: {
                                            showMergeConflict = false
                                            mergeConflictModel.close()
                                        },
                                        onNavigateToFile: { fileURL in
                                            if let rootURL = workingDirectory.directoryURL {
                                                mergeConflictModel.load(fileURL: fileURL, rootURL: rootURL, allConflictURLs: mergeConflictModel.allConflictURLs)
                                            }
                                        }
                                    )
                                } else if showBranchDiff {
                                    BranchDiffView(
                                        model: branchDiffModel,
                                        annotationStore: diffAnnotationStore,
                                        onSelectFile: { path, _ in
                                            showBranchDiff = false
                                            if let root = workingDirectory.directoryURL {
                                                let url = root.appendingPathComponent(path)
                                                filePreview.select(url)
                                            }
                                        },
                                        onDismiss: { showBranchDiff = false },
                                        onShowInPreview: { [weak filePreview] path, line in
                                            showBranchDiff = false
                                            if let root = workingDirectory.directoryURL {
                                                let url = root.appendingPathComponent(path)
                                                filePreview?.select(url, line: line)
                                            }
                                        },
                                        onRevertHunk: { [weak changesModel] fileDiff, hunk in
                                            changesModel?.discardHunk(patch: DiffParser.reconstructPatch(fileDiff: fileDiff, hunk: hunk))
                                        }
                                    )
                                } else if showDiffSummary {
                                    DiffSummaryView(
                                        changesModel: changesModel,
                                        annotationStore: diffAnnotationStore,
                                        onSelectFile: { url in
                                            showDiffSummary = false
                                            filePreview.select(url)
                                        },
                                        onDismiss: { showDiffSummary = false },
                                        onShowFileAtLine: { [weak filePreview] url, line in
                                            showDiffSummary = false
                                            filePreview?.select(url, line: line)
                                        }
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

                                    FilePreviewView(model: filePreview, changesModel: changesModel, buildDiagnostics: buildVerifier.diagnostics)
                                }
                            }
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

            // Secondary panel Quick Open overlay
            if showSecondaryQuickOpen {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { dismissSecondaryQuickOpen() }

                VStack {
                    QuickOpenView(
                        model: quickOpenModel,
                        filePreview: filePreview2,
                        onDismiss: { dismissSecondaryQuickOpen() }
                    )
                    .padding(.top, 60)

                    Spacer()
                }
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

    private func dismissSecondaryQuickOpen() {
        showSecondaryQuickOpen = false
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
            PaletteCommand(id: "toggle-split-preview", title: splitPreview ? "Disable Split Preview" : "Enable Split Preview", icon: "rectangle.split.2x1", shortcut: "⌘\\", category: "View") {
                hasProject
            } action: {
                splitPreview.toggle()
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
            PaletteCommand(id: "toggle-auto-follow", title: autoFollow ? "Disable Follow Agent" : "Enable Follow Agent", icon: autoFollow ? "eye.slash" : "eye", shortcut: "⌘⇧A", category: "View") {
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

            PaletteCommand(id: "unstage-focused-hunk", title: "Unstage Focused Hunk", icon: "minus.circle", shortcut: "u", category: "Review") {
                changesModel.focusedHunk != nil
            } action: { [weak changesModel] in
                changesModel?.unstageFocusedHunk()
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

            PaletteCommand(id: "git-commit", title: "Commit", icon: "checkmark.circle", shortcut: "⌘↩", category: "Git") {
                hasProject && changesModel.canCommit
            } action: { [weak changesModel] in
                changesModel?.commit()
            },

            PaletteCommand(id: "git-commit-push", title: "Commit & Push", icon: "arrow.up.circle", shortcut: nil, category: "Git") {
                hasProject && changesModel.canCommit && workingDirectory.hasRemotes && !workingDirectory.isPushing
            } action: { [weak changesModel, weak workingDirectory] in
                changesModel?.commitAndPush { workingDirectory?.push() }
            },

            PaletteCommand(id: "git-stage-all-commit", title: "Stage All & Commit", icon: "checkmark.circle.badge.plus", shortcut: nil, category: "Git") {
                hasProject && !changesModel.changedFiles.isEmpty && !changesModel.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } action: { [weak changesModel] in
                changesModel?.stageAllAndCommit()
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
        showBranchGuardBanner = false
        branchGuardTriggered = false
        filePreview.close(persist: false)
        filePreview2.close(persist: false)
        showDiffSummary = false
        showBranchDiff = false
        showMergeConflict = false
        mergeConflictModel.close()
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

    private func checkBranchGuard() {
        guard !branchGuardTriggered else { return }
        guard let branch = workingDirectory.gitBranch,
              branch == "main" || branch == "master" else { return }
        guard branchGuardBehavior != "disabled" else { return }
        branchGuardTriggered = true
        if branchGuardBehavior == "autoBranch", let rootURL = workingDirectory.directoryURL {
            let name = BranchGuardBanner.autoBranchName()
            DispatchQueue.global(qos: .userInitiated).async {
                let result = GitBranchProvider.createBranch(named: name, in: rootURL)
                if !result.success {
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showBranchGuardBanner = true
                        }
                    }
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                showBranchGuardBanner = true
            }
        }
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

    /// Reads the active terminal's scrollback, generates a markdown document, saves it
    /// to the PromptHistory directory, and reveals it in Finder.
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

struct ToolbarView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    @ObservedObject var changesModel: ChangesModel
    @ObservedObject var activityModel: ActivityFeedModel
    @ObservedObject var filePreview: FilePreviewModel
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
    /// True when at least one terminal tab is waiting for user input.
    var isAgentWaitingForInput: Bool = false
    /// The current Copilot CLI agent mode (nil if not yet detected).
    var agentMode: AgentMode? = nil
    /// The current Copilot CLI model name (nil if not yet detected).
    var agentModel: String? = nil
    var onOpenDirectory: () -> Void
    var onSwitchProject: (URL) -> Void
    var onCloneRepository: () -> Void
    var onCompact: () -> Void
    /// Called when the "Agent needs input" indicator is tapped so the terminal
    /// can be focused.
    var onFocusTerminal: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.md) {
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
                            onBranchChanged: {
                                changesModel.refresh()
                            },
                            workingDirectory: workingDirectory
                        )
                    }
                }

                GitSyncControls(workingDirectory: workingDirectory)
            }

            Spacer()

            // Group 2: Unified agent status pill (mode + activity + session health)
            UnifiedAgentStatusPill(
                activityModel: activityModel,
                sessionHealthMonitor: sessionHealthMonitor,
                isAgentWaitingForInput: isAgentWaitingForInput,
                agentMode: agentMode,
                agentModel: agentModel,
                onFocusTerminal: onFocusTerminal ?? {},
                onCompact: onCompact
            )

            // Group 3: Overflow menu with secondary actions
            ToolbarOverflowMenu(
                autoFollow: $autoFollow,
                showCopilotActions: $showCopilotActions,
                showPromptHistory: $showPromptHistory,
                showInstructions: $showInstructions,
                showProjectSwitcher: $showProjectSwitcher,
                workingDirectory: workingDirectory,
                filePreview: filePreview,
                recentProjects: recentProjects,
                promptHistoryStore: promptHistoryStore,
                onOpenDirectory: onOpenDirectory,
                onSwitchProject: onSwitchProject,
                onCloneRepository: onCloneRepository
            )
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
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

// MARK: - Unified Agent Status Pill

/// Single clickable toolbar pill that unifies AgentModePill, AgentInputIndicator,
/// AgentActivityIndicator, and SessionHealthView into one element.
/// When the agent is waiting for input, clicking focuses the terminal.
/// Otherwise, clicking opens an expanded popover with full session details.
private struct UnifiedAgentStatusPill: View {
    @ObservedObject var activityModel: ActivityFeedModel
    @ObservedObject var sessionHealthMonitor: SessionHealthMonitor
    var isAgentWaitingForInput: Bool
    var agentMode: AgentMode?
    var agentModel: String?
    var onFocusTerminal: () -> Void
    var onCompact: () -> Void

    @EnvironmentObject private var terminalProxy: TerminalInputProxy
    @State private var showPopover = false
    @State private var isPulsing = false

    private var needsPulse: Bool {
        isAgentWaitingForInput || activityModel.isAgentActive
    }

    private var dotColor: Color {
        if isAgentWaitingForInput { return .orange }
        if activityModel.isAgentActive { return .green }
        if activityModel.sessionStats.isActive { return .green.opacity(0.6) }
        return Color.secondary.opacity(0.3)
    }

    private var pillBackground: Color {
        if isAgentWaitingForInput { return .orange.opacity(0.12) }
        if activityModel.isAgentActive { return .green.opacity(0.1) }
        return Color.secondary.opacity(0.07)
    }

    private var statusText: String {
        if isAgentWaitingForInput { return "Needs input" }
        if activityModel.isAgentActive {
            if let change = activityModel.latestFileChange {
                return change.url.lastPathComponent
            }
            return "Working…"
        }
        if activityModel.sessionStats.isActive {
            let n = activityModel.sessionStats.totalFilesTouched
            return "\(n) file\(n == 1 ? "" : "s")"
        }
        return "Idle"
    }

    private var contextBarColor: Color {
        if sessionHealthMonitor.contextFillness > 0.8 { return .orange }
        if sessionHealthMonitor.contextFillness > 0.5 { return .yellow }
        return Color(nsColor: .systemGreen)
    }

    private var helpText: String {
        if isAgentWaitingForInput {
            return "Agent is waiting for your input — click to focus terminal"
        }
        if activityModel.isAgentActive {
            return "Agent is actively making changes — click for details"
        }
        let n = activityModel.sessionStats.totalFilesTouched
        return n > 0
            ? "Agent idle — \(n) file\(n == 1 ? "" : "s") touched this session — click for details"
            : "Agent idle — no changes this session — click for details"
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
                        needsPulse
                            ? .easeInOut(duration: 0.65).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )
                    .onChange(of: isAgentWaitingForInput) { _, new in isPulsing = new || activityModel.isAgentActive }
                    .onChange(of: activityModel.isAgentActive) { _, new in isPulsing = new || isAgentWaitingForInput }
                    .onAppear { isPulsing = needsPulse }

                if let mode = agentMode {
                    Text(mode.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Text(statusText)
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
        .help(helpText)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            UnifiedAgentPopover(
                activityModel: activityModel,
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
        .animation(.easeInOut(duration: 0.2), value: activityModel.isAgentActive)
    }
}

/// Expanded popover for the unified agent status pill.
/// Shows mode/model controls, session health, and activity stats.
private struct UnifiedAgentPopover: View {
    @ObservedObject var activityModel: ActivityFeedModel
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
            // Header: status indicator + mode/model controls
            HStack(spacing: 8) {
                Circle()
                    .fill(activityModel.isAgentActive ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(activityModel.isAgentActive ? "Working…" : "Agent Idle")
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

            // Session health row
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

            // Activity stats
            VStack(alignment: .leading, spacing: 10) {
                let stats = activityModel.sessionStats
                if stats.totalFilesTouched > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Files Changed")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            if stats.filesCreated > 0 {
                                Label("\(stats.filesCreated) added", systemImage: "plus.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.green)
                            }
                            if stats.filesModified > 0 {
                                Label("\(stats.filesModified) modified", systemImage: "pencil.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                            }
                            if stats.filesDeleted > 0 {
                                Label("\(stats.filesDeleted) deleted", systemImage: "minus.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    if stats.totalAdditions > 0 || stats.totalDeletions > 0 {
                        HStack(spacing: 8) {
                            if stats.totalAdditions > 0 {
                                Text("+\(stats.totalAdditions)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                            if stats.totalDeletions > 0 {
                                Text("-\(stats.totalDeletions)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    if stats.commitCount > 0 {
                        Label("\(stats.commitCount) commit\(stats.commitCount == 1 ? "" : "s")", systemImage: "arrow.triangle.branch")
                            .font(.system(size: 11))
                            .foregroundStyle(.purple)
                    }
                } else {
                    Text("No changes this session")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

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

/// `...` overflow button containing secondary toolbar actions:
/// Follow Agent toggle, Copilot Actions, Prompt History, Instructions, and Switch Project.
/// Uses a single popover anchor so only one panel is shown at a time.
private struct ToolbarOverflowMenu: View {
    @Binding var autoFollow: Bool
    @Binding var showCopilotActions: Bool
    @Binding var showPromptHistory: Bool
    @Binding var showInstructions: Bool
    @Binding var showProjectSwitcher: Bool
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    var filePreview: FilePreviewModel
    @ObservedObject var recentProjects: RecentProjectsModel
    @ObservedObject var promptHistoryStore: PromptHistoryStore
    var onOpenDirectory: () -> Void
    var onSwitchProject: (URL) -> Void
    var onCloneRepository: () -> Void

    private enum ActivePanel: Identifiable {
        case copilotActions, promptHistory, instructions, projectSwitcher
        var id: Self { self }
    }

    @State private var activePanel: ActivePanel? = nil

    var body: some View {
        Menu {
            Toggle(isOn: $autoFollow) {
                Label(autoFollow ? "Follow Agent: On" : "Follow Agent: Off",
                      systemImage: autoFollow ? "eye" : "eye.slash")
            }
            Divider()
            Button {
                activePanel = .copilotActions
            } label: {
                Label("Copilot Actions", systemImage: "terminal")
            }
            Button {
                activePanel = .promptHistory
            } label: {
                Label("Prompt History", systemImage: "clock.arrow.circlepath")
            }
            Button {
                activePanel = .instructions
            } label: {
                Label("Instructions", systemImage: "doc.text")
            }
            Divider()
            Button {
                activePanel = .projectSwitcher
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
        .popover(item: $activePanel, arrowEdge: .bottom) { panel in
            switch panel {
            case .copilotActions:
                CopilotActionsView(onDismiss: { activePanel = nil })
            case .promptHistory:
                PromptHistoryView(
                    store: promptHistoryStore,
                    onDismiss: { activePanel = nil }
                )
            case .instructions:
                if let rootURL = workingDirectory.directoryURL {
                    InstructionsView(
                        rootURL: rootURL,
                        filePreview: filePreview,
                        onDismiss: { activePanel = nil }
                    )
                }
            case .projectSwitcher:
                ProjectSwitcherView(
                    recentProjects: recentProjects,
                    currentPath: workingDirectory.directoryURL?.standardizedFileURL.path,
                    onSelect: { url in
                        activePanel = nil
                        onSwitchProject(url)
                    },
                    onBrowse: {
                        activePanel = nil
                        onOpenDirectory()
                    },
                    onClone: {
                        activePanel = nil
                        onCloneRepository()
                    },
                    onDismiss: { activePanel = nil }
                )
            }
        }
        // Sync incoming bindings (e.g. from keyboard shortcuts) → local panel state
        .onChange(of: showCopilotActions) { _, v in if v && activePanel != .copilotActions { activePanel = .copilotActions } }
        .onChange(of: showPromptHistory) { _, v in if v && activePanel != .promptHistory { activePanel = .promptHistory } }
        .onChange(of: showInstructions) { _, v in if v && activePanel != .instructions { activePanel = .instructions } }
        .onChange(of: showProjectSwitcher) { _, v in if v && activePanel != .projectSwitcher { activePanel = .projectSwitcher } }
        // Sync local panel state → bindings
        .onChange(of: activePanel) { _, v in
            let isCopilot = v == .copilotActions
            let isHistory = v == .promptHistory
            let isInstructions = v == .instructions
            let isSwitcher = v == .projectSwitcher
            if showCopilotActions != isCopilot { showCopilotActions = isCopilot }
            if showPromptHistory != isHistory { showPromptHistory = isHistory }
            if showInstructions != isInstructions { showInstructions = isInstructions }
            if showProjectSwitcher != isSwitcher { showProjectSwitcher = isSwitcher }
        }
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
    @ObservedObject var contextStore: ContextStore
    @Binding var activeTab: SidebarTab
    var onReviewAll: (() -> Void)?
    var onBranchDiff: (() -> Void)?
    var onCreatePR: (() -> Void)?
    var onResolveConflicts: ((URL) -> Void)?
    var lastTaskPrompt: String? = nil

    @State private var activityUnread: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                SidebarTabButton(
                    title: "Files",
                    systemImage: "folder",
                    isActive: activeTab == .files,
                    badge: activeTab != .files && fileTreeModel.changedFileCount > 0 ? fileTreeModel.changedFileCount : nil
                ) {
                    activeTab = .files
                }

                SidebarTabButton(
                    title: "Changes",
                    systemImage: "arrow.triangle.2.circlepath",
                    isActive: activeTab == .changes,
                    badge: activeTab != .changes && changesModel.changedFiles.count > 0 ? changesModel.changedFiles.count : nil
                ) {
                    activeTab = .changes
                }

                SidebarTabButton(
                    title: "Activity",
                    systemImage: "waveform",
                    isActive: activeTab == .activity,
                    badge: activityUnread > 0 ? activityUnread : nil
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
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .background(.bar)

            Divider()

            // Content
            switch activeTab {
            case .files:
                if let rootURL = model.directoryURL {
                    FileTreeView(rootURL: rootURL, filePreview: filePreview, model: fileTreeModel, activityModel: activityModel, contextStore: contextStore)
                        .id(rootURL)
                } else {
                    VStack(spacing: Spacing.md) {
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
                ChangesListView(model: changesModel, filePreview: filePreview, workingDirectory: model, activityFeedModel: activityModel, onReviewAll: onReviewAll, onBranchDiff: onBranchDiff, onCreatePR: onCreatePR, onResolveConflicts: onResolveConflicts, lastTaskPrompt: lastTaskPrompt)

            case .activity:
                ActivityFeedView(model: activityModel, filePreview: filePreview, rootURL: model.directoryURL)

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
                    VStack(spacing: Spacing.md) {
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
        .onChange(of: activityModel.events.count) { oldCount, newCount in
            if activeTab != .activity && newCount > oldCount {
                activityUnread += newCount - oldCount
            }
        }
        .onChange(of: activeTab) { _, newTab in
            if newTab == .activity {
                activityUnread = 0
            }
        }
    }
}

struct SidebarTabButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    var badge: Int? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Color.accentColor : (isHovering ? .primary : .secondary))
                        .frame(width: 32, height: 22)

                    if let badge = badge {
                        Text("\(min(badge, 99))")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(x: 6, y: -4)
                    }
                }

                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(isActive ? Color.accentColor : (isHovering ? .primary : .secondary))
                    .lineLimit(1)
            }
            .frame(width: 48, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive
                        ? Color.accentColor.opacity(0.12)
                        : (isHovering ? Color.primary.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { isHovering = $0 }
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
    var onFindTerminalNext: () -> Void
    var onFindTerminalPrevious: () -> Void
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
    var onNextPreviewTab: (() -> Void)?
    var onPreviousPreviewTab: (() -> Void)?
    var onShowPromptHistory: (() -> Void)?
    var onGoToTestFile: (() -> Void)?
    var onToggleSplitPreview: (() -> Void)?
    var onExportSession: (() -> Void)?
    var recentProjects: RecentProjectsModel
    var onOpenRecentProject: ((URL) -> Void)?
    var onAskAboutSelection: (() -> Void)?

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
                onFindTerminalNext: onFindTerminalNext,
                onFindTerminalPrevious: onFindTerminalPrevious,
                onRevealInTree: onRevealInTree,
                onMentionInTerminal: onMentionInTerminal,
                onCloneRepository: onCloneRepository,
                onSplitTerminalH: onSplitTerminalH,
                onSplitTerminalV: onSplitTerminalV
            ))
            .modifier(FocusedSceneModifierD(
                onNextPreviewTab: onNextPreviewTab,
                onPreviousPreviewTab: onPreviousPreviewTab,
                onShowPromptHistory: onShowPromptHistory,
                onExportSession: onExportSession,
                onGoToTestFile: onGoToTestFile,
                onToggleSplitPreview: onToggleSplitPreview,
                recentProjects: recentProjects,
                onOpenRecentProject: onOpenRecentProject,
                onAskAboutSelection: onAskAboutSelection
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
    var onFindTerminalNext: () -> Void
    var onFindTerminalPrevious: () -> Void
    var onRevealInTree: (() -> Void)?
    var onMentionInTerminal: (() -> Void)?
    var onCloneRepository: (() -> Void)?
    var onSplitTerminalH: (() -> Void)?
    var onSplitTerminalV: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.newCopilotTab, hasProject ? onNewCopilotTab : nil)
            .focusedSceneValue(\.findTerminalNext, hasProject ? onFindTerminalNext : nil)
            .focusedSceneValue(\.findTerminalPrevious, hasProject ? onFindTerminalPrevious : nil)
            .focusedSceneValue(\.revealInTree, onRevealInTree)
            .focusedSceneValue(\.mentionInTerminal, onMentionInTerminal)
            .focusedSceneValue(\.cloneRepository, onCloneRepository)
            .focusedSceneValue(\.splitTerminalH, onSplitTerminalH)
            .focusedSceneValue(\.splitTerminalV, onSplitTerminalV)
    }
}

private struct FocusedSceneModifierD: ViewModifier {
    var onNextPreviewTab: (() -> Void)?
    var onPreviousPreviewTab: (() -> Void)?
    var onShowPromptHistory: (() -> Void)?
    var onExportSession: (() -> Void)?
    var onGoToTestFile: (() -> Void)?
    var onToggleSplitPreview: (() -> Void)?
    var recentProjects: RecentProjectsModel
    var onOpenRecentProject: ((URL) -> Void)?
    var onAskAboutSelection: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.nextPreviewTab, onNextPreviewTab)
            .focusedSceneValue(\.previousPreviewTab, onPreviousPreviewTab)
            .focusedSceneValue(\.showPromptHistory, onShowPromptHistory)
            .focusedSceneValue(\.exportSession, onExportSession)
            .focusedSceneValue(\.goToTestFile, onGoToTestFile)
            .focusedSceneValue(\.toggleSplitPreview, onToggleSplitPreview)
            .focusedSceneObject(recentProjects)
            .focusedSceneValue(\.openRecentProject, onOpenRecentProject)
            .focusedSceneValue(\.askAboutSelection, onAskAboutSelection)
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

/// Compact status pill in the toolbar showing the current agent state.
/// Always visible; clicking expands a popover with activity details.
struct AgentActivityIndicator: View {
    @ObservedObject var activityModel: ActivityFeedModel
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @State private var isPulsing = false
    @State private var showPopover = false

    private enum AgentState {
        case idle       // no file changes this session yet
        case working    // changes detected within the last 10 s
        case completed  // was working, now quiet, with changes recorded
    }

    private var currentState: AgentState {
        if activityModel.isAgentActive { return .working }
        if activityModel.sessionStats.isActive { return .completed }
        return .idle
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .scaleEffect(isPulsing && currentState == .working ? 1.3 : 1.0)
                    .animation(
                        currentState == .working
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )
                    .onChange(of: activityModel.isAgentActive) { _, active in
                        isPulsing = active
                    }
                    .onAppear { isPulsing = activityModel.isAgentActive }

                Text(pillLabel)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(currentState == .idle ? .tertiary : .secondary)

                if currentState != .idle {
                    Text("\(activityModel.sessionStats.totalFilesTouched)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(currentState == .working ? .green : .secondary)
                        .accessibilityLabel("\(activityModel.sessionStats.totalFilesTouched) files changed")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(pillBackgroundColor)
            )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            AgentStatusPopover(
                activityModel: activityModel,
                onJumpToTerminal: {
                    showPopover = false
                    if let tv = terminalProxy.terminalView {
                        tv.window?.makeFirstResponder(tv)
                    }
                }
            )
        }
    }

    private var dotColor: Color {
        switch currentState {
        case .idle:      return Color.secondary.opacity(0.3)
        case .working:   return Color.green
        case .completed: return Color.green.opacity(0.6)
        }
    }

    private var pillBackgroundColor: Color {
        switch currentState {
        case .idle:      return Color.clear
        case .working:   return Color.green.opacity(0.1)
        case .completed: return Color.secondary.opacity(0.08)
        }
    }

    private var pillLabel: String {
        switch currentState {
        case .idle:
            return "Idle"
        case .working:
            if let change = activityModel.latestFileChange {
                return change.url.lastPathComponent
            }
            return "Working…"
        case .completed:
            return summaryText
        }
    }

    private var helpText: String {
        switch currentState {
        case .idle:
            return "Agent idle — no changes this session"
        case .working:
            return "Agent is actively making changes"
        case .completed:
            let n = activityModel.sessionStats.totalFilesTouched
            return "Agent idle — \(n) file\(n == 1 ? "" : "s") touched this session"
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

/// Compact popover shown when the agent status pill is clicked.
/// Displays a summary of files touched, diff totals, the last event, and
/// a button to focus the terminal.
struct AgentStatusPopover: View {
    @ObservedObject var activityModel: ActivityFeedModel
    var onJumpToTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(activityModel.isAgentActive ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(activityModel.isAgentActive ? "Working…" : "Agent Idle")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                let stats = activityModel.sessionStats

                if stats.totalFilesTouched > 0 {
                    // Files breakdown
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Files Changed")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            if stats.filesCreated > 0 {
                                Label("\(stats.filesCreated) added", systemImage: "plus.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.green)
                            }
                            if stats.filesModified > 0 {
                                Label("\(stats.filesModified) modified", systemImage: "pencil.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                            }
                            if stats.filesDeleted > 0 {
                                Label("\(stats.filesDeleted) deleted", systemImage: "minus.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    // Diff line totals
                    if stats.totalAdditions > 0 || stats.totalDeletions > 0 {
                        HStack(spacing: 8) {
                            if stats.totalAdditions > 0 {
                                Text("+\(stats.totalAdditions)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                            if stats.totalDeletions > 0 {
                                Text("-\(stats.totalDeletions)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if stats.commitCount > 0 {
                        Label("\(stats.commitCount) commit\(stats.commitCount == 1 ? "" : "s")", systemImage: "arrow.triangle.branch")
                            .font(.system(size: 11))
                            .foregroundStyle(.purple)
                    }
                } else {
                    Text("No changes this session")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                // Last event
                if let lastEvent = activityModel.events.last {
                    Divider()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last Event")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Image(systemName: lastEvent.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(lastEvent.displayName)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                        }

                        Text(lastEvent.timestamp, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Jump to terminal
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
        .frame(width: 260)
    }
}

// MARK: - Agent Mode Pill

/// Compact toolbar pill that shows the current Copilot CLI agent mode and model.
/// Tapping the mode segment cycles through Interactive → Plan → Autopilot.
/// Tapping the model segment opens a popover listing available models.
private struct AgentModePill: View {
    var mode: AgentMode?
    var model: String?
    @EnvironmentObject private var terminalProxy: TerminalInputProxy
    @State private var showModelPicker = false

    /// Known Copilot CLI models shown in the model picker popover.
    private static let knownModels: [String] = [
        "gpt-4.1",
        "gpt-4o",
        "o1",
        "o3",
        "claude-3.5-sonnet",
        "claude-3.7-sonnet"
    ]

    var body: some View {
        HStack(spacing: 0) {
            // Mode segment — click to cycle to next mode
            Button {
                let next = mode?.next ?? .interactive
                terminalProxy.send(next.activateCommand)
            } label: {
                Text(mode?.displayName ?? "Mode")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(mode != nil ? .primary : .tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .help(mode.map { "Mode: \($0.displayName) — click to cycle" }
                ?? "Agent mode unknown — click to set Interactive")

            Divider()
                .frame(height: 12)
                .opacity(0.5)

            // Model segment — click to pick a model
            Button {
                showModelPicker.toggle()
            } label: {
                Text(model ?? "Model")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(model != nil ? .primary : .tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .help(model.map { "Model: \($0) — click to switch" }
                ?? "Model unknown — click to select")
            .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
                modelPickerPopover
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
                )
        )
    }

    private var modelPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Select Model")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ForEach(Self.knownModels, id: \.self) { name in
                Button {
                    terminalProxy.send("/model \(name)\n")
                    showModelPicker = false
                } label: {
                    HStack {
                        Text(name)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .opacity(name == model ? 1 : 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Footer hint
            Text("Custom: /model <name>")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(width: 220)
    }
}

// MARK: - Agent Input Indicator

/// Pulsing toolbar pill shown when any terminal tab is blocked waiting for
/// user input (plan approval, y/n confirmation, clarifying question, etc.).
/// Clicking the indicator focuses the terminal so the developer can respond.
private struct AgentInputIndicator: View {
    var onFocusTerminal: () -> Void
    @State private var isPulsing = false

    var body: some View {
        Button(action: onFocusTerminal) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                    .scaleEffect(isPulsing ? 1.4 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                Text("Agent needs input")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .help("Agent is waiting for your input — click to focus terminal")
        .onAppear { isPulsing = true }
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
