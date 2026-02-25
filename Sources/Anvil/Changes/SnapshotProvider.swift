import Foundation

/// Creates and restores lightweight pre-task git snapshots.
///
/// Snapshots use `git stash create --include-untracked` to capture the working
/// tree state without modifying it. The returned SHA is stored in memory and
/// used to restore the tree on rollback.
enum SnapshotProvider {

    // MARK: - Snapshot creation

    /// Captures the current working tree state and returns an `AnvilSnapshot`.
    /// Returns `nil` if the HEAD SHA cannot be determined (not a git repo).
    static func create(in directory: URL, label: String = "Pre-task snapshot") -> AnvilSnapshot? {
        guard let headSHA = runGit(args: ["rev-parse", "HEAD"], at: directory) else { return nil }

        // git stash create returns a stash object SHA, or empty string if tree is clean.
        let stashOutput = runGit(args: ["stash", "create", "--include-untracked"], at: directory)
        let stashSHA = stashOutput?.isEmpty == false ? stashOutput : nil

        return AnvilSnapshot(id: UUID(), date: Date(), label: label, headSHA: headSHA, stashSHA: stashSHA)
    }

    // MARK: - Rollback

    /// Restores the working tree to the state captured in `snapshot`.
    ///
    /// Steps:
    ///  1. `git reset --hard <headSHA>` — move HEAD and index back to the snapshot commit.
    ///  2. `git clean -fd` — remove untracked files added after the snapshot.
    ///  3. If the snapshot captured pre-existing working-tree changes (stashSHA ≠ nil),
    ///     re-apply them via a temporary stash entry and immediately drop it.
    @discardableResult
    static func restore(_ snapshot: AnvilSnapshot, in directory: URL) -> (success: Bool, error: String?) {
        // Step 1: reset HEAD
        let reset = runGitWithError(args: ["reset", "--hard", snapshot.headSHA], at: directory)
        guard reset.success else { return reset }

        // Step 2: remove untracked files the agent added
        runGit(args: ["clean", "-fd"], at: directory)

        // Step 3: re-apply pre-existing working tree changes (if any)
        if let stashSHA = snapshot.stashSHA {
            let store = runGitWithError(
                args: ["stash", "store", "-m", "anvil-rollback-restore", stashSHA],
                at: directory
            )
            if store.success {
                let apply = runGitWithError(args: ["stash", "apply", "stash@{0}"], at: directory)
                runGit(args: ["stash", "drop", "stash@{0}"], at: directory)
                if !apply.success {
                    return (false, apply.error ?? "Failed to apply pre-task working tree changes.")
                }
            }
        }

        return (true, nil)
    }

    // MARK: - Private helpers

    @discardableResult
    private static func runGit(args: [String], at directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
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
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runGitWithError(args: [String], at directory: URL) -> (success: Bool, error: String?) {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
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
