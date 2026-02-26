import Foundation
import Combine

/// Observable model that manages merge conflict resolution for a single file.
final class MergeConflictModel: ObservableObject {

    /// The file currently being resolved.
    @Published private(set) var fileURL: URL?
    /// The conflict blocks extracted from the file.
    @Published private(set) var blocks: [ConflictBlock] = []
    /// Whether all blocks have been resolved.
    @Published private(set) var allResolved = false
    /// Whether the file was successfully written and staged.
    @Published private(set) var isStaged = false
    /// Error message from the last operation.
    @Published var errorMessage: String?

    /// All files in the repo that currently have conflicts.
    @Published private(set) var allConflictURLs: [URL] = []
    /// URLs of files that have been successfully staged (resolved).
    @Published private(set) var stagedFileURLs: Set<URL> = []

    private var rootURL: URL?

    // MARK: - Computed progress

    /// Number of conflicted files that have been staged.
    var resolvedFileCount: Int { stagedFileURLs.count }

    /// Total number of conflicted files being tracked.
    var totalConflictFileCount: Int { allConflictURLs.count }

    /// Conflicted files that have NOT been staged yet.
    var remainingConflictURLs: [URL] {
        allConflictURLs.filter { !stagedFileURLs.contains($0) }
    }

    // MARK: - Public API

    /// Load conflict blocks from `url` inside `root`.
    /// `allConflictURLs` lists every file in the repo that still has conflict markers.
    func load(fileURL: URL, rootURL: URL, allConflictURLs: [URL] = []) {
        self.rootURL = rootURL
        self.fileURL = fileURL
        self.isStaged = false
        self.errorMessage = nil
        self.allConflictURLs = allConflictURLs.isEmpty ? self.allConflictURLs : allConflictURLs
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            blocks = []
            return
        }
        blocks = MergeConflictParser.parse(content: content)
        updateAllResolved()
    }

    /// Dismiss / reset the model.
    func close() {
        fileURL = nil
        blocks = []
        allResolved = false
        isStaged = false
        errorMessage = nil
        rootURL = nil
        allConflictURLs = []
        stagedFileURLs = []
    }

    // MARK: - Resolution actions

    func acceptCurrent(id: UUID) {
        resolve(id: id, as: .acceptCurrent)
    }

    func acceptIncoming(id: UUID) {
        resolve(id: id, as: .acceptIncoming)
    }

    func acceptBoth(id: UUID) {
        resolve(id: id, as: .acceptBoth)
    }

    func unresolve(id: UUID) {
        resolve(id: id, as: .unresolved)
    }

    // MARK: - Write & stage

    /// Write the resolved content to disk and stage the file with `git add`.
    /// Called automatically when all conflicts are resolved, or manually by the user.
    func writeAndStage() {
        guard let fileURL, let rootURL else { return }
        guard let originalContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            errorMessage = "Could not read file."
            return
        }
        let resolved = MergeConflictParser.applyResolutions(to: originalContent, blocks: blocks)
        do {
            try resolved.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Could not write file: \(error.localizedDescription)"
            return
        }

        // git add <relativePath>
        let relativePath = fileURL.path.replacingOccurrences(
            of: rootURL.standardizedFileURL.path + "/", with: ""
        )
        let stagedURL = fileURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["add", "--", relativePath]
            process.currentDirectoryURL = rootURL
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            DispatchQueue.main.async {
                self?.isStaged = true
                self?.stagedFileURLs.insert(stagedURL)
            }
        }
    }

    // MARK: - Private helpers

    private func resolve(id: UUID, as resolution: ConflictResolution) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].resolution = resolution
        updateAllResolved()
    }

    private func updateAllResolved() {
        allResolved = !blocks.isEmpty && blocks.allSatisfy { $0.resolution != .unresolved }
    }
}
