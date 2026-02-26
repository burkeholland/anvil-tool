import Foundation
import Combine

/// A file changed within a single commit, augmented with its parsed diff.
struct CommitDiffFile: Identifiable {
    let path: String
    let additions: Int
    let deletions: Int
    let status: String
    var diff: FileDiff?

    var id: String { path }

    init(commitFile: CommitFile) {
        self.path = commitFile.path
        self.additions = commitFile.additions
        self.deletions = commitFile.deletions
        self.status = commitFile.status
    }

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var directoryPath: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }
}

/// Manages loading the full diff for a single git commit (all files changed in that commit).
final class CommitDiffModel: ObservableObject {
    @Published private(set) var commit: GitCommit?
    @Published private(set) var files: [CommitDiffFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    var totalAdditions: Int { files.reduce(0) { $0 + $1.additions } }
    var totalDeletions: Int { files.reduce(0) { $0 + $1.deletions } }

    private var loadGeneration: UInt64 = 0
    private let workQueue = DispatchQueue(label: "dev.anvil.commit-diff", qos: .userInitiated)

    /// Load the full diff for the given commit.
    func load(commit: GitCommit, rootURL: URL) {
        self.commit = commit
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        files = []

        workQueue.async { [weak self] in
            guard let self else { return }
            let commitFiles = GitLogProvider.commitFiles(sha: commit.sha, in: rootURL)
            var diffFiles: [CommitDiffFile] = commitFiles.map { CommitDiffFile(commitFile: $0) }

            // Load diffs for each file concurrently
            let count = diffFiles.count
            var diffs = [FileDiff?](repeating: nil, count: count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: count) { i in
                let diff = DiffProvider.commitFileDiff(
                    sha: commit.sha, filePath: diffFiles[i].path, in: rootURL
                )
                lock.lock()
                diffs[i] = diff
                lock.unlock()
            }
            for i in 0..<count {
                diffFiles[i].diff = diffs[i]
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadGeneration == generation else { return }
                self.files = diffFiles
                self.isLoading = false
            }
        }
    }
}
