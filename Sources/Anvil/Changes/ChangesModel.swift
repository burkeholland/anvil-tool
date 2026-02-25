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

    @Published var commitMessage: String = ""
    @Published private(set) var isCommitting = false
    @Published private(set) var lastCommitError: String?
    @Published private(set) var isDiscardingAll = false
    /// The stash reference after a "Discard All" so the user can recover.
    @Published var lastDiscardStashRef: String?

    private(set) var rootDirectory: URL?
    private var refreshGeneration: UInt64 = 0
    private var commitGeneration: UInt64 = 0
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

    func start(rootURL: URL) {
        self.rootDirectory = rootURL
        fileWatcher?.stop()
        fileWatcher = FileWatcher(directory: rootURL) { [weak self] in
            self?.refresh()
            self?.refreshCommits()
        }
        refresh()
        refreshCommits()
    }

    func stop() {
        fileWatcher?.stop()
        fileWatcher = nil
        rootDirectory = nil
        // Advance generations so any in-flight refresh is discarded
        refreshGeneration &+= 1
        commitGeneration &+= 1
        changedFiles = []
        recentCommits = []
        isLoading = false
        isLoadingCommits = false
        commitMessage = ""
        isCommitting = false
        lastCommitError = nil
        isDiscardingAll = false
        lastDiscardStashRef = nil
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

                files.append(ChangedFile(
                    url: url,
                    relativePath: relativePath,
                    status: detail.status,
                    staging: detail.staging,
                    diff: diffMap[relativePath]
                ))
            }

            files.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }

            DispatchQueue.main.async {
                guard let self = self, self.refreshGeneration == generation else { return }
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
}
