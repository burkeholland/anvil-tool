import Foundation

/// Fetches and manages git stash entries.
enum GitStashProvider {

    /// Fetch all stash entries.
    static func list(in directory: URL) -> [StashEntry] {
        // Format: refname, hash, subject, author date (ISO)
        guard let output = runGit(
            args: ["stash", "list", "--format=%gd%n%H%n%s%n%aI"],
            at: directory
        ), !output.isEmpty else {
            return []
        }

        let lines = output.components(separatedBy: "\n")
        var entries: [StashEntry] = []
        var i = 0

        while i + 3 < lines.count {
            let refName = lines[i]       // stash@{0}
            let sha = lines[i + 1]
            let message = lines[i + 2]
            let dateStr = lines[i + 3]
            i += 4

            // Parse index from "stash@{N}"
            let index: Int
            if let openBrace = refName.firstIndex(of: "{"),
               let closeBrace = refName.firstIndex(of: "}"),
               openBrace < closeBrace {
                let indexStr = refName[refName.index(after: openBrace)..<closeBrace]
                index = Int(indexStr) ?? entries.count
            } else {
                index = entries.count
            }

            let date = ISO8601DateFormatter().date(from: dateStr) ?? Date()
            entries.append(StashEntry(
                index: index, sha: sha, message: message,
                date: date, files: nil
            ))
        }

        return entries
    }

    /// Fetch the files changed in a specific stash entry.
    static func stashFiles(index: Int, in directory: URL) -> [CommitFile] {
        // Use `git stash show` which properly handles untracked files
        guard let output = runGit(
            args: ["stash", "show", "--include-untracked", "--numstat", "stash@{\(index)}"],
            at: directory
        ), !output.isEmpty else {
            return []
        }

        let statusOutput = runGit(
            args: ["stash", "show", "--include-untracked", "--name-status", "stash@{\(index)}"],
            at: directory
        ) ?? ""

        // Parse numstat
        var statsMap: [String: (Int, Int)] = [:]
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3 else { continue }
            let adds = Int(parts[0]) ?? 0
            let dels = Int(parts[1]) ?? 0
            let path = String(parts[2])
            statsMap[path] = (adds, dels)
        }

        // Parse name-status
        var files: [CommitFile] = []
        for line in statusOutput.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count >= 2 else { continue }
            let statusRaw = String(parts[0])
            let status = String(statusRaw.prefix(1))
            let path: String
            if status == "R" && parts.count >= 3 {
                path = String(parts[2])
            } else {
                path = String(parts[1])
            }

            let (adds, dels) = statsMap[path] ?? (0, 0)
            files.append(CommitFile(
                path: path, additions: adds, deletions: dels, status: status
            ))
        }

        // If name-status produced nothing (e.g. old git), fall back to numstat paths
        if files.isEmpty && !statsMap.isEmpty {
            for (path, (adds, dels)) in statsMap {
                files.append(CommitFile(path: path, additions: adds, deletions: dels, status: "M"))
            }
        }

        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Stash all changes (including untracked) with an optional message.
    @discardableResult
    static func push(message: String?, includeUntracked: Bool = true, in directory: URL) -> (success: Bool, error: String?) {
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        if let message = message, !message.isEmpty { args += ["-m", message] }
        return runGitWithError(args: args, at: directory)
    }

    /// Apply a stash without removing it from the stash list.
    @discardableResult
    static func apply(sha: String, in directory: URL) -> (success: Bool, error: String?) {
        runGitWithError(args: ["stash", "apply", sha], at: directory)
    }

    /// Apply and remove a stash from the stash list.
    /// Resolves SHA to current index to prevent index drift.
    @discardableResult
    static func pop(sha: String, in directory: URL) -> (success: Bool, error: String?) {
        guard let currentIndex = resolveIndex(for: sha, in: directory) else {
            return (false, "Stash no longer exists")
        }
        return runGitWithError(args: ["stash", "pop", "stash@{\(currentIndex)}"], at: directory)
    }

    /// Remove a stash entry without applying it.
    /// Resolves SHA to current index to prevent index drift.
    @discardableResult
    static func drop(sha: String, in directory: URL) -> (success: Bool, error: String?) {
        guard let currentIndex = resolveIndex(for: sha, in: directory) else {
            return (false, "Stash no longer exists")
        }
        return runGitWithError(args: ["stash", "drop", "stash@{\(currentIndex)}"], at: directory)
    }

    /// Resolve a stash SHA to its current index, returning nil if not found.
    private static func resolveIndex(for sha: String, in directory: URL) -> Int? {
        guard let output = runGit(
            args: ["stash", "list", "--format=%H"],
            at: directory
        ), !output.isEmpty else {
            return nil
        }
        let shas = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        return shas.firstIndex(of: sha)
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
