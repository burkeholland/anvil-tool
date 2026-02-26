import SwiftUI
import AppKit

/// Shows all git-changed files in a list with status indicators and diff stats,
/// plus staging controls, a commit form, and recent commit history.
struct ChangesListView: View {
    @ObservedObject var model: ChangesModel
    @ObservedObject var filePreview: FilePreviewModel
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    var activityFeedModel: ActivityFeedModel? = nil
    var onReviewAll: (() -> Void)?
    var onBranchDiff: (() -> Void)?
    var onCreatePR: (() -> Void)?
    var onResolveConflicts: ((URL) -> Void)?
    /// The most recent task prompt, used to generate the copy summary.
    var lastTaskPrompt: String? = nil
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @State private var fileToDiscard: ChangedFile?
    @State private var fileToRedo: ChangedFile?
    @State private var redoPromptText: String = ""
    @State private var showDiscardAllConfirm = false
    @State private var showUndoCommitConfirm = false
    @State private var stashToDrop: StashEntry?
    @State private var showOnlyUnreviewed = false
    @State private var collapsedGroups: Set<String> = []
    @State private var showCopiedConfirmation = false
    @State private var copiedDismissTask: DispatchWorkItem?

    private enum ChangeScope: String, CaseIterable {
        case all = "All Changes"
        case lastTask = "Last Task"
        case sinceSnapshot = "Since Snapshot"
    }
    @State private var changeScope: ChangeScope = .all

    // MARK: - File Grouping Mode

    enum GroupingMode: String, CaseIterable {
        case directory = "directory"
        case changeType = "changeType"
        case fileKind = "fileKind"

        var label: String {
            switch self {
            case .directory:  return "Directory"
            case .changeType: return "Type"
            case .fileKind:   return "Kind"
            }
        }
    }

    @State private var groupingMode: GroupingMode = .directory

    private func groupingModeKey() -> String? {
        guard let path = workingDirectory.directoryURL?.standardizedFileURL.path else { return nil }
        return "dev.anvil.changesGroupingMode.\(path)"
    }

    private func saveGroupingMode() {
        guard let key = groupingModeKey() else { return }
        UserDefaults.standard.set(groupingMode.rawValue, forKey: key)
    }

    private func loadGroupingMode() {
        guard let key = groupingModeKey(),
              let raw = UserDefaults.standard.string(forKey: key),
              let mode = GroupingMode(rawValue: raw) else { return }
        groupingMode = mode
    }

    // MARK: - Scope-filtered file lists

    private var displayedFiles: [ChangedFile] {
        switch changeScope {
        case .all:           return model.changedFiles
        case .lastTask:      return model.lastTaskChangedFiles
        case .sinceSnapshot: return model.snapshotDeltaFiles
        }
    }

    private var displayedStagedFiles: [ChangedFile] {
        displayedFiles.filter { $0.staging == .staged || $0.staging == .partial }
    }

    private var displayedUnstagedFiles: [ChangedFile] {
        displayedFiles.filter { $0.staging == .unstaged || $0.staging == .partial }
    }

    private var displayedTotalAdditions: Int {
        displayedFiles.compactMap(\.diff).reduce(0) { $0 + $1.additionCount }
    }

    private var displayedTotalDeletions: Int {
        displayedFiles.compactMap(\.diff).reduce(0) { $0 + $1.deletionCount }
    }

    private var displayedSensitiveFiles: [ChangedFile] {
        displayedFiles.filter { SensitiveFileClassifier.isSensitive($0.relativePath) }
    }

    private var testCoverageMap: [URL: TestCoverageChecker.TestCoverage] {
        TestCoverageChecker.coverage(for: displayedFiles)
    }

    var body: some View {
        if model.isLoading && model.changedFiles.isEmpty && model.recentCommits.isEmpty {
            loadingView
        } else {
            contentList
        }
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text("Scanning changes…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var changesTopSections: some View {
        if !model.changedFiles.isEmpty {
            Section {
                CommitFormView(
                    model: model,
                    onPush: workingDirectory.hasRemotes ? { workingDirectory.push() } : nil,
                    activityFeedModel: activityFeedModel
                )
            }
            if let onReviewAll, model.changedFiles.count > 0 {
                Section {
                    Button {
                        onReviewAll()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 11))
                            Text("Review All Changes")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("⌘⇧D")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    ReviewProgressBar(
                        reviewed: model.reviewedCount,
                        total: model.changedFiles.count,
                        showOnlyUnreviewed: $showOnlyUnreviewed,
                        onMarkAll: { model.markAllReviewed() },
                        onClearAll: { model.clearAllReviewed() }
                    )
                    testCoverageSummarySection
                }
            }
            Section {
                Button {
                    copySummaryToClipboard()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Copy Summary")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("for PR description")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                Button {
                    model.takeSnapshot()
                    changeScope = .sinceSnapshot
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.teal)
                        Text("Take Snapshot")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("checkpoint")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .help("Capture the current diff state so you can see only new changes after the next agent run")
                if model.snapshots.count > 1 {
                    snapshotPickerRow
                }
            }
        }
        if let onBranchDiff, workingDirectory.gitBranch != nil {
            Section {
                Button {
                    onBranchDiff()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.pull")
                            .font(.system(size: 11))
                            .foregroundStyle(.purple)
                        Text("Branch Diff")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("PR Preview")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
        if workingDirectory.hasRemotes && (workingDirectory.aheadCount > 0 || !workingDirectory.hasUpstream) && model.changedFiles.isEmpty {
            Section {
                SyncPromptView(workingDirectory: workingDirectory)
            }
        }
        if workingDirectory.hasUpstream && model.changedFiles.isEmpty {
            if let prURL = workingDirectory.openPRURL, let url = URL(string: prURL) {
                Section {
                    PRStatusRow(title: workingDirectory.openPRTitle ?? "Open Pull Request", url: url)
                }
            } else if let onCreatePR, workingDirectory.aheadCount == 0 {
                Section {
                    Button {
                        onCreatePR()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.pull")
                                .font(.system(size: 11))
                                .foregroundStyle(.purple)
                            Text("Create Pull Request")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var conflictsSection: some View {
        if !model.conflictedFiles.isEmpty {
            Section {
                ForEach(model.conflictedFiles) { file in
                    HStack(spacing: 6) {
                        ChangedFileRow(
                            file: file,
                            isSelected: false,
                            isStaged: false,
                            isReviewed: false,
                            isFocused: false,
                            onDiscard: { fileToDiscard = file }
                        )
                        if let onResolveConflicts {
                            Button {
                                onResolveConflicts(file.url)
                            } label: {
                                Text("Resolve")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(.red)
                        }
                    }
                    .contentShape(Rectangle())
                    .contextMenu { changedFileContextMenu(file: file, isStaged: false) }
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text("Merge Conflicts")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                        .textCase(nil)
                    Spacer()
                }
            }
        }
    }

    /// A segmented toggle shown when a task-start baseline or snapshot is available,
    /// letting the user switch between all uncommitted changes, last-task changes, and snapshot delta.
    @ViewBuilder
    private var changeScopeSection: some View {
        let available = availableScopes
        if available.count > 1 && !model.changedFiles.isEmpty {
            Section {
                Picker("Changes scope", selection: $changeScope) {
                    ForEach(available, id: \.self) { scope in
                        Text(scopeShortLabel(scope)).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 2)
            }
        }
    }

    /// The scope options that are currently meaningful to show.
    private var availableScopes: [ChangeScope] {
        var scopes: [ChangeScope] = [.all]
        if model.hasTaskStart { scopes.append(.lastTask) }
        if !model.snapshots.isEmpty { scopes.append(.sinceSnapshot) }
        return scopes
    }

    private func scopeShortLabel(_ scope: ChangeScope) -> String {
        switch scope {
        case .all:           return "All"
        case .lastTask:      return "Last Task"
        case .sinceSnapshot: return "Snapshot"
        }
    }

    /// Inline picker row for selecting which snapshot to compare against (shown only when >1 snapshot).
    @ViewBuilder
    private var snapshotPickerRow: some View {
        HStack(spacing: 6) {
            Text("Compare to:")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Picker("Snapshot", selection: $model.activeSnapshotID) {
                ForEach(Array(model.snapshots.reversed())) { snap in
                    Text(snap.label).tag(Optional(snap.id))
                }
            }
            .labelsHidden()
            .font(.system(size: 10))
            .frame(maxWidth: 120)
        }
        .padding(.vertical, 1)
    }

    /// A summary row showing test coverage stats and a button to ask the agent for tests.
    @ViewBuilder
    private var testCoverageSummarySection: some View {
        let covMap = testCoverageMap
        let (covered, total) = TestCoverageChecker.stats(from: covMap)
        if total > 0 {
            TestCoverageSummaryRow(
                covered: covered,
                total: total,
                onAskForTests: covered < total ? {
                    let uncovered = displayedFiles.filter { covMap[$0.url] == .uncovered }
                    let paths = uncovered.map { "@\($0.relativePath)" }.joined(separator: " ")
                    terminalProxy.sendPrompt("Please add tests for: \(paths)")
                } : nil
            )
        }
    }

    /// A segmented toggle for choosing how the changed-file list is grouped.
    @ViewBuilder
    private var groupingModeSection: some View {
        if !model.changedFiles.isEmpty {
            Section {
                Picker("Group by", selection: $groupingMode) {
                    ForEach(GroupingMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 2)
                .onChange(of: groupingMode) { saveGroupingMode() }
            }
        }
    }

    @ViewBuilder
    private var sensitiveFilesSection: some View {
        let files = displayedSensitiveFiles
        if !files.isEmpty {
            let covMap = testCoverageMap
            Section {
                ForEach(files) { file in
                    let isStaged = file.staging == .staged || file.staging == .partial
                    fileRow(file: file, isStaged: isStaged, isSensitive: true,
                            testCoverage: covMap[file.url] ?? .notApplicable)
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Requires Careful Review")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .textCase(nil)
                    Spacer()
                    Text("\(files.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.7)))
                }
            }
        }
    }

    @ViewBuilder
    private var stagedSection: some View {
        if !displayedStagedFiles.isEmpty {
            let covMap = testCoverageMap
            Section {
                let files = showOnlyUnreviewed ? displayedStagedFiles.filter { !model.isReviewed($0) } : displayedStagedFiles
                groupedFileRows(files: ReviewPriorityScorer.sorted(files), isStaged: true, coverageMap: covMap)
            } header: {
                HStack(spacing: 8) {
                    Text("Staged Changes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                    Spacer()
                    Button { model.unstageAll() } label: {
                        Text("Unstage All")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var unstagedSection: some View {
        if !displayedUnstagedFiles.isEmpty {
            let covMap = testCoverageMap
            Section {
                let files = showOnlyUnreviewed ? displayedUnstagedFiles.filter { !model.isReviewed($0) } : displayedUnstagedFiles
                groupedFileRows(files: ReviewPriorityScorer.sorted(files), isStaged: false, coverageMap: covMap)
            } header: {
                unstagedSectionHeader
            }
        } else if displayedStagedFiles.isEmpty && !model.isLoading {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        if changeScope == .lastTask && !model.changedFiles.isEmpty {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary.opacity(0.6))
                            Text("No changes from last task")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else if changeScope == .sinceSnapshot && !model.changedFiles.isEmpty {
                            Image(systemName: "camera")
                                .font(.system(size: 16))
                                .foregroundStyle(.teal.opacity(0.6))
                            Text("No new changes since snapshot")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.green.opacity(0.6))
                            Text("Working tree clean")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 8)
                    Spacer()
                }
            } header: {
                Text("Changes")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    private var unstagedSectionHeader: some View {
        HStack(spacing: 8) {
            Text("Changes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
            Spacer()
            if displayedTotalAdditions > 0 {
                Text("+\(displayedTotalAdditions)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.green)
            }
            if displayedTotalDeletions > 0 {
                Text("-\(displayedTotalDeletions)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.red)
            }
            Button { showDiscardAllConfirm = true } label: {
                Text("Discard All")
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Discard all uncommitted changes (stashes first for recovery)")
            Button { model.stageAll() } label: {
                Text("Stage All")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var historyAndStashSections: some View {
        if !model.recentCommits.isEmpty {
            Section {
                ForEach(Array(model.recentCommits.enumerated()), id: \.element.id) { index, commit in
                    CommitRow(
                        commit: commit,
                        isLatest: index == 0,
                        model: model,
                        filePreview: filePreview,
                        onUndoCommit: index == 0 ? { showUndoCommitConfirm = true } : nil
                    )
                }
            } header: {
                Text("Recent Commits")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        if !model.stashes.isEmpty || !model.changedFiles.isEmpty {
            Section {
                ForEach(model.stashes) { stash in
                    StashRow(
                        stash: stash,
                        model: model,
                        filePreview: filePreview,
                        onDropStash: { stashToDrop = stash }
                    )
                }
            } header: {
                HStack {
                    Text("Stashes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                    if !model.stashes.isEmpty {
                        Text("\(model.stashes.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.4)))
                    }
                    Spacer()
                    if !model.changedFiles.isEmpty {
                        Button {
                            model.stashAll()
                        } label: {
                            Text("Stash All")
                                .font(.system(size: 10))
                                .foregroundStyle(.teal.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                        .help("Stash all uncommitted changes")
                    }
                }
            }
        }
    }

    // List + keyboard + focused-value bindings (split to stay within type-checker limits)
    private var listBase: some View {
        listWithKeyPress
            .focusedValue(\.nextReviewFile, !model.changedFiles.isEmpty ? {
                model.focusNextFile()
                if let url = model.focusedFile?.url { filePreview.select(url) }
            } : nil)
            .focusedValue(\.previousReviewFile, !model.changedFiles.isEmpty ? {
                model.focusPreviousFile()
                if let url = model.focusedFile?.url { filePreview.select(url) }
            } : nil)
            .focusedValue(\.nextHunk, !model.changedFiles.isEmpty ? { model.focusNextHunk() } : nil)
            .focusedValue(\.previousHunk, !model.changedFiles.isEmpty ? { model.focusPreviousHunk() } : nil)
    }

    private var listWithKeyPress: some View {
        ScrollViewReader { proxy in
            List {
                changesTopSections
                changeScopeSection
                groupingModeSection
                conflictsSection
                sensitiveFilesSection
                stagedSection
                unstagedSection
                historyAndStashSections
            }
            .listStyle(.sidebar)
            .onAppear { loadGroupingMode() }
            .onKeyPress { keyPress in
                switch keyPress.characters {
                case "]":
                    model.focusNextFile()
                    if let url = model.focusedFile?.url { filePreview.select(url) }
                    return .handled
                case "[":
                    model.focusPreviousFile()
                    if let url = model.focusedFile?.url { filePreview.select(url) }
                    return .handled
                case "n":
                    model.focusNextUnreviewedFile()
                    if let url = model.focusedFile?.url { filePreview.select(url) }
                    return .handled
                case "p":
                    model.focusPreviousUnreviewedFile()
                    if let url = model.focusedFile?.url { filePreview.select(url) }
                    return .handled
                case "j": model.focusNextHunk(); return .handled
                case "k": model.focusPreviousHunk(); return .handled
                case "s": model.stageFocusedHunk(); return .handled
                case "u": model.unstageFocusedHunk(); return .handled
                case "d": model.discardFocusedHunk(); return .handled
                case "r": model.toggleFocusedFileReviewed(); return .handled
                default:
                    if keyPress.key == .return {
                        if let url = model.focusedFile?.url { filePreview.select(url) }
                        return .handled
                    }
                    return .ignored
                }
            }
            .focusedValue(\.stageFocusedHunk, model.focusedHunk != nil ? { model.stageFocusedHunk() } : nil)
            .focusedValue(\.unstageFocusedHunk, model.focusedHunk != nil ? { model.unstageFocusedHunk() } : nil)
            .focusedValue(\.discardFocusedHunk, model.focusedHunk != nil ? { model.discardFocusedHunk() } : nil)
            .focusedValue(\.toggleFocusedFileReviewed, model.focusedFile != nil ? { model.toggleFocusedFileReviewed() } : nil)
            .focusedValue(\.openFocusedFile, model.focusedFile != nil ? { if let url = model.focusedFile?.url { filePreview.select(url) } } : nil)
            .onChange(of: model.focusedFileIndex) { _, idx in
                guard let idx, model.changedFiles.indices.contains(idx) else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(model.changedFiles[idx].id, anchor: .center)
                }
            }
        }
    }

    // Alerts layered on top of listBase
    private var listWithAlerts: some View {
        listBase
            .alert("Discard Changes?", isPresented: Binding(
                get: { fileToDiscard != nil },
                set: { if !$0 { fileToDiscard = nil } }
            )) {
                Button("Discard", role: .destructive) {
                    if let file = fileToDiscard {
                        model.discardChanges(for: file)
                        if filePreview.selectedURL == file.url { filePreview.refresh() }
                    }
                    fileToDiscard = nil
                }
                Button("Cancel", role: .cancel) { fileToDiscard = nil }
            } message: {
                if let file = fileToDiscard {
                    let adds = file.diff.map { "+\($0.additionCount)" } ?? ""
                    let dels = file.diff.map { "-\($0.deletionCount)" } ?? ""
                    let stats = [adds, dels].filter { !$0.isEmpty }.joined(separator: " / ")
                    let statsSuffix = stats.isEmpty ? "" : " (\(stats))"
                    Text("Discard uncommitted changes to \"\(file.fileName)\"\(statsSuffix)? An Undo banner will appear for 8 seconds.")
                }
            }
            .alert("Discard All Changes?", isPresented: $showDiscardAllConfirm) {
                Button("Discard All", role: .destructive) { model.discardAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will discard all \(model.changedFiles.count) uncommitted changed file\(model.changedFiles.count == 1 ? "" : "s"). Changes are stashed so you can recover them.")
            }
            .alert("Undo Last Commit?", isPresented: $showUndoCommitConfirm) {
                Button("Undo Commit", role: .destructive) { model.undoLastCommit() }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let commit = model.recentCommits.first {
                    Text("This will undo \"\(commit.message)\" (\(commit.shortSHA)). The changes will be moved back to the staging area — no work is lost.")
                }
            }
            .alert("Drop Stash?", isPresented: Binding(
                get: { stashToDrop != nil },
                set: { if !$0 { stashToDrop = nil } }
            )) {
                Button("Drop", role: .destructive) {
                    if let stash = stashToDrop { model.dropStash(sha: stash.sha) }
                    stashToDrop = nil
                }
                Button("Cancel", role: .cancel) { stashToDrop = nil }
            } message: {
                if let stash = stashToDrop {
                    Text("This will permanently delete stash@{\(stash.index)} (\(stash.cleanMessage)). This cannot be undone.")
                }
            }
            .sheet(isPresented: Binding(
                get: { fileToRedo != nil },
                set: { if !$0 { fileToRedo = nil } }
            )) {
                RedoWithFeedbackSheet(
                    promptText: $redoPromptText,
                    onSubmit: {
                        if let file = fileToRedo {
                            model.discardChanges(for: file)
                            if filePreview.selectedURL == file.url { filePreview.refresh() }
                            terminalProxy.sendPrompt(redoPromptText)
                        }
                        fileToRedo = nil
                    },
                    onCancel: { fileToRedo = nil }
                )
            }
    }

    private var contentList: some View {
        listWithAlerts
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    if model.lastStashError != nil {
                        StashErrorBanner(model: model)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if model.lastUndoneCommitSHA != nil {
                        UndoCommitBanner(model: model)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if model.lastDiscardStashRef != nil {
                        DiscardRecoveryBanner(model: model)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if model.lastDiscardedHunkPatch != nil {
                        DiscardHunkRecoveryBanner(model: model)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if model.activeDiscardBannerEntry != nil {
                        DiscardFileRecoveryBanner(model: model)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .overlay(alignment: .center) {
                if showCopiedConfirmation {
                    Text("Summary copied to clipboard")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.lastDiscardStashRef != nil)
            .animation(.easeInOut(duration: 0.2), value: model.lastUndoneCommitSHA != nil)
            .animation(.easeInOut(duration: 0.2), value: model.lastStashError != nil)
            .animation(.easeInOut(duration: 0.2), value: model.lastDiscardedHunkPatch != nil)
            .animation(.easeInOut(duration: 0.2), value: model.activeDiscardBannerEntry != nil)
            .animation(.easeInOut(duration: 0.2), value: showCopiedConfirmation)
    }

    private func redoPrompt(for file: ChangedFile) -> String {
        "Please redo the changes to \(file.relativePath) — "
    }

    private func copySummaryToClipboard() {
        let files = displayedFiles
        let summary = ChangeSummaryGenerator.generate(files: files, taskPrompt: lastTaskPrompt)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        copiedDismissTask?.cancel()
        showCopiedConfirmation = true
        let task = DispatchWorkItem { showCopiedConfirmation = false }
        copiedDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: task)
    }

    // MARK: - Grouping Helpers

    /// Groups files by directory, preserving the relative order directories appear in the list.
    private func directoryGroups(from files: [ChangedFile]) -> [(dir: String, files: [ChangedFile])] {
        var seen = Set<String>()
        var orderedDirs: [String] = []
        for file in files {
            if seen.insert(file.directoryPath).inserted {
                orderedDirs.append(file.directoryPath)
            }
        }
        return orderedDirs.map { dir in (dir, files.filter { $0.directoryPath == dir }) }
    }

    /// Groups files by their git change type (Added, Modified, Deleted, Renamed).
    private func changeTypeGroups(from files: [ChangedFile]) -> [(label: String, icon: String, color: Color, files: [ChangedFile])] {
        let order: [(label: String, icon: String, color: Color, statuses: [GitFileStatus])] = [
            ("Added",    "plus.circle.fill",   .green,  [.added, .untracked]),
            ("Modified", "pencil.circle.fill",  .orange, [.modified]),
            ("Deleted",  "minus.circle.fill",   .red,    [.deleted]),
            ("Renamed",  "arrow.right.circle.fill", .blue, [.renamed]),
        ]
        return order.compactMap { entry in
            let matching = files.filter { entry.statuses.contains($0.status) }
            guard !matching.isEmpty else { return nil }
            return (entry.label, entry.icon, entry.color, matching)
        }
    }

    /// Infers a file kind (Source, Tests, Config, Docs) from its path and extension.
    private static func fileKind(for file: ChangedFile) -> (label: String, icon: String, color: Color) {
        let path = file.relativePath.lowercased()
        let name = file.fileName.lowercased()
        let ext = (file.fileName as NSString).pathExtension.lowercased()

        // Docs
        let docExtensions: Set<String> = ["md", "rst", "txt", "adoc"]
        let docPrefixes = ["readme", "changelog", "license", "contributing", "authors", "notice"]
        if docExtensions.contains(ext) || docPrefixes.contains(where: { name.hasPrefix($0) }) {
            return ("Docs", "doc.text.fill", .purple)
        }

        // Config
        let configExtensions: Set<String> = ["json", "yaml", "yml", "toml", "lock", "env", "ini", "cfg", "conf"]
        let configNames: Set<String> = [
            ".gitignore", ".gitattributes", ".editorconfig", ".eslintrc", ".prettierrc",
            ".babelrc", ".swiftlint.yml", "makefile", "dockerfile", "package.json",
            "tsconfig.json", "jest.config.js", "vite.config.ts", "webpack.config.js",
        ]
        if configExtensions.contains(ext) || configNames.contains(name) {
            return ("Config", "gearshape.fill", .gray)
        }

        // Tests
        let testPathSegments = ["/tests/", "/test/", "/__tests__/", "/spec/", "/specs/"]
        let testFileParts = ["test", "spec", ".test.", ".spec.", "tests.swift"]
        if testPathSegments.contains(where: { path.contains($0) })
            || testFileParts.contains(where: { name.contains($0) }) {
            return ("Tests", "testtube.2", .teal)
        }

        // Source (catch-all)
        return ("Source", "chevron.left.forwardslash.chevron.right", .blue)
    }

    /// Groups files by inferred file kind (Source, Tests, Config, Docs).
    private func fileKindGroups(from files: [ChangedFile]) -> [(label: String, icon: String, color: Color, files: [ChangedFile])] {
        let order = ["Source", "Tests", "Config", "Docs"]
        var buckets: [String: (icon: String, color: Color, files: [ChangedFile])] = [:]
        for file in files {
            let kind = Self.fileKind(for: file)
            buckets[kind.label, default: (kind.icon, kind.color, [])].files.append(file)
        }
        return order.compactMap { label in
            guard let bucket = buckets[label], !bucket.files.isEmpty else { return nil }
            return (label, bucket.icon, bucket.color, bucket.files)
        }
    }

    /// Renders a single changed-file row with tap, context menu, and drag support.
    @ViewBuilder
    private func fileRow(file: ChangedFile, isStaged: Bool, showDirectoryLabel: Bool = true, isSensitive: Bool = false,
                         testCoverage: TestCoverageChecker.TestCoverage = .notApplicable) -> some View {
        let fileIdx = model.changedFiles.firstIndex(where: { $0.id == file.id })
        ChangedFileRow(
            file: file,
            isSelected: filePreview.selectedURL == file.url,
            isStaged: isStaged,
            isReviewed: model.isReviewed(file),
            isFocused: fileIdx == model.focusedFileIndex,
            isSensitive: isSensitive,
            showDirectoryLabel: showDirectoryLabel,
            testCoverage: testCoverage,
            onToggleReview: { model.toggleReviewed(file) },
            onOpenFile: { filePreview.select(file.url) },
            onDiscard: { fileToDiscard = file },
            onRedo: {
                fileToRedo = file
                redoPromptText = redoPrompt(for: file)
            },
            onStageHunk: file.diff.map { diff in
                { hunk in model.stageHunk(patch: DiffParser.reconstructPatch(fileDiff: diff, hunk: hunk)) }
            },
            onUnstageHunk: file.diff.map { diff in
                { hunk in model.unstageHunk(patch: DiffParser.reconstructPatch(fileDiff: diff, hunk: hunk)) }
            },
            onDiscardHunk: file.diff.map { diff in
                { hunk in model.discardHunk(patch: DiffParser.reconstructPatch(fileDiff: diff, hunk: hunk)) }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            filePreview.select(file.url)
            if let idx = fileIdx {
                model.focusedFileIndex = idx
                model.focusedHunkIndex = nil
            }
        }
        .contextMenu { changedFileContextMenu(file: file, isStaged: isStaged) }
        .draggable(file.url)
        .id(file.id)
    }

    /// Renders files grouped according to the current `groupingMode`.
    @ViewBuilder
    private func groupedFileRows(files: [ChangedFile], isStaged: Bool,
                                 coverageMap: [URL: TestCoverageChecker.TestCoverage] = [:]) -> some View {
        switch groupingMode {
        case .directory:
            let groups = directoryGroups(from: files)
            if groups.count > 1 {
                ForEach(groups, id: \.dir) { group in
                    DirectoryGroupHeader(
                        directory: group.dir,
                        files: group.files,
                        isCollapsed: collapsedGroups.contains(group.dir)
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            collapsedGroups = collapsedGroups.symmetricDifference([group.dir])
                        }
                    }
                    if !collapsedGroups.contains(group.dir) {
                        ForEach(group.files) { file in
                            fileRow(file: file, isStaged: isStaged, showDirectoryLabel: false,
                                    testCoverage: coverageMap[file.url] ?? .notApplicable)
                                .padding(.leading, 12)
                        }
                    }
                }
            } else {
                ForEach(files) { file in
                    fileRow(file: file, isStaged: isStaged,
                            testCoverage: coverageMap[file.url] ?? .notApplicable)
                }
            }

        case .changeType:
            let groups = changeTypeGroups(from: files)
            if groups.count > 1 {
                ForEach(groups, id: \.label) { group in
                    GenericGroupHeader(
                        label: group.label,
                        systemImage: group.icon,
                        color: group.color,
                        count: group.files.count,
                        isCollapsed: collapsedGroups.contains(group.label)
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            collapsedGroups = collapsedGroups.symmetricDifference([group.label])
                        }
                    }
                    if !collapsedGroups.contains(group.label) {
                        ForEach(group.files) { file in
                            fileRow(file: file, isStaged: isStaged,
                                    testCoverage: coverageMap[file.url] ?? .notApplicable)
                                .padding(.leading, 12)
                        }
                    }
                }
            } else {
                ForEach(files) { file in
                    fileRow(file: file, isStaged: isStaged,
                            testCoverage: coverageMap[file.url] ?? .notApplicable)
                }
            }

        case .fileKind:
            let groups = fileKindGroups(from: files)
            if groups.count > 1 {
                ForEach(groups, id: \.label) { group in
                    GenericGroupHeader(
                        label: group.label,
                        systemImage: group.icon,
                        color: group.color,
                        count: group.files.count,
                        isCollapsed: collapsedGroups.contains(group.label)
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            collapsedGroups = collapsedGroups.symmetricDifference([group.label])
                        }
                    }
                    if !collapsedGroups.contains(group.label) {
                        ForEach(group.files) { file in
                            fileRow(file: file, isStaged: isStaged,
                                    testCoverage: coverageMap[file.url] ?? .notApplicable)
                                .padding(.leading, 12)
                        }
                    }
                }
            } else {
                ForEach(files) { file in
                    fileRow(file: file, isStaged: isStaged,
                            testCoverage: coverageMap[file.url] ?? .notApplicable)
                }
            }
        }
    }

    @ViewBuilder
    private func changedFileContextMenu(file: ChangedFile, isStaged: Bool) -> some View {
        // Review toggle
        Button {
            model.toggleReviewed(file)
        } label: {
            if model.isReviewed(file) {
                Label("Mark as Unreviewed", systemImage: "eye.slash")
            } else {
                Label("Mark as Reviewed", systemImage: "eye")
            }
        }

        Divider()

        if isStaged {
            Button {
                model.unstageFile(file)
            } label: {
                Label("Unstage", systemImage: "minus.circle")
            }
        } else if file.status != .untracked {
            Button {
                model.stageFile(file)
            } label: {
                Label("Stage", systemImage: "plus.circle")
            }
        } else {
            Button {
                model.stageFile(file)
            } label: {
                Label("Track & Stage", systemImage: "plus.circle")
            }
        }

        Divider()

        Button {
            terminalProxy.mentionFile(relativePath: file.relativePath)
        } label: {
            Label("Mention in Terminal", systemImage: "terminal")
        }

        Divider()

        Button {
            ExternalEditorManager.openFile(file.url)
        } label: {
            if let editor = ExternalEditorManager.preferred {
                Label("Open in \(editor.name)", systemImage: "square.and.pencil")
            } else {
                Label("Open in Default App", systemImage: "square.and.pencil")
            }
        }

        Divider()

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.relativePath, forType: .string)
        } label: {
            Label("Copy Relative Path", systemImage: "doc.on.doc")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.url.path, forType: .string)
        } label: {
            Label("Copy Absolute Path", systemImage: "doc.on.doc.fill")
        }

        Divider()

        Button {
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        if let rootURL = workingDirectory.directoryURL {
            Button {
                GitHubURLBuilder.openFile(rootURL: rootURL, relativePath: file.relativePath)
            } label: {
                Label("Open in GitHub", systemImage: "arrow.up.right.square")
            }
        }

        Divider()

        Button(role: .destructive) {
            fileToDiscard = file
        } label: {
            Label("Discard Changes…", systemImage: "arrow.uturn.backward")
        }

        Button {
            fileToRedo = file
            redoPromptText = redoPrompt(for: file)
        } label: {
            Label("Redo with Feedback…", systemImage: "arrow.uturn.right")
        }
    }
}

// MARK: - Review Progress

struct ReviewProgressBar: View {
    let reviewed: Int
    let total: Int
    @Binding var showOnlyUnreviewed: Bool
    var onMarkAll: () -> Void
    var onClearAll: () -> Void

    private var progress: Double {
        total > 0 ? Double(reviewed) / Double(total) : 0
    }

    private var isComplete: Bool { reviewed == total && total > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "eye")
                    .font(.system(size: 10))
                    .foregroundStyle(isComplete ? .green : .blue.opacity(0.7))

                Text("\(reviewed)/\(total) reviewed")
                    .font(.system(size: 11))
                    .foregroundStyle(isComplete ? .green : .secondary)

                Spacer()

                Button {
                    showOnlyUnreviewed.toggle()
                } label: {
                    Text(showOnlyUnreviewed ? "Show All" : "Unreviewed")
                        .font(.system(size: 10))
                        .foregroundStyle(showOnlyUnreviewed ? .blue : .secondary)
                }
                .buttonStyle(.plain)

                if reviewed > 0 && !isComplete {
                    Button {
                        onMarkAll()
                    } label: {
                        Text("Mark All")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                if reviewed > 0 {
                    Button {
                        onClearAll()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(isComplete ? Color.green : Color.blue.opacity(0.6))
                        .frame(width: geo.size.width * progress)
                        .animation(.easeInOut(duration: 0.2), value: progress)
                }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Test Coverage Summary

/// A row showing how many implementation files in the current changeset have test coverage,
/// with an optional one-click button to ask the agent to add missing tests.
struct TestCoverageSummaryRow: View {
    let covered: Int
    let total: Int
    var onAskForTests: (() -> Void)? = nil

    private var isAllCovered: Bool { covered == total }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isAllCovered ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(isAllCovered ? .teal : .orange)

            Text(summaryText)
                .font(.system(size: 11))
                .foregroundStyle(isAllCovered ? .teal : .secondary)

            Spacer()

            if !isAllCovered, let onAskForTests {
                Button(action: onAskForTests) {
                    Text("Ask for tests")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryText: String {
        let noun = total == 1 ? "file" : "files"
        let verb = total == 1 ? "has" : "have"
        if isAllCovered {
            return "\(total) changed \(noun) \(verb) test coverage"
        }
        return "\(covered) of \(total) changed \(noun) \(verb) test coverage"
    }
}

// MARK: - Commit Form

struct CommitFormView: View {
    @ObservedObject var model: ChangesModel
    /// Called after a successful commit to trigger a push. When nil, push options are hidden.
    var onPush: (() -> Void)?
    /// Activity feed model used to auto-generate a conventional commit message.
    var activityFeedModel: ActivityFeedModel? = nil

    @AppStorage("dev.anvil.commitMessageStyle") private var storedStyle: String = ChangesModel.CommitMessageStyle.conventional.rawValue

    // MARK: - Style helpers

    private var messageStyle: ChangesModel.CommitMessageStyle {
        ChangesModel.CommitMessageStyle(rawValue: storedStyle) ?? .conventional
    }

    // MARK: - Title / body split

    /// The first line of `commitMessage` (the subject).
    private var titleText: String {
        model.commitMessage.components(separatedBy: "\n").first ?? ""
    }

    /// Everything after the first blank line separator in `commitMessage`.
    private var bodyText: String {
        let msg = model.commitMessage
        if let range = msg.range(of: "\n\n") {
            return String(msg[range.upperBound...])
        }
        return ""
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { titleText },
            set: { newTitle in
                let body = bodyText
                model.commitMessage = body.isEmpty ? newTitle : newTitle + "\n\n" + body
            }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { bodyText },
            set: { newBody in
                let title = titleText
                model.commitMessage = newBody.isEmpty ? title : title + "\n\n" + newBody
            }
        )
    }

    // MARK: - Status helpers

    /// Files that are entirely unstaged (not staged at all).
    private var purelyUnstagedFiles: [ChangedFile] {
        model.changedFiles.filter { $0.staging == .unstaged }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Style picker
            Picker("", selection: Binding(
                get: { messageStyle },
                set: { newStyle in
                    storedStyle = newStyle.rawValue
                    model.commitMessage = model.generateCommitMessage(
                        style: newStyle,
                        sessionStats: activityFeedModel?.sessionStats
                    )
                }
            )) {
                ForEach(ChangesModel.CommitMessageStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)

            // Title field
            ZStack(alignment: .topLeading) {
                if titleText.isEmpty {
                    Text("Summary (required)")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                }
                TextField("", text: titleBinding)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .onSubmit {
                        guard model.canCommit else { return }
                        model.commit()
                    }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .overlay(alignment: .centerTrailing) {
                Button {
                    model.commitMessage = model.generateCommitMessage(
                        style: messageStyle,
                        sessionStats: activityFeedModel?.sessionStats
                    )
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Auto-generate commit message from changes")
                .padding(.trailing, 4)
            }

            // Body field
            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty {
                    Text("Description (optional)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                }
                TextEditor(text: bodyBinding)
                    .font(.system(size: 11))
                    .frame(minHeight: 44, maxHeight: 88)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command), model.canCommit else { return .ignored }
                        model.commit()
                        return .handled
                    }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .onAppear {
                autoFillIfNeeded()
            }
            .onChange(of: model.stagedFiles.count) { oldCount, newCount in
                if oldCount == 0 && newCount > 0 {
                    autoFillIfNeeded()
                }
            }

            HStack(spacing: 8) {
                Button {
                    model.commit()
                } label: {
                    HStack(spacing: 4) {
                        if model.isCommitting {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(model.stagedFiles.isEmpty ? "Commit" : "Commit (\(model.stagedFiles.count))")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.canCommit)
                .help("Commit staged changes (⌘↩)")

                Menu {
                    Button("Stage All & Commit") {
                        model.stageAllAndCommit()
                    }
                    .disabled(model.changedFiles.isEmpty || model.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let onPush {
                        Divider()
                        Button("Commit & Push") {
                            model.commitAndPush(pushAction: onPush)
                        }
                        .disabled(!model.canCommit)
                        Button("Stage All & Commit & Push") {
                            model.stageAllAndCommitAndPush(pushAction: onPush)
                        }
                        .disabled(model.changedFiles.isEmpty || model.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }

            // Unstaged changes warning
            if !model.stagedFiles.isEmpty && !purelyUnstagedFiles.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text("\(purelyUnstagedFiles.count) unstaged file\(purelyUnstagedFiles.count == 1 ? "" : "s") won't be included")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if model.unreviewedStagedCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("\(model.unreviewedStagedCount) staged file\(model.unreviewedStagedCount == 1 ? "" : "s") not yet reviewed")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange.opacity(0.9))
                }
            } else if model.reviewedCount > 0 && model.reviewedCount == model.changedFiles.count {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("All changes reviewed — ready to commit")
                        .font(.system(size: 10))
                        .foregroundStyle(.green.opacity(0.9))
                }
            }

            if let error = model.lastCommitError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func autoFillIfNeeded() {
        guard model.commitMessage.isEmpty, !model.stagedFiles.isEmpty else { return }
        model.commitMessage = model.generateCommitMessage(
            style: messageStyle,
            sessionStats: activityFeedModel?.sessionStats
        )
    }
}

// MARK: - Commit Row

struct CommitRow: View {
    let commit: GitCommit
    var isLatest: Bool = false
    @ObservedObject var model: ChangesModel
    @ObservedObject var filePreview: FilePreviewModel
    var onUndoCommit: (() -> Void)?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Commit header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                if isExpanded && commit.files == nil {
                    model.loadCommitFiles(for: commit.sha)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(commit.message)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)
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
                }
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .contextMenu {
                if isLatest, let onUndoCommit {
                    Button {
                        onUndoCommit()
                    } label: {
                        Label("Undo Commit…", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!model.canUndoCommit)

                    Divider()
                }

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

                if let rootURL = model.rootDirectory {
                    Divider()

                    Button {
                        GitHubURLBuilder.openCommit(rootURL: rootURL, sha: commit.sha)
                    } label: {
                        Label("Open Commit in GitHub", systemImage: "arrow.up.right.square")
                    }
                }
            }

            // Expanded file list
            if isExpanded {
                if let files = commit.files {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(files) { file in
                            CommitFileRow(
                                file: file,
                                commitSHA: commit.sha,
                                model: model,
                                filePreview: filePreview
                            )
                        }
                    }
                    .padding(.leading, 18)
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.mini)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Stash Row

struct StashRow: View {
    let stash: StashEntry
    @ObservedObject var model: ChangesModel
    @ObservedObject var filePreview: FilePreviewModel
    var onDropStash: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Stash header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                if isExpanded && stash.files == nil {
                    model.loadStashFiles(for: stash.sha)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.teal)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stash.cleanMessage)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            Text(stash.displayName)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.teal.opacity(0.8))

                            Spacer()

                            Text(stash.relativeDate)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    model.applyStash(sha: stash.sha)
                } label: {
                    Label("Apply", systemImage: "arrow.uturn.forward")
                }

                Button {
                    model.popStash(sha: stash.sha)
                } label: {
                    Label("Pop (Apply & Remove)", systemImage: "tray.and.arrow.up")
                }

                Divider()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(stash.sha, forType: .string)
                } label: {
                    Label("Copy SHA", systemImage: "doc.on.doc")
                }

                Divider()

                Button(role: .destructive) {
                    onDropStash()
                } label: {
                    Label("Drop Stash…", systemImage: "trash")
                }
            }

            // Expanded file list
            if isExpanded {
                if let files = stash.files {
                    VStack(alignment: .leading, spacing: 0) {
                        // Action buttons
                        HStack(spacing: 8) {
                            Button {
                                model.applyStash(sha: stash.sha)
                            } label: {
                                Label("Apply", systemImage: "arrow.uturn.forward")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                model.popStash(sha: stash.sha)
                            } label: {
                                Label("Pop", systemImage: "tray.and.arrow.up")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()

                            Button(role: .destructive) {
                                onDropStash()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red.opacity(0.7))
                            .help("Drop stash")
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)

                        ForEach(files) { file in
                            StashFileRow(
                                file: file,
                                stashIndex: stash.index,
                                model: model,
                                filePreview: filePreview
                            )
                        }
                    }
                    .padding(.leading, 18)
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.mini)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Stash File Row

struct StashFileRow: View {
    let file: CommitFile
    let stashIndex: Int
    @ObservedObject var model: ChangesModel
    @ObservedObject var filePreview: FilePreviewModel

    var body: some View {
        HStack(spacing: 6) {
            Text(file.status)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(statusColor)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !file.directoryPath.isEmpty {
                    Text(file.directoryPath)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            HStack(spacing: 3) {
                if file.additions > 0 {
                    Text("+\(file.additions)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.green)
                }
                if file.deletions > 0 {
                    Text("-\(file.deletions)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let rootURL = model.rootDirectory else { return }
            filePreview.selectStashFile(
                path: file.path,
                stashIndex: stashIndex,
                rootURL: rootURL
            )
        }
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        }
    }

    private var statusColor: Color {
        switch file.status {
        case "A": return .green
        case "D": return .red
        case "R": return .blue
        default:  return .orange
        }
    }
}

/// Banner shown when a stash operation fails.
struct StashErrorBanner: View {
    @ObservedObject var model: ChangesModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(.red)

            if let error = model.lastStashError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                model.lastStashError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Commit File Row

struct CommitFileRow: View {
    let file: CommitFile
    let commitSHA: String
    @ObservedObject var model: ChangesModel
    @ObservedObject var filePreview: FilePreviewModel

    var body: some View {
        HStack(spacing: 6) {
            Text(file.status)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(statusColor)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !file.directoryPath.isEmpty {
                    Text(file.directoryPath)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            HStack(spacing: 3) {
                if file.additions > 0 {
                    Text("+\(file.additions)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.green)
                }
                if file.deletions > 0 {
                    Text("-\(file.deletions)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let rootURL = model.rootDirectory else { return }
            filePreview.selectCommitFile(
                path: file.path,
                commitSHA: commitSHA,
                rootURL: rootURL
            )
        }
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        }
    }

    private var statusColor: Color {
        switch file.status {
        case "A": return .green
        case "D": return .red
        case "R": return .blue
        default:  return .orange
        }
    }
}

struct ChangedFileRow: View {
    let file: ChangedFile
    let isSelected: Bool
    var isStaged: Bool = false
    var isReviewed: Bool = false
    var isFocused: Bool = false
    var isSensitive: Bool = false
    var showDirectoryLabel: Bool = true
    var testCoverage: TestCoverageChecker.TestCoverage = .notApplicable
    var onToggleReview: (() -> Void)? = nil
    var onOpenFile: (() -> Void)? = nil
    var onDiscard: (() -> Void)? = nil
    var onRedo: (() -> Void)? = nil
    var onStageHunk: ((DiffHunk) -> Void)? = nil
    var onUnstageHunk: ((DiffHunk) -> Void)? = nil
    var onDiscardHunk: ((DiffHunk) -> Void)? = nil

    @State private var isHovering = false
    @State private var dismissTask: DispatchWorkItem?

    private var priority: ReviewPriority { ReviewPriorityScorer.score(file) }

    private var changeDescription: String? {
        guard let diff = file.diff else { return nil }
        return DiffChangeDescriber.describe(diff: diff, fileExtension: file.url.pathExtension)
    }

    var body: some View {
        HStack(spacing: 6) {
            // Status badge
            Text(statusLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(file.status.color)
                )

            // File name and path
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(file.fileName)
                        .font(.system(.body, design: .default))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(isReviewed ? .secondary : .primary)

                    if isSensitive {
                        Text("⚠️")
                            .font(.system(size: 11))
                            .help("Sensitive file — requires careful review before committing")
                    }

                    if testCoverage == .uncovered {
                        Text("no tests")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                            .help("No test file changed for this implementation file")
                    } else if testCoverage == .covered {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.teal.opacity(0.6))
                            .help("Test file also modified in this changeset")
                    }
                }

                if let description = changeDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if showDirectoryLabel && !file.directoryPath.isEmpty {
                    Text(file.directoryPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            // Diff stats
            if let diff = file.diff {
                HStack(spacing: 4) {
                    if diff.additionCount > 0 {
                        Text("+\(diff.additionCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    if diff.deletionCount > 0 {
                        Text("-\(diff.deletionCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
            }

            // Risk indicator dot
            ReviewPriorityIndicator(priority: priority)

            // Review toggle button (checkbox)
            if let onToggleReview {
                Button {
                    onToggleReview()
                } label: {
                    Image(systemName: isReviewed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(isReviewed ? Color.blue.opacity(0.8) : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.borderless)
                .help(isReviewed ? "Mark as unreviewed (R)" : "Mark as reviewed (R)")
            }

            // Discard button (trash icon, shown on hover)
            if let onDiscard, isHovering {
                Button {
                    onDiscard()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Discard Changes…")
            }

            // Redo button (arrow.uturn.right, shown on hover)
            if let onRedo, isHovering {
                Button {
                    onRedo()
                } label: {
                    Image(systemName: "arrow.uturn.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .help("Redo with Feedback…")
            }

            // Staging indicator
            switch file.staging {
            case .staged:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            case .partial:
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .help("Partially staged - some hunks are staged, others are not")
            case .unstaged:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.2))
                : nil
        )
        .overlay(
            isFocused && !isSelected
                ? RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                : nil
        )
        .onHover { hovering in
            dismissTask?.cancel()
            if hovering {
                isHovering = true
            } else {
                let task = DispatchWorkItem { isHovering = false }
                dismissTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
            }
        }
        .onDisappear { dismissTask?.cancel() }
        .popover(isPresented: Binding(
            get: { isHovering && file.diff != nil },
            set: { if !$0 { isHovering = false } }
        ), arrowEdge: .trailing) {
            if let diff = file.diff {
                DiffPreviewPopover(
                    diff: diff,
                    stagedDiff: file.stagedDiff,
                    onStageHunk: onStageHunk,
                    onUnstageHunk: onUnstageHunk,
                    onDiscardHunk: onDiscardHunk,
                    onOpenFull: onOpenFile
                )
            }
        }
    }

    private var statusLabel: String {
        switch file.status {
        case .modified:   return "M"
        case .added:      return "A"
        case .deleted:    return "D"
        case .untracked:  return "?"
        case .renamed:    return "R"
        case .conflicted: return "!"
        }
    }
}

// MARK: - Directory Group Header

/// A collapsible directory header row shown in the Changes panel when files span multiple directories.
struct DirectoryGroupHeader: View {
    let directory: String
    let files: [ChangedFile]
    let isCollapsed: Bool
    let onToggle: () -> Void

    private var displayName: String {
        directory.isEmpty ? "(root)" : directory
    }

    private var totalAdditions: Int {
        files.compactMap(\.diff).reduce(0) { $0 + $1.additionCount }
    }

    private var totalDeletions: Int {
        files.compactMap(\.diff).reduce(0) { $0 + $1.deletionCount }
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 5) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)

                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer()

                HStack(spacing: 3) {
                    if totalAdditions > 0 {
                        Text("+\(totalAdditions)")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    if totalDeletions > 0 {
                        Text("-\(totalDeletions)")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

/// A collapsible group header for change-type and file-kind grouping modes.
struct GenericGroupHeader: View {
    let label: String
    let systemImage: String
    let color: Color
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 5) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)

                Image(systemName: systemImage)
                    .font(.system(size: 10))
                    .foregroundStyle(color)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(color.opacity(0.5)))
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

/// Banner shown after "Discard All" with a button to recover stashed changes.
struct DiscardRecoveryBanner: View {
    @ObservedObject var model: ChangesModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 12))
                .foregroundStyle(.orange)

            Text("Changes stashed.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                model.recoverDiscarded()
            } label: {
                Text("Undo")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                model.lastDiscardStashRef = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Banner shown after "Discard Hunk" with a button to re-apply the discarded hunk.
struct DiscardHunkRecoveryBanner: View {
    @ObservedObject var model: ChangesModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash.circle")
                .font(.system(size: 12))
                .foregroundStyle(.orange)

            Text("Hunk discarded.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                model.undoDiscardHunk()
            } label: {
                Text("Undo")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                model.lastDiscardedHunkPatch = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Banner shown after a per-file discard with an Undo button to restore the file.
struct DiscardFileRecoveryBanner: View {
    @ObservedObject var model: ChangesModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 12))
                .foregroundStyle(.orange)

            if let entry = model.activeDiscardBannerEntry {
                Text("\"\(entry.fileName)\" discarded.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                model.undoDiscardFile()
            } label: {
                Text("Undo")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                model.dismissDiscardUndo()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Banner shown after "Undo Commit" confirming the action.
struct UndoCommitBanner: View {
    @ObservedObject var model: ChangesModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 12))
                .foregroundStyle(.blue)

            if let sha = model.lastUndoneCommitSHA {
                Text("Commit \(sha) undone. Changes are staged.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                model.lastUndoneCommitSHA = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Prompt shown in the Changes panel when there are unpushed commits.
struct SyncPromptView: View {
    @ObservedObject var workingDirectory: WorkingDirectoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)

                if workingDirectory.hasUpstream {
                    Text("\(workingDirectory.aheadCount) unpushed commit\(workingDirectory.aheadCount == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text("Branch not published")
                        .font(.system(size: 12, weight: .medium))
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    workingDirectory.push()
                } label: {
                    HStack(spacing: 4) {
                        if workingDirectory.isPushing {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(workingDirectory.hasUpstream ? "Push" : "Publish Branch")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(workingDirectory.isPushing)

                if workingDirectory.behindCount > 0 {
                    Button {
                        workingDirectory.pull()
                    } label: {
                        HStack(spacing: 4) {
                            if workingDirectory.isPulling {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text("Pull")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(workingDirectory.isPulling)
                }
            }

            if let error = workingDirectory.lastSyncError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Row shown in the Changes panel when the current branch has an open pull request.
struct PRStatusRow: View {
    let title: String
    let url: URL

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 11))
                .foregroundStyle(.purple)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Text("Open")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Redo With Feedback Sheet

/// A sheet that presents a pre-filled, editable prompt asking Copilot to redo
/// the changes to a specific file. On submit the prompt is sent to the terminal.
struct RedoWithFeedbackSheet: View {
    @Binding var promptText: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Redo with Feedback")
                .font(.headline)

            Text("Describe what went wrong so Copilot can try again. The file's changes will be discarded before the prompt is sent.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Prompt", text: $promptText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...8)
                .focused($isTextFieldFocused)
                .onSubmit { onSubmit() }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Send") { onSubmit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420, maxWidth: 520)
        .onAppear { isTextFieldFocused = true }
    }
}
