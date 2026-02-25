import Foundation
import Combine

/// A single changed file entry for the changes list.
struct ChangedFile: Identifiable {
    let url: URL
    let relativePath: String
    let status: GitFileStatus
    let staging: StagingState
    var diff: FileDiff?

    var id: URL { url }

    var fileName: String { url.lastPathComponent }

    var directoryPath: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }
}

/// Manages the list of git-changed files and their diffs.
/// Owns its own FileWatcher to refresh independently of the file tree tab.
final class ChangesModel: ObservableObject {
    @Published private(set) var changedFiles: [ChangedFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var recentCommits: [GitCommit] = []
    @Published private(set) var isLoadingCommits = false
    @Published private(set) var stashes: [StashEntry] = []
    @Published private(set) var isLoadingStashes = false
    @Published var lastStashError: String?

    @Published var commitMessage: String = ""
    @Published private(set) var isCommitting = false
    @Published private(set) var lastCommitError: String?
    @Published private(set) var isDiscardingAll = false
    /// The stash reference after a "Discard All" so the user can recover.
    @Published var lastDiscardStashRef: String?
    @Published private(set) var isUndoingCommit = false
    /// The SHA of the commit that was undone, so the user can see what was reverted.
    @Published var lastUndoneCommitSHA: String?
    /// Error message from the most recent hunk-level operation.
    @Published var lastHunkError: String?

    // MARK: - Review Tracking

    /// Relative paths the user has marked as reviewed in this session.
    @Published private(set) var reviewedPaths: Set<String> = []
    /// Fingerprints (adds:dels:staging) captured when each file was marked reviewed.
    /// Used to auto-clear review marks when a file's diff changes.
    private var reviewedFingerprints: [String: String] = [:]

    private(set) var rootDirectory: URL?
    private var refreshGeneration: UInt64 = 0
    private var commitGeneration: UInt64 = 0
    private var stashGeneration: UInt64 = 0
    private var fileWatcher: FileWatcher?

    deinit {
        fileWatcher?.stop()
    }

    var totalAdditions: Int {
        changedFiles.compactMap(\.diff).reduce(0) { $0 + $1.additionCount }
    }

    var totalDeletions: Int {
        changedFiles.compactMap(\.diff).reduce(0) { $0 + $1.deletionCount }
    }

    var stagedFiles: [ChangedFile] {
        changedFiles.filter { $0.staging == .staged || $0.staging == .partial }
    }

    var unstagedFiles: [ChangedFile] {
        changedFiles.filter { $0.staging == .unstaged || $0.staging == .partial }
    }

    var canCommit: Bool {
        !stagedFiles.isEmpty && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCommitting
    }

    // MARK: - Commit Message Generation

    /// Generates a structured commit message from the current changes.
    /// - Parameter allFiles: When `true`, uses all changed files (for Stage All & Commit).
    ///   When `false` (default), uses staged files if any are staged, otherwise all changed files.
    func generateCommitMessage(allFiles: Bool = false) -> String {
        let files: [ChangedFile]
        if allFiles {
            files = changedFiles
        } else {
            files = stagedFiles.isEmpty ? changedFiles : stagedFiles
        }
        guard !files.isEmpty else { return "" }

        let added = files.filter { $0.status == .added || $0.status == .untracked }
        let modified = files.filter { $0.status == .modified }
        let deleted = files.filter { $0.status == .deleted }
        let renamed = files.filter { $0.status == .renamed }

        // Build subject line
        let subject = buildSubject(added: added, modified: modified, deleted: deleted, renamed: renamed)

        // Build body with per-file stats
        var bodyLines: [String] = []
        if files.count > 1 {
            bodyLines.append("")
            for file in files {
                let stats = fileStatsLabel(file)
                bodyLines.append("- \(file.relativePath)\(stats)")
            }
        }

        return subject + bodyLines.joined(separator: "\n")
    }

    private func buildSubject(added: [ChangedFile], modified: [ChangedFile], deleted: [ChangedFile], renamed: [ChangedFile]) -> String {
        var parts: [String] = []

        if !added.isEmpty {
            let names = added.prefix(3).map(\.fileName)
            let label = names.joined(separator: ", ")
            parts.append("Add \(label)\(added.count > 3 ? " and \(added.count - 3) more" : "")")
        }
        if !modified.isEmpty {
            let names = modified.prefix(3).map(\.fileName)
            let label = names.joined(separator: ", ")
            parts.append("Update \(label)\(modified.count > 3 ? " and \(modified.count - 3) more" : "")")
        }
        if !deleted.isEmpty {
            let names = deleted.prefix(3).map(\.fileName)
            let label = names.joined(separator: ", ")
            parts.append("Remove \(label)\(deleted.count > 3 ? " and \(deleted.count - 3) more" : "")")
        }
        if !renamed.isEmpty {
            let names = renamed.prefix(2).map(\.fileName)
            let label = names.joined(separator: ", ")
            parts.append("Rename \(label)\(renamed.count > 2 ? " and \(renamed.count - 2) more" : "")")
        }

        if parts.isEmpty { return "Update files" }
        return parts.joined(separator: "; ")
    }

    private func fileStatsLabel(_ file: ChangedFile) -> String {
        guard let diff = file.diff else {
            return file.status == .untracked ? " (new)" : ""
        }
        let adds = diff.additionCount
        let dels = diff.deletionCount
        if adds > 0 && dels > 0 { return " (+\(adds)/-\(dels))" }
        if adds > 0 { return " (+\(adds))" }
        if dels > 0 { return " (-\(dels))" }
        return ""
    }

    // MARK: - Review Tracking Methods

    var reviewedCount: Int {
        changedFiles.filter { reviewedPaths.contains($0.relativePath) }.count
    }

    func isReviewed(_ file: ChangedFile) -> Bool {
        reviewedPaths.contains(file.relativePath)
    }

    func toggleReviewed(_ file: ChangedFile) {
        if reviewedPaths.contains(file.relativePath) {
            reviewedPaths.remove(file.relativePath)
            reviewedFingerprints.removeValue(forKey: file.relativePath)
        } else {
            reviewedPaths.insert(file.relativePath)
            reviewedFingerprints[file.relativePath] = diffFingerprint(file)
        }
    }

    func markAllReviewed() {
        for file in changedFiles {
            reviewedPaths.insert(file.relativePath)
            reviewedFingerprints[file.relativePath] = diffFingerprint(file)
        }
    }

    func clearAllReviewed() {
        reviewedPaths.removeAll()
        reviewedFingerprints.removeAll()
    }

    private func diffFingerprint(_ file: ChangedFile) -> String {
        if let diff = file.diff {
            // Include hunk headers for sensitivity to content changes, not just counts
            let hunkSummary = diff.hunks.map(\.header).joined(separator: "|")
            return "\(diff.additionCount):\(diff.deletionCount):\(file.staging):\(hunkSummary)"
        }
        // For files with no diff (e.g., untracked), use file size as a proxy
        let size = (try? FileManager.default.attributesOfItem(atPath: file.url.path))?[.size] as? Int ?? 0
        return "nodiff:\(file.status):\(size)"
    }

    /// Prunes review marks for files that no longer exist or whose diff changed.
    private func pruneReviewedPaths(newFiles: [ChangedFile]) {
        let currentPaths = Set(newFiles.map(\.relativePath))
        // Remove paths that are no longer in the changed list
        reviewedPaths = reviewedPaths.intersection(currentPaths)
        reviewedFingerprints = reviewedFingerprints.filter { currentPaths.contains($0.key) }
        // Clear marks where the diff changed since review
        for file in newFiles {
            if let fingerprint = reviewedFingerprints[file.relativePath],
               fingerprint != diffFingerprint(file) {
                reviewedPaths.remove(file.relativePath)
                reviewedFingerprints.removeValue(forKey: file.relativePath)
            }
        }
    }

    func start(rootURL: URL) {
        self.rootDirectory = rootURL
        fileWatcher?.stop()
        fileWatcher = FileWatcher(directory: rootURL) { [weak self] in
            self?.refresh()
            self?.refreshCommits()
            self?.refreshStashes()
        }
        refresh()
        refreshCommits()
        refreshStashes()
    }

    func stop() {
        fileWatcher?.stop()
        fileWatcher = nil
        rootDirectory = nil
        // Advance generations so any in-flight refresh is discarded
        refreshGeneration &+= 1
        commitGeneration &+= 1
        stashGeneration &+= 1
        changedFiles = []
        recentCommits = []
        stashes = []
        isLoading = false
        isLoadingCommits = false
        isLoadingStashes = false
        commitMessage = ""
        isCommitting = false
        lastCommitError = nil
        isDiscardingAll = false
        lastDiscardStashRef = nil
        isUndoingCommit = false
        lastUndoneCommitSHA = nil
        lastHunkError = nil
        lastStashError = nil
        reviewedPaths = []
        reviewedFingerprints = [:]
    }

    func refresh() {
        guard let rootURL = rootDirectory else { return }
        isLoading = true
        refreshGeneration &+= 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let detailed = GitStatusProvider.detailedStatus(for: rootURL)
            let gitRoot = detailed?.gitRoot ?? rootURL
            let statuses = detailed?.files ?? [:]
            let diffs = DiffProvider.allChanges(in: rootURL)

            // Build a lookup from relative path → FileDiff
            var diffMap: [String: FileDiff] = [:]
            for diff in diffs {
                diffMap[diff.newPath] = diff
            }

            let gitRootPath = gitRoot.standardizedFileURL.path
            var files: [ChangedFile] = []
            for (absPath, detail) in statuses {
                let url = URL(fileURLWithPath: absPath)
                // Skip directories
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: absPath, isDirectory: &isDir), isDir.boolValue {
                    continue
                }

                let relativePath: String
                if absPath.hasPrefix(gitRootPath) {
                    var rel = String(absPath.dropFirst(gitRootPath.count))
                    if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
                    relativePath = rel
                } else {
                    relativePath = url.lastPathComponent
                }

                let fileDiff: FileDiff?
                if let mapped = diffMap[relativePath] {
                    fileDiff = mapped
                } else if detail.status == .untracked {
                    fileDiff = DiffProvider.newFileDiff(for: url, relativePath: relativePath)
                } else {
                    fileDiff = nil
                }

                files.append(ChangedFile(
                    url: url,
                    relativePath: relativePath,
                    status: detail.status,
                    staging: detail.staging,
                    diff: fileDiff
                ))
            }

            files.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }

            DispatchQueue.main.async {
                guard let self = self, self.refreshGeneration == generation else { return }
                self.pruneReviewedPaths(newFiles: files)
                self.changedFiles = files
                self.isLoading = false
            }
        }
    }

    func refreshCommits() {
        guard let rootURL = rootDirectory else { return }
        isLoadingCommits = true
        commitGeneration &+= 1
        let generation = commitGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let commits = GitLogProvider.recentCommits(in: rootURL, count: 50)
            DispatchQueue.main.async {
                guard let self = self, self.commitGeneration == generation else { return }
                self.recentCommits = commits
                self.isLoadingCommits = false
            }
        }
    }

    /// Load the file list for a commit (lazy-loaded on expand).
    func loadCommitFiles(for sha: String) {
        guard let rootURL = rootDirectory else { return }
        guard let index = recentCommits.firstIndex(where: { $0.sha == sha }),
              recentCommits[index].files == nil else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = GitLogProvider.commitFiles(sha: sha, in: rootURL)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.recentCommits.firstIndex(where: { $0.sha == sha }) else { return }
                self.recentCommits[idx].files = files
            }
        }
    }

    /// Discard all uncommitted changes to a file.
    /// Handles different git statuses appropriately.
    func discardChanges(for file: ChangedFile) {
        guard let rootURL = rootDirectory else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            switch file.status {
            case .untracked:
                // Remove untracked file from disk
                Self.runGitSync(args: ["clean", "-f", "--", file.relativePath], at: rootURL)
            case .added:
                // Unstage and remove a newly added file
                Self.runGitSync(args: ["rm", "-f", "--", file.relativePath], at: rootURL)
            default:
                // For modified, deleted, renamed, conflicted: restore from HEAD
                Self.runGitSync(args: ["checkout", "HEAD", "--", file.relativePath], at: rootURL)
            }
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    // MARK: - Staging

    /// Stage a file (add to the git index).
    func stageFile(_ file: ChangedFile) {
        guard let rootURL = rootDirectory else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.runGitSync(args: ["add", "--", file.relativePath], at: rootURL)
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    /// Unstage a file (remove from the git index but keep changes).
    func unstageFile(_ file: ChangedFile) {
        guard let rootURL = rootDirectory else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if file.status == .untracked || file.status == .added {
                Self.runGitSync(args: ["reset", "HEAD", "--", file.relativePath], at: rootURL)
            } else {
                Self.runGitSync(args: ["restore", "--staged", "--", file.relativePath], at: rootURL)
            }
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    /// Stage all changed files.
    func stageAll(completion: (() -> Void)? = nil) {
        guard let rootURL = rootDirectory else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.runGitSync(args: ["add", "-A"], at: rootURL)
            DispatchQueue.main.async {
                self?.refresh()
                completion?()
            }
        }
    }

    /// Unstage all staged files.
    func unstageAll() {
        guard let rootURL = rootDirectory else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.runGitSync(args: ["reset", "HEAD"], at: rootURL)
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    // MARK: - Hunk-level Staging

    /// Stage a single hunk by applying a patch to the index.
    func stageHunk(patch: String) {
        guard let rootURL = rootDirectory else { return }
        lastHunkError = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = Self.runGitApply(patch: patch, args: ["apply", "--cached"], at: rootURL)
            DispatchQueue.main.async {
                if !success { self?.lastHunkError = error ?? "Failed to stage hunk" }
                self?.refresh()
            }
        }
    }

    /// Unstage a single hunk by reverse-applying the patch from the index.
    func unstageHunk(patch: String) {
        guard let rootURL = rootDirectory else { return }
        lastHunkError = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = Self.runGitApply(patch: patch, args: ["apply", "--cached", "--reverse"], at: rootURL)
            DispatchQueue.main.async {
                if !success { self?.lastHunkError = error ?? "Failed to unstage hunk" }
                self?.refresh()
            }
        }
    }

    /// Discard a single hunk by reverse-applying the patch to the working tree.
    func discardHunk(patch: String) {
        guard let rootURL = rootDirectory else { return }
        lastHunkError = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = Self.runGitApply(patch: patch, args: ["apply", "--reverse"], at: rootURL)
            DispatchQueue.main.async {
                if !success { self?.lastHunkError = error ?? "Failed to discard hunk" }
                self?.refresh()
            }
        }
    }

    /// Commit staged changes with the current commit message.
    func commit() {
        guard let rootURL = rootDirectory else { return }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !stagedFiles.isEmpty else { return }

        isCommitting = true
        lastCommitError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = Self.runGitCommit(message: message, at: rootURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isCommitting = false
                if success {
                    self.commitMessage = ""
                    self.lastCommitError = nil
                } else {
                    self.lastCommitError = error ?? "Commit failed"
                }
                self.refresh()
                self.refreshCommits()
            }
        }
    }

    /// Stage all files and commit atomically, without relying on intermediate
    /// UI state refresh between the two git operations.
    func stageAllAndCommit() {
        guard let rootURL = rootDirectory else { return }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !changedFiles.isEmpty else { return }

        isCommitting = true
        lastCommitError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.runGitSync(args: ["add", "-A"], at: rootURL)
            let (success, error) = Self.runGitCommit(message: message, at: rootURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isCommitting = false
                if success {
                    self.commitMessage = ""
                    self.lastCommitError = nil
                } else {
                    self.lastCommitError = error ?? "Commit failed"
                }
                self.refresh()
                self.refreshCommits()
            }
        }
    }

    /// Discard all uncommitted changes. Stashes first so the user can recover.
    func discardAll() {
        guard let rootURL = rootDirectory, !changedFiles.isEmpty else { return }
        isDiscardingAll = true
        lastDiscardStashRef = nil
        refreshGeneration &+= 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Count stashes before push to verify a new one was created
            let countBefore = Self.runGitOutput(args: ["stash", "list"], at: rootURL)?
                .components(separatedBy: "\n").filter { !$0.isEmpty }.count ?? 0

            // Stash everything (including untracked) for recovery
            _ = Self.runGitOutput(args: ["stash", "push", "--include-untracked", "-m", "Anvil: discard all changes"], at: rootURL)

            let countAfter = Self.runGitOutput(args: ["stash", "list"], at: rootURL)?
                .components(separatedBy: "\n").filter { !$0.isEmpty }.count ?? 0

            // Resolve stash@{0} to an immutable SHA so index drift doesn't matter
            let stashRef: String?
            if countAfter > countBefore {
                stashRef = Self.runGitOutput(args: ["rev-parse", "stash@{0}"], at: rootURL)
            } else {
                stashRef = nil
            }

            DispatchQueue.main.async {
                guard let self = self, self.refreshGeneration == generation else { return }
                self.lastDiscardStashRef = stashRef
                self.isDiscardingAll = false
                self.refresh()
            }
        }
    }

    /// Recover changes from the last discard-all stash.
    func recoverDiscarded() {
        guard let rootURL = rootDirectory, let sha = lastDiscardStashRef else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = Self.runGitWithStatus(args: ["stash", "apply", sha], at: rootURL)
            if success {
                // Drop the stash entry only after successful apply
                Self.runGitSync(args: ["stash", "drop", sha], at: rootURL)
            }
            DispatchQueue.main.async {
                guard let self = self, self.refreshGeneration == generation else { return }
                if success {
                    self.lastDiscardStashRef = nil
                }
                // Always refresh to reflect current state
                self.refresh()
            }
        }
    }

    // MARK: - Undo Commit

    /// Whether the most recent commit can be undone (soft reset).
    /// Returns false if there's only one commit (no parent), or an undo is already in progress.
    var canUndoCommit: Bool {
        guard !recentCommits.isEmpty && !isUndoingCommit else { return false }
        // Need at least 2 commits so HEAD~1 exists
        return recentCommits.count >= 2
    }

    /// Undo the most recent commit via `git reset --soft HEAD~1`.
    /// Changes from the undone commit become staged, preserving all work.
    func undoLastCommit() {
        guard let rootURL = rootDirectory, let commit = recentCommits.first else { return }
        isUndoingCommit = true
        lastUndoneCommitSHA = nil
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let sha = commit.shortSHA

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Verify HEAD~1 exists before attempting reset
            let parentExists = Self.runGitWithStatus(args: ["rev-parse", "--verify", "HEAD~1"], at: rootURL)
            let success: Bool
            if parentExists {
                success = Self.runGitWithStatus(args: ["reset", "--soft", "HEAD~1"], at: rootURL)
            } else {
                success = false
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Always clear the loading flag regardless of generation
                self.isUndoingCommit = false
                guard self.refreshGeneration == generation else { return }
                if success {
                    self.lastUndoneCommitSHA = sha
                } else {
                    self.lastCommitError = "Failed to undo commit"
                }
                self.refresh()
                self.refreshCommits()
            }
        }
    }

    // MARK: - Stash Management

    func refreshStashes() {
        guard let rootURL = rootDirectory else { return }
        isLoadingStashes = true
        stashGeneration &+= 1
        let generation = stashGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = GitStashProvider.list(in: rootURL)
            DispatchQueue.main.async {
                guard let self = self, self.stashGeneration == generation else { return }
                self.stashes = entries
                self.isLoadingStashes = false
            }
        }
    }

    /// Load the file list for a stash entry (lazy-loaded on expand).
    func loadStashFiles(for sha: String) {
        guard let rootURL = rootDirectory else { return }
        guard let index = stashes.firstIndex(where: { $0.sha == sha }),
              stashes[index].files == nil else { return }
        let stashIndex = stashes[index].index

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = GitStashProvider.stashFiles(index: stashIndex, in: rootURL)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.stashes.firstIndex(where: { $0.sha == sha }) else { return }
                self.stashes[idx].files = files
            }
        }
    }

    /// Apply a stash without removing it.
    func applyStash(sha: String) {
        guard let rootURL = rootDirectory else { return }
        lastStashError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = GitStashProvider.apply(sha: sha, in: rootURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !success {
                    self.lastStashError = error ?? "Failed to apply stash"
                }
                self.refresh()
            }
        }
    }

    /// Pop a stash (apply and remove). Uses SHA to prevent index drift.
    func popStash(sha: String) {
        guard let rootURL = rootDirectory else { return }
        lastStashError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = GitStashProvider.pop(sha: sha, in: rootURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !success {
                    self.lastStashError = error ?? "Failed to pop stash"
                }
                self.refresh()
                self.refreshStashes()
            }
        }
    }

    /// Drop a stash without applying it. Uses SHA to prevent index drift.
    func dropStash(sha: String) {
        guard let rootURL = rootDirectory else { return }
        lastStashError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = GitStashProvider.drop(sha: sha, in: rootURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !success {
                    self.lastStashError = error ?? "Failed to drop stash"
                }
                self.refreshStashes()
            }
        }
    }

    private static func runGitOutput(args: [String], at directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runGitWithStatus(args: [String], at directory: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func runGitSync(args: [String], at directory: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// Applies a patch via stdin to `git apply` with the given arguments.
    private static func runGitApply(patch: String, args: [String], at directory: URL) -> (success: Bool, error: String?) {
        let process = Process()
        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
            if let data = patch.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }

        if process.terminationStatus == 0 {
            return (true, nil)
        }
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, msg)
    }

    private static func runGitCommit(message: String, at directory: URL) -> (success: Bool, error: String?) {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["commit", "-m", message]
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }

        if process.terminationStatus == 0 {
            return (true, nil)
        }
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, msg)
    }

    #if DEBUG
    /// Test helper to set changed files directly.
    func setChangedFilesForTesting(_ files: [ChangedFile]) {
        changedFiles = files
    }
    #endif
}
