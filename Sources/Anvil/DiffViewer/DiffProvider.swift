import Foundation

/// Runs `git diff` and returns parsed results.
enum DiffProvider {

    /// Get the staged diff for a specific file (`git diff --cached` vs HEAD).
    /// Returns nil when there are no staged changes for the file.
    static func stagedDiff(for fileURL: URL, in directory: URL) -> FileDiff? {
        let relativePath = relativePath(of: fileURL, in: directory)
        guard let output = runGitDiff(args: ["diff", "--cached", "--", relativePath], at: directory),
              !output.isEmpty else { return nil }
        return DiffParser.parseSingleFile(output)
    }

    /// Get the diff for a specific file (all uncommitted changes vs HEAD).
    /// Falls back to a synthetic all-additions diff for untracked files.
    static func diff(for fileURL: URL, in directory: URL) -> FileDiff? {
        let relativePath = relativePath(of: fileURL, in: directory)
        // Use HEAD to capture both staged and unstaged changes in one pass
        if let output = runGitDiff(args: ["diff", "HEAD", "--", relativePath], at: directory),
           !output.isEmpty {
            return DiffParser.parseSingleFile(output)
        }
        // No diff from git — check if this is an untracked file
        if isUntracked(relativePath, in: directory) {
            return newFileDiff(for: fileURL, relativePath: relativePath)
        }
        return nil
    }

    /// Get all changed files with their diffs (all uncommitted changes vs HEAD).
    static func allChanges(in directory: URL) -> [FileDiff] {
        guard let output = runGitDiff(args: ["diff", "HEAD"], at: directory), !output.isEmpty else {
            return []
        }
        return DiffParser.parse(output)
    }

    /// Get the diff for a specific file in a stash entry.
    static func stashFileDiff(stashIndex: Int, filePath: String, in directory: URL) -> FileDiff? {
        let ref = "stash@{\(stashIndex)}"
        if let output = runGitDiff(
            args: ["diff", "\(ref)^1", ref, "--", filePath],
            at: directory
        ), !output.isEmpty {
            return DiffParser.parseSingleFile(output)
        }
        // Fallback: show stash@{N}:filePath as a new-file diff (e.g. untracked)
        if let output = runGitDiff(
            args: ["show", "\(ref):\(filePath)"],
            at: directory
        ), !output.isEmpty {
            // Wrap raw content as synthetic additions diff
            let lines = output.components(separatedBy: "\n")
            let diffLines: [DiffLine] = lines.enumerated().map { i, text in
                DiffLine(id: i + 1, kind: .addition, text: text,
                         oldLineNumber: nil, newLineNumber: i + 1)
            }
            let header = "@@ -0,0 +1,\(lines.count) @@"
            let hunk = DiffHunk(id: 0, header: header, lines: diffLines)
            return FileDiff(id: filePath, oldPath: "/dev/null", newPath: filePath, hunks: [hunk])
        }
        return nil
    }

    /// Get the diff for a specific file in a specific commit.
    static func commitFileDiff(sha: String, filePath: String, in directory: URL) -> FileDiff? {
        // Try parent..commit diff first; fall back to `git show` for root commits
        if let output = runGitDiff(
            args: ["diff", "\(sha)~1", sha, "--", filePath],
            at: directory
        ), !output.isEmpty {
            return DiffParser.parseSingleFile(output)
        }
        // Fallback for root commit (no parent)
        if let output = runGitDiff(
            args: ["show", "--format=", sha, "--", filePath],
            at: directory
        ), !output.isEmpty {
            return DiffParser.parseSingleFile(output)
        }
        return nil
    }

    /// Generate a synthetic all-additions diff for an untracked/new file.
    static func newFileDiff(for fileURL: URL, in directory: URL) -> FileDiff? {
        let relativePath = relativePath(of: fileURL, in: directory)
        return newFileDiff(for: fileURL, relativePath: relativePath)
    }

    /// Generate a synthetic all-additions diff from a file's content.
    static func newFileDiff(for fileURL: URL, relativePath: String) -> FileDiff? {
        // Guard: skip binary or oversized files (match FilePreviewModel's 1MB cap)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size > 0, size <= 1_048_576 else {
            return nil
        }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
              !content.isEmpty else {
            return nil
        }
        let endsWithNewline = content.hasSuffix("\n")
        let contentLines = content.components(separatedBy: "\n")
        // Strip trailing empty element from final newline
        let lines = contentLines.last == "" ? Array(contentLines.dropLast()) : contentLines
        guard !lines.isEmpty else { return nil }

        var diffLines: [DiffLine] = []
        let header = "@@ -0,0 +1,\(lines.count) @@"
        diffLines.append(DiffLine(id: 0, kind: .hunkHeader, text: header,
                                  oldLineNumber: nil, newLineNumber: nil))
        for (i, line) in lines.enumerated() {
            diffLines.append(DiffLine(id: i + 1, kind: .addition, text: line,
                                      oldLineNumber: nil, newLineNumber: i + 1))
        }

        let hunk = DiffHunk(id: 0, header: header, lines: diffLines)
        var diff = FileDiff(id: relativePath, oldPath: "/dev/null",
                            newPath: relativePath, hunks: [hunk])
        diff.noTrailingNewline = !endsWithNewline
        return diff
    }

    // MARK: - Branch Diff (PR Preview)

    /// Returns the merge-base SHA between `base` and HEAD, or nil if there is
    /// no common ancestor (e.g., unrelated histories, detached HEAD with no base).
    static func mergeBase(_ base: String, in directory: URL) -> String? {
        guard let sha = runGitDiff(args: ["merge-base", base, "HEAD"], at: directory)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !sha.isEmpty else {
            return nil
        }
        return sha
    }

    /// Returns the raw diff between `baseSHA` and HEAD (the full branch diff).
    static func branchDiff(baseSHA: String, in directory: URL) -> [FileDiff] {
        guard let output = runGitDiff(args: ["diff", "--no-renames", baseSHA, "HEAD"], at: directory),
              !output.isEmpty else {
            return []
        }
        return DiffParser.parse(output)
    }

    /// Returns a list of changed files between `baseSHA` and HEAD with addition/deletion stats.
    static func branchChangedFiles(baseSHA: String, in directory: URL) -> [BranchDiffFile] {
        // Use --no-renames to avoid {old => new} path format mismatches
        guard let numstatOutput = runGitDiff(args: ["diff", "--numstat", "--no-renames", baseSHA, "HEAD"], at: directory),
              !numstatOutput.isEmpty else {
            return []
        }
        let statusOutput = runGitDiff(args: ["diff", "--name-status", "--no-renames", baseSHA, "HEAD"], at: directory) ?? ""

        var statusMap: [String: String] = [:]
        for line in statusOutput.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let status = String(parts[0].prefix(1))
            let path = String(parts[1])
            statusMap[path] = status
        }

        var files: [BranchDiffFile] = []
        for line in numstatOutput.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3 else { continue }
            let adds = Int(parts[0]) ?? 0
            let dels = Int(parts[1]) ?? 0
            let path = String(parts[2])
            let status = statusMap[path] ?? "M"
            files.append(BranchDiffFile(
                path: path, additions: adds, deletions: dels, status: status
            ))
        }

        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Detects the default branch name (main or master) if it exists.
    static func defaultBranch(in directory: URL) -> String? {
        for candidate in ["main", "master"] {
            if let sha = runGitDiff(args: ["rev-parse", "--verify", candidate], at: directory)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !sha.isEmpty {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Private

    private static func runGitDiff(args: [String], at directory: URL) -> String? {
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

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func isUntracked(_ relativePath: String, in directory: URL) -> Bool {
        guard let output = runGitDiff(args: ["ls-files", relativePath], at: directory) else {
            return false
        }
        // ls-files returns nothing for untracked files
        return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func relativePath(of fileURL: URL, in directory: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let dirPath = directory.standardizedFileURL.path
        if filePath.hasPrefix(dirPath) {
            var relative = String(filePath.dropFirst(dirPath.count))
            if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
            return relative
        }
        return filePath
    }
}
