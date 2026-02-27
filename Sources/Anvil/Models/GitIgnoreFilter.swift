import Foundation

/// Uses `git ls-files` to determine which files and directories should be visible,
/// respecting .gitignore, .git/info/exclude, and the user's global gitignore.
/// For non-git repos, falls back to a hardcoded exclusion list.
/// Thread-safe: all mutable state is guarded by a lock.
final class GitIgnoreFilter {
    private var allowedFiles: Set<String> = []
    private var ignoredDirs: Set<String> = []
    private var filterAvailable: Bool = false
    private let lock = NSLock()
    private let rootPath: String
    let isGitRepo: Bool

    /// Directories/files always hidden regardless of git status
    static let alwaysHidden: Set<String> = [".git", ".DS_Store"]

    /// Fallback exclusions for non-git repos (and when git commands fail)
    static let defaultHidden: Set<String> = [
        ".git", ".build", ".DS_Store", ".swiftpm", "node_modules",
        ".Trash", "DerivedData", "xcuserdata"
    ]

    /// Creates a filter. Does NOT run git on init — call `refresh()` from a background thread.
    init(rootURL: URL) {
        self.rootPath = rootURL.standardizedFileURL.path
        self.isGitRepo = FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent(".git").path
        )
    }

    /// Testable initializer: supply a known file list and ignored dirs instead of running git.
    init(rootPath: String, knownFiles: [String], ignoredDirectories: [String] = []) {
        self.rootPath = rootPath
        self.isGitRepo = true
        lock.lock()
        applyFileList(knownFiles)
        self.ignoredDirs = Set(ignoredDirectories)
        self.filterAvailable = true
        lock.unlock()
    }

    /// Re-runs `git ls-files` to update the filter. Safe to call from any thread.
    func refresh() {
        guard isGitRepo else { return }

        // 1. Get non-ignored files (tracked + untracked-but-not-ignored)
        let fileOutput = runGit(args: ["-c", "core.quotePath=false", "ls-files", "-co", "--exclude-standard"])
        // 2. Get ignored directories (blocklist approach — avoids empty-dir problem)
        let ignoredOutput = runGit(args: ["-c", "core.quotePath=false", "ls-files", "-o", "-i", "--exclude-standard", "--directory"])

        lock.lock()
        if let files = fileOutput {
            applyFileList(files)
            self.ignoredDirs = Set(
                (ignoredOutput ?? []).map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
            )
            self.filterAvailable = true
        }
        // If git failed, filterAvailable stays false → fallback behavior
        lock.unlock()
    }

    /// Whether a file or directory should appear in the tree.
    func shouldShow(name: String, relativePath: String, isDirectory: Bool) -> Bool {
        if Self.alwaysHidden.contains(name) { return false }

        if !isGitRepo {
            if name.hasPrefix(".") { return false }
            return !Self.defaultHidden.contains(name)
        }

        lock.lock()
        let available = filterAvailable
        let files = allowedFiles
        let ignored = ignoredDirs
        lock.unlock()

        if !available {
            // Git repo but filter hasn't loaded yet — use safe fallback
            if name.hasPrefix(".") { return false }
            return !Self.defaultHidden.contains(name)
        }

        if isDirectory {
            return !ignored.contains(relativePath)
        } else {
            return files.contains(relativePath)
        }
    }

    /// Computes the path of `url` relative to the repo root.
    func relativePath(for url: URL) -> String {
        let absPath = url.standardizedFileURL.path
        guard absPath.hasPrefix(rootPath) else { return absPath }
        var rel = String(absPath.dropFirst(rootPath.count))
        if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
        return rel
    }

    // MARK: - Private

    /// Runs a git command and returns output lines, or nil on failure.
    private func runGit(args: [String]) -> [String]? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootPath] + args
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            // Read stdout BEFORE waitUntilExit to avoid pipe-buffer deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.split(separator: "\n").map(String.init)
        } catch {
            return nil
        }
    }

    /// Populates allowedFiles from the given file list. Caller must hold lock.
    private func applyFileList(_ files: [String]) {
        allowedFiles = Set(files)
    }
}
