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

    private var rootURL: URL?

    // MARK: - Public API

    /// Load conflict blocks from `url` inside `root`.
    func load(fileURL: URL, rootURL: URL) {
        self.rootURL = rootURL
        self.fileURL = fileURL
        self.isStaged = false
        self.errorMessage = nil
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
            }
        }
    }

    // MARK: - Private helpers

    private func resolve(id: UUID, as resolution: ConflictResolution) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].resolution = resolution
        updateAllResolved()
        if allResolved {
            writeAndStage()
        }
    }

    private func updateAllResolved() {
        allResolved = !blocks.isEmpty && blocks.allSatisfy { $0.resolution != .unresolved }
    }
}
