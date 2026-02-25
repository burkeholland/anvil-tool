import Foundation

/// A local git branch with metadata.
struct GitBranch: Identifiable {
    let name: String
    let isCurrent: Bool
    let lastCommitDate: Date?
    let lastCommitMessage: String?

    var id: String { name }
}

/// Fetches branch information and performs branch operations via git CLI.
enum GitBranchProvider {

    /// List all local branches with their latest commit info.
    static func branches(in directory: URL) -> [GitBranch] {
        // format: refname:short | HEAD indicator | relative date | subject
        let format = "%(refname:short)\t%(HEAD)\t%(creatordate:relative)\t%(contents:subject)"
        guard let output = runGit(
            args: ["branch", "--format=\(format)", "--sort=-committerdate"],
            at: directory
        ) else {
            return []
        }

        var result: [GitBranch] = []
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            let name = parts[0]
            let isCurrent = parts[1] == "*"
            let message = parts.count > 3 ? parts[3] : nil

            result.append(GitBranch(
                name: name,
                isCurrent: isCurrent,
                lastCommitDate: nil,
                lastCommitMessage: message
            ))
        }

        // Ensure current branch is first regardless of sort
        if let currentIdx = result.firstIndex(where: { $0.isCurrent }), currentIdx != 0 {
            let current = result.remove(at: currentIdx)
            result.insert(current, at: 0)
        }

        return result
    }

    /// Switch to an existing branch. Returns (success, errorMessage).
    static func switchBranch(to name: String, in directory: URL) -> (success: Bool, error: String?) {
        let (exitCode, _, stderr) = runGitFull(args: ["checkout", name], at: directory)
        if exitCode == 0 { return (true, nil) }
        return (false, stderr)
    }

    /// Create a new branch from current HEAD and switch to it.
    static func createBranch(named name: String, in directory: URL) -> (success: Bool, error: String?) {
        let (exitCode, _, stderr) = runGitFull(args: ["checkout", "-b", name], at: directory)
        if exitCode == 0 { return (true, nil) }
        return (false, stderr)
    }

    /// Delete a local branch (non-force). Fails if branch is not fully merged.
    static func deleteBranch(named name: String, in directory: URL) -> (success: Bool, error: String?) {
        let (exitCode, _, stderr) = runGitFull(args: ["branch", "-d", name], at: directory)
        if exitCode == 0 { return (true, nil) }
        return (false, stderr)
    }

    /// Check whether the working tree has uncommitted changes.
    static func hasUncommittedChanges(in directory: URL) -> Bool {
        guard let output = runGit(args: ["status", "--porcelain"], at: directory) else { return false }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Private

    private static func runGit(args: [String], at directory: URL) -> String? {
        let (exitCode, stdout, _) = runGitFull(args: args, at: directory)
        guard exitCode == 0 else { return nil }
        return stdout
    }

    private static func runGitFull(args: [String], at directory: URL) -> (exitCode: Int32, stdout: String?, stderr: String?) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return (-1, nil, error.localizedDescription)
        }

        // Read pipe data before waitUntilExit to avoid deadlock when
        // git output fills the pipe buffer.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, stdout, stderr)
    }
}
