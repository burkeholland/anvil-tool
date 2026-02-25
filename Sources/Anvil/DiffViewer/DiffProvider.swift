import Foundation

/// Runs `git diff` and returns parsed results.
enum DiffProvider {

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
