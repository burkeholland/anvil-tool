import Foundation
import AppKit

/// Constructs and opens github.com URLs for files, commits, and repositories.
enum GitHubURLBuilder {

    // MARK: - Open Actions (dispatch to background; safe to call from the main thread)

    /// Opens the repository root on GitHub in the default browser.
    static func openRepo(rootURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = repoURL(in: rootURL) else { return }
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
    }

    /// Opens a file on the current branch on GitHub in the default browser.
    static func openFile(rootURL: URL, relativePath: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let repo = repoURL(in: rootURL) else { return }
            let branch = currentBranch(in: rootURL) ?? "main"
            guard let url = blobURL(repo: repo, ref: branch, path: relativePath) else { return }
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
    }

    /// Opens a file at a specific commit on GitHub in the default browser.
    static func openFile(rootURL: URL, sha: String, relativePath: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let repo = repoURL(in: rootURL),
                  let url = blobURL(repo: repo, ref: sha, path: relativePath) else { return }
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
    }

    /// Opens a commit on GitHub in the default browser.
    static func openCommit(rootURL: URL, sha: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let repo = repoURL(in: rootURL) else { return }
            let url = repo.appendingPathComponent("commit/\(sha)")
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: - URL Builders

    static func repoURL(in directory: URL) -> URL? {
        guard let remote = remoteURL(in: directory) else { return nil }
        return parseGitHubURL(from: remote)
    }

    // MARK: - Private helpers

    private static func blobURL(repo: URL, ref: String, path: String) -> URL? {
        guard var components = URLComponents(url: repo, resolvingAgainstBaseURL: false) else { return nil }
        let encodedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        components.percentEncodedPath += "/blob/" + encodedRef + "/" + encodedPath
        return components.url
    }

    private static func currentBranch(in directory: URL) -> String? {
        let (code, stdout, _) = runGit(["rev-parse", "--abbrev-ref", "HEAD"], at: directory)
        guard code == 0, let branch = stdout, !branch.isEmpty else { return nil }
        return branch
    }

    private static func remoteURL(in directory: URL) -> String? {
        // Prefer "origin"; fall back to the first configured remote.
        let (code, stdout, _) = runGit(["remote", "get-url", "origin"], at: directory)
        if code == 0, let url = stdout, !url.isEmpty { return url }

        let (code2, remotes, _) = runGit(["remote"], at: directory)
        guard code2 == 0, let names = remotes, !names.isEmpty else { return nil }
        let firstName = names.components(separatedBy: "\n").first(where: { !$0.isEmpty }) ?? ""
        guard !firstName.isEmpty else { return nil }
        let (code3, url, _) = runGit(["remote", "get-url", firstName], at: directory)
        guard code3 == 0 else { return nil }
        return url
    }

    private static func parseGitHubURL(from remoteURL: String) -> URL? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // HTTPS: https://github.com/owner/repo[.git]
        if trimmed.hasPrefix("https://github.com/") {
            let stripped = trimmed.hasSuffix(".git") ? String(trimmed.dropLast(4)) : trimmed
            return URL(string: stripped)
        }

        // SSH: git@github.com:owner/repo[.git]
        if trimmed.hasPrefix("git@github.com:") {
            var path = String(trimmed.dropFirst("git@github.com:".count))
            if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
            return URL(string: "https://github.com/" + path)
        }

        return nil
    }

    private static func runGit(_ args: [String], at directory: URL) -> (Int32, String?, String?) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = outPipe
        process.standardError = errPipe
        do { try process.run() } catch { return (-1, nil, nil) }

        // Read stdout and stderr concurrently to prevent pipe-buffer deadlock.
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
