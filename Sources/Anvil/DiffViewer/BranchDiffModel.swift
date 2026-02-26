import Foundation
import Combine

/// A file changed between the branch merge-base and HEAD.
struct BranchDiffFile: Identifiable {
    let path: String
    let additions: Int
    let deletions: Int
    let status: String // "M", "A", "D", "R"
    var diff: FileDiff?

    var id: String { path }

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var directoryPath: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    var statusColor: String {
        switch status {
        case "A": return "green"
        case "D": return "red"
        case "R": return "blue"
        default:  return "orange"
        }
    }
}

/// Manages the state for viewing the total branch diff (PR preview).
/// Computes the merge-base between the current branch and the default branch,
/// then loads all changed files with their diffs.
final class BranchDiffModel: ObservableObject {
    @Published private(set) var files: [BranchDiffFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var baseBranch: String?
    @Published private(set) var mergeBaseSHA: String?
    @Published private(set) var currentBranch: String?
    @Published private(set) var commitCount: Int = 0
    @Published private(set) var errorMessage: String?

    var totalAdditions: Int { files.reduce(0) { $0 + $1.additions } }
    var totalDeletions: Int { files.reduce(0) { $0 + $1.deletions } }

    private var rootURL: URL?
    private var loadGeneration: UInt64 = 0
    private let workQueue = DispatchQueue(label: "dev.anvil.branch-diff", qos: .userInitiated)

    func load(rootURL: URL) {
        self.rootURL = rootURL
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        files = []

        workQueue.async { [weak self] in
            guard let self = self else { return }

            // Detect current branch
            let branch = self.runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"], at: rootURL)

            // Detect default branch
            guard let defaultBranch = DiffProvider.defaultBranch(in: rootURL) else {
                DispatchQueue.main.async {
                    guard self.loadGeneration == generation else { return }
                    self.isLoading = false
                    self.currentBranch = branch
                    self.errorMessage = "No default branch (main/master) found"
                }
                return
            }

            // Check if we're ON the default branch
            if branch == defaultBranch {
                DispatchQueue.main.async {
                    guard self.loadGeneration == generation else { return }
                    self.isLoading = false
                    self.currentBranch = branch
                    self.baseBranch = defaultBranch
                    self.errorMessage = "Already on \(defaultBranch) — switch to a feature branch to see the diff"
                }
                return
            }

            // Compute merge-base
            guard let mergeBase = DiffProvider.mergeBase(defaultBranch, in: rootURL) else {
                DispatchQueue.main.async {
                    guard self.loadGeneration == generation else { return }
                    self.isLoading = false
                    self.currentBranch = branch
                    self.baseBranch = defaultBranch
                    self.errorMessage = "Could not compute merge base with \(defaultBranch)"
                }
                return
            }

            // Count commits on the branch
            let commitCountStr = self.runGit(
                args: ["rev-list", "--count", "\(mergeBase)..HEAD"],
                at: rootURL
            )
            let commits = Int(commitCountStr ?? "0") ?? 0

            // Get changed files with stats
            var changedFiles = DiffProvider.branchChangedFiles(baseSHA: mergeBase, in: rootURL)

            // Load diffs for each file
            let diffs = DiffProvider.branchDiff(baseSHA: mergeBase, in: rootURL)
            let diffMap = Dictionary(uniqueKeysWithValues: diffs.map { ($0.id, $0) })
            for i in 0..<changedFiles.count {
                changedFiles[i].diff = diffMap[changedFiles[i].path]
            }

            DispatchQueue.main.async {
                guard self.loadGeneration == generation else { return }
                self.isLoading = false
                self.currentBranch = branch
                self.baseBranch = defaultBranch
                self.mergeBaseSHA = String(mergeBase.prefix(8))
                self.commitCount = commits
                self.files = changedFiles
            }
        }
    }

    private func runGit(args: [String], at directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
