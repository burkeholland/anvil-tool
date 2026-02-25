import Foundation
import Combine

/// A single changed file entry for the changes list.
struct ChangedFile: Identifiable {
    let url: URL
    let relativePath: String
    let status: GitFileStatus
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
    }

    func refresh() {
        guard let rootURL = rootDirectory else { return }
        isLoading = true
        refreshGeneration &+= 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let gitRoot = Self.findGitRoot(for: rootURL)
            let statuses = GitStatusProvider.status(for: rootURL)
            let diffs = DiffProvider.allChanges(in: rootURL)

            // Build a lookup from relative path → FileDiff
            var diffMap: [String: FileDiff] = [:]
            for diff in diffs {
                diffMap[diff.newPath] = diff
            }

            // Filter to file-level statuses (not directories), build ChangedFile list
            let gitRootPath = (gitRoot ?? rootURL).standardizedFileURL.path
            var files: [ChangedFile] = []
            for (absPath, status) in statuses {
                let url = URL(fileURLWithPath: absPath)
                // Skip directories — they have propagated statuses
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: absPath, isDirectory: &isDir), isDir.boolValue {
                    continue
                }
                // Also skip deleted files that no longer exist on disk
                if status == .deleted && !FileManager.default.fileExists(atPath: absPath) {
                    // Still include them — they're valid changes
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
                    status: status,
                    diff: diffMap[relativePath]
                ))
            }

            // Sort: directories first (by path), then alphabetically
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

    private static func findGitRoot(for directory: URL) -> URL? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--show-toplevel"]
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
