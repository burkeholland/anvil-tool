import Foundation

/// Static helpers for querying and interacting with git remotes.
enum GitRemoteProvider {

    /// Returns the ahead/behind counts relative to the upstream tracking branch.
    /// Returns nil if there is no upstream configured.
    static func aheadBehind(in directory: URL) -> (ahead: Int, behind: Int)? {
        // rev-list --count --left-right @{u}...HEAD
        // Output: "<behind>\t<ahead>"
        let (exitCode, stdout, _) = runGitFull(
            args: ["rev-list", "--count", "--left-right", "@{u}...HEAD"],
            at: directory
        )
        guard exitCode == 0, let output = stdout else { return nil }
        let parts = output.components(separatedBy: "\t")
        guard parts.count == 2,
              let behind = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let ahead = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return (ahead: ahead, behind: behind)
    }

    /// Returns the name of the upstream tracking branch (e.g. "origin/main"), or nil.
    static func upstream(in directory: URL) -> String? {
        let (exitCode, stdout, _) = runGitFull(
            args: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
            at: directory
        )
        guard exitCode == 0, let name = stdout, !name.isEmpty else { return nil }
        return name
    }

    /// Push the current branch to its upstream. Returns (success, errorMessage).
    static func push(in directory: URL) -> (success: Bool, error: String?) {
        let (exitCode, _, stderr) = runGitFull(args: ["push"], at: directory)
        if exitCode == 0 { return (true, nil) }
        return (false, stderr)
    }

    /// Push the current branch and set upstream. Returns (success, errorMessage).
    static func pushSetUpstream(branch: String, in directory: URL) -> (success: Bool, error: String?) {
        let remote = defaultRemote(in: directory) ?? "origin"
        let (exitCode, _, stderr) = runGitFull(
            args: ["push", "--set-upstream", remote, branch],
            at: directory
        )
        if exitCode == 0 { return (true, nil) }
        return (false, stderr)
    }

    /// Pull from the upstream tracking branch. Returns (success, errorMessage).
    static func pull(in directory: URL) -> (success: Bool, error: String?) {
        let (exitCode, _, stderr) = runGitFull(args: ["pull"], at: directory)
        if exitCode == 0 { return (true, nil) }
        return (false, stderr)
    }

    /// Fetch from all remotes (updates tracking refs without modifying working tree).
    static func fetch(in directory: URL) -> Bool {
        let (exitCode, _, _) = runGitFull(args: ["fetch", "--all", "--prune"], at: directory)
        return exitCode == 0
    }

    /// Check whether any remotes are configured.
    static func hasRemotes(in directory: URL) -> Bool {
        let (exitCode, stdout, _) = runGitFull(args: ["remote"], at: directory)
        guard exitCode == 0, let output = stdout else { return false }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Returns the first configured remote name (prefers "origin").
    static func defaultRemote(in directory: URL) -> String? {
        let (exitCode, stdout, _) = runGitFull(args: ["remote"], at: directory)
        guard exitCode == 0, let output = stdout else { return nil }
        let remotes = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        if remotes.contains("origin") { return "origin" }
        return remotes.first
    }

    // MARK: - Private

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

        // Read both pipes concurrently to avoid deadlock when one pipe fills
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.wait()
        process.waitUntilExit()

        let stdout = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, stdout, stderr)
    }
}
