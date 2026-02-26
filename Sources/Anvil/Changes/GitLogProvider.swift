import Foundation

/// Fetches git commit history and per-commit file stats.
enum GitLogProvider {

    /// Fetch the most recent commits from git log.
    static func recentCommits(in directory: URL, count: Int = 50) -> [GitCommit] {
        // Use NUL-separated format fields for reliable parsing
        let format = "%H%n%h%n%s%n%an%n%aI"
        guard let output = runGit(
            args: ["log", "-\(count)", "--pretty=format:\(format)", "--no-merges"],
            at: directory
        ), !output.isEmpty else {
            return []
        }

        let lines = output.components(separatedBy: "\n")
        var commits: [GitCommit] = []
        var i = 0

        while i + 4 < lines.count {
            let sha = lines[i]
            let shortSHA = lines[i + 1]
            let message = lines[i + 2]
            let author = lines[i + 3]
            let dateStr = lines[i + 4]
            i += 5

            let date = ISO8601DateFormatter().date(from: dateStr) ?? Date()
            commits.append(GitCommit(
                sha: sha, shortSHA: shortSHA, message: message,
                author: author, date: date, files: nil
            ))
        }

        return commits
    }

    /// Fetch the files changed in a specific commit with addition/deletion stats.
    static func commitFiles(sha: String, in directory: URL) -> [CommitFile] {
        guard let output = runGit(
            args: ["diff-tree", "--no-commit-id", "-r", "--numstat", "--diff-filter=AMDRT", sha],
            at: directory
        ), !output.isEmpty else {
            return []
        }

        // Also get the status letter for each file
        let statusOutput = runGit(
            args: ["diff-tree", "--no-commit-id", "-r", "--name-status", "--diff-filter=AMDRT", sha],
            at: directory
        ) ?? ""

        // Parse numstat: "additions\tdeletions\tpath"
        var statsMap: [String: (Int, Int)] = [:]
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3 else { continue }
            let adds = Int(parts[0]) ?? 0
            let dels = Int(parts[1]) ?? 0
            let path = String(parts[2])
            statsMap[path] = (adds, dels)
        }

        // Parse name-status: "M\tpath" or "R100\told\tnew"
        var files: [CommitFile] = []
        for line in statusOutput.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count >= 2 else { continue }
            let statusRaw = String(parts[0])
            let status = String(statusRaw.prefix(1)) // Normalize R100 → R
            let path: String
            if status == "R" && parts.count >= 3 {
                path = String(parts[2]) // Use new path for renames
            } else {
                path = String(parts[1])
            }

            let (adds, dels) = statsMap[path] ?? (0, 0)
            files.append(CommitFile(
                path: path, additions: adds, deletions: dels, status: status
            ))
        }

        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Fetch a page of commits from the log with optional author and date filters.
    /// - Parameters:
    ///   - directory: The git repository root.
    ///   - skip: Number of commits to skip (for pagination).
    ///   - count: Maximum number of commits to return.
    ///   - author: If provided, only commits whose author name contains this string.
    ///   - since: If provided, only commits after this date.
    ///   - until: If provided, only commits before or on this date.
    static func pagedCommits(
        in directory: URL,
        skip: Int = 0,
        count: Int = 30,
        author: String? = nil,
        since: Date? = nil,
        until: Date? = nil
    ) -> [GitCommit] {
        let format = "%H%n%h%n%s%n%an%n%aI"
        var args = ["log", "-\(count)", "--skip=\(skip)", "--pretty=format:\(format)", "--no-merges"]
        if let author = author, !author.isEmpty {
            args.append("--author=\(author)")
        }
        let iso = ISO8601DateFormatter()
        if let since = since {
            args.append("--since=\(iso.string(from: since))")
        }
        if let until = until {
            // Add one day so the selected date is inclusive
            let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: until) ?? until
            args.append("--until=\(iso.string(from: nextDay))")
        }
        guard let output = runGit(args: args, at: directory), !output.isEmpty else {
            return []
        }

        let lines = output.components(separatedBy: "\n")
        var commits: [GitCommit] = []
        var i = 0
        while i + 4 < lines.count {
            let sha = lines[i]
            let shortSHA = lines[i + 1]
            let message = lines[i + 2]
            let author = lines[i + 3]
            let dateStr = lines[i + 4]
            i += 5
            let date = ISO8601DateFormatter().date(from: dateStr) ?? Date()
            commits.append(GitCommit(
                sha: sha, shortSHA: shortSHA, message: message,
                author: author, date: date, files: nil
            ))
        }
        return commits
    }

    /// Fetch commits on the current branch that are not yet in `base`.
    /// Used to populate the PR description with branch-specific commit history.
    static func branchCommits(base: String, in directory: URL) -> [GitCommit] {
        let format = "%H%n%h%n%s%n%an%n%aI"
        guard let output = runGit(
            args: ["log", "--pretty=format:\(format)", "--no-merges", "\(base)..HEAD"],
            at: directory
        ), !output.isEmpty else {
            return []
        }

        let lines = output.components(separatedBy: "\n")
        var commits: [GitCommit] = []
        var i = 0

        while i + 4 < lines.count {
            let sha = lines[i]
            let shortSHA = lines[i + 1]
            let message = lines[i + 2]
            let author = lines[i + 3]
            let dateStr = lines[i + 4]
            i += 5

            let date = ISO8601DateFormatter().date(from: dateStr) ?? Date()
            commits.append(GitCommit(
                sha: sha, shortSHA: shortSHA, message: message,
                author: author, date: date, files: nil
            ))
        }

        return commits
    }

    /// Fetch recent commits that touched a specific file path.
    static func fileLog(path: String, in directory: URL, count: Int = 20) -> [GitCommit] {
        let format = "%H%n%h%n%s%n%an%n%aI"
        guard let output = runGit(
            args: ["log", "-\(count)", "--pretty=format:\(format)", "--no-merges", "--follow", "--", path],
            at: directory
        ), !output.isEmpty else {
            return []
        }

        let lines = output.components(separatedBy: "\n")
        var commits: [GitCommit] = []
        var i = 0

        while i + 4 < lines.count {
            let sha = lines[i]
            let shortSHA = lines[i + 1]
            let message = lines[i + 2]
            let author = lines[i + 3]
            let dateStr = lines[i + 4]
            i += 5

            let date = ISO8601DateFormatter().date(from: dateStr) ?? Date()
            commits.append(GitCommit(
                sha: sha, shortSHA: shortSHA, message: message,
                author: author, date: date, files: nil
            ))
        }

        return commits
    }

    // MARK: - Private

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
}
