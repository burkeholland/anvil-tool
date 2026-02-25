import Foundation

/// Runs `git diff` and returns parsed results.
enum DiffProvider {

    /// Get the diff for a specific file (all uncommitted changes vs HEAD).
    static func diff(for fileURL: URL, in directory: URL) -> FileDiff? {
        let relativePath = relativePath(of: fileURL, in: directory)
        // Use HEAD to capture both staged and unstaged changes in one pass
        guard let output = runGitDiff(args: ["diff", "HEAD", "--", relativePath], at: directory),
              !output.isEmpty else {
            return nil
        }
        return DiffParser.parseSingleFile(output)
    }

    /// Get all changed files with their diffs (all uncommitted changes vs HEAD).
    static func allChanges(in directory: URL) -> [FileDiff] {
        guard let output = runGitDiff(args: ["diff", "HEAD"], at: directory), !output.isEmpty else {
            return []
        }
        return DiffParser.parse(output)
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
