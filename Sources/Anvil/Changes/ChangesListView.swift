import SwiftUI
import AppKit

/// Shows all git-changed files in a list with status indicators and diff stats,
/// plus staging controls, a commit form, and recent commit history.
struct ChangesListView: View {
    @ObservedObject var model: ChangesModel
    @ObservedObject var filePreview: FilePreviewModel
    @ObservedObject var workingDirectory: WorkingDirectoryModel
    var onReviewAll: (() -> Void)?
    var onBranchDiff: (() -> Void)?
    var onCreatePR: (() -> Void)?
    var onResolveConflicts: ((URL) -> Void)?
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @State private var fileToDiscard: ChangedFile?
    @State private var showDiscardAllConfirm = false
    @State private var showUndoCommitConfirm = false
    @State private var stashToDrop: StashEntry?
    @State private var showOnlyUnreviewed = false

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
                CommitFormView(model: model)
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
                            isFocused: false
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

    @ViewBuilder
    private var stagedSection: some View {
        if !model.stagedFiles.isEmpty {
            Section {
                let files = showOnlyUnreviewed ? model.stagedFiles.filter { !model.isReviewed($0) } : model.stagedFiles
                ForEach(files) { file in
                    let fileIdx = model.changedFiles.firstIndex(where: { $0.id == file.id })
                    ChangedFileRow(
                        file: file,
                        isSelected: filePreview.selectedURL == file.url,
                        isStaged: true,
                        isReviewed: model.isReviewed(file),
                        isFocused: fileIdx == model.focusedFileIndex,
                        onToggleReview: { model.toggleReviewed(file) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        filePreview.select(file.url)
                        if let idx = fileIdx {
                            model.focusedFileIndex = idx
                            model.focusedHunkIndex = nil
                        }
                    }
                    .contextMenu { changedFileContextMenu(file: file, isStaged: true) }
                    .draggable(file.url)
                }
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
        if !model.unstagedFiles.isEmpty {
            Section {
                let files = showOnlyUnreviewed ? model.unstagedFiles.filter { !model.isReviewed($0) } : model.unstagedFiles
                ForEach(files) { file in
                    let fileIdx = model.changedFiles.firstIndex(where: { $0.id == file.id })
                    ChangedFileRow(
                        file: file,
                        isSelected: filePreview.selectedURL == file.url,
                        isStaged: false,
                        isReviewed: model.isReviewed(file),
                        isFocused: fileIdx == model.focusedFileIndex,
                        onToggleReview: { model.toggleReviewed(file) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        filePreview.select(file.url)
                        if let idx = fileIdx {
                            model.focusedFileIndex = idx
                            model.focusedHunkIndex = nil
                        }
                    }
                    .contextMenu { changedFileContextMenu(file: file, isStaged: false) }
                    .draggable(file.url)
                }
            } header: {
                unstagedSectionHeader
            }
        } else if model.stagedFiles.isEmpty && !model.isLoading {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.green.opacity(0.6))
                        Text("Working tree clean")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
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
            if model.totalAdditions > 0 {
                Text("+\(model.totalAdditions)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.green)
            }
            if model.totalDeletions > 0 {
                Text("-\(model.totalDeletions)")
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
        if !model.stashes.isEmpty {
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
                    Spacer()
                    Text("\(model.stashes.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.4)))
                }
            }
        }
    }

    // List + keyboard + focused-value bindings (split to stay within type-checker limits)
    private var listBase: some View {
        List {
            changesTopSections
            conflictsSection
            stagedSection
            unstagedSection
            historyAndStashSections
        }
        .listStyle(.sidebar)
        .onKeyPress { keyPress in
            switch keyPress.characters {
            case "]": model.focusNextFile(); return .handled
            case "[": model.focusPreviousFile(); return .handled
            case "j", "n": model.focusNextHunk(); return .handled
            case "k", "p": model.focusPreviousHunk(); return .handled
            case "s": model.stageFocusedHunk(); return .handled
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
        .focusedValue(\.nextReviewFile, !model.changedFiles.isEmpty ? { model.focusNextFile() } : nil)
        .focusedValue(\.previousReviewFile, !model.changedFiles.isEmpty ? { model.focusPreviousFile() } : nil)
        .focusedValue(\.nextHunk, !model.changedFiles.isEmpty ? { model.focusNextHunk() } : nil)
        .focusedValue(\.previousHunk, !model.changedFiles.isEmpty ? { model.focusPreviousHunk() } : nil)
        .focusedValue(\.stageFocusedHunk, model.focusedHunk != nil ? { model.stageFocusedHunk() } : nil)
        .focusedValue(\.discardFocusedHunk, model.focusedHunk != nil ? { model.discardFocusedHunk() } : nil)
        .focusedValue(\.toggleFocusedFileReviewed, model.focusedFile != nil ? { model.toggleFocusedFileReviewed() } : nil)
        .focusedValue(\.openFocusedFile, model.focusedFile != nil ? { if let url = model.focusedFile?.url { filePreview.select(url) } } : nil)
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
                    Text("This will permanently discard all uncommitted changes to \"\(file.fileName)\". This cannot be undone.")
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
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.lastDiscardStashRef != nil)
            .animation(.easeInOut(duration: 0.2), value: model.lastUndoneCommitSHA != nil)
            .animation(.easeInOut(duration: 0.2), value: model.lastStashError != nil)
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

        Divider()

        Button(role: .destructive) {
            fileToDiscard = file
        } label: {
            Label("Discard Changes…", systemImage: "arrow.uturn.backward")
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

// MARK: - Commit Form

struct CommitFormView: View {
    @ObservedObject var model: ChangesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Commit message field
            ZStack(alignment: .topLeading) {
                if model.commitMessage.isEmpty {
                    Text("Commit message")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                }
                TextEditor(text: $model.commitMessage)
                    .font(.system(size: 12))
                    .frame(minHeight: 36, maxHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .overlay(alignment: .bottomTrailing) {
                Button {
                    model.commitMessage = model.generateCommitMessage()
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Generate commit message from changes")
                .padding(4)
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

                Menu {
                    Button("Stage All & Commit") {
                        model.stageAllAndCommit()
                    }
                    .disabled(model.changedFiles.isEmpty || model.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
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
                            StashFileRow(file: file)
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
    var onToggleReview: (() -> Void)? = nil

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
                Text(file.fileName)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isReviewed ? .secondary : .primary)

                if !file.directoryPath.isEmpty {
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

            // Staging indicator
            if isStaged {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
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
