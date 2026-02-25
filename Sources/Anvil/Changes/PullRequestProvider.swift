import Foundation

/// Static helpers for interacting with GitHub Pull Requests via the `gh` CLI.
enum PullRequestProvider {

    struct OpenPR {
        let url: String
        let title: String
        let number: Int
    }

    /// Checks for an open PR on the current branch using `gh pr view`.
    /// Returns nil if no open PR or if `gh` is unavailable.
    static func openPR(in directory: URL) -> OpenPR? {
        let (exitCode, stdout, _) = runGH(
            args: ["pr", "view", "--json", "url,title,number"],
            at: directory
        )
        guard exitCode == 0, let json = stdout else { return nil }
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = obj["url"] as? String,
              let title = obj["title"] as? String,
              let number = obj["number"] as? Int else { return nil }
        return OpenPR(url: url, title: title, number: number)
    }

    /// Creates a pull request using `gh pr create`.
    /// Returns (success, prURL or errorMessage).
    static func create(title: String, body: String, base: String, in directory: URL) -> (success: Bool, urlOrError: String?) {
        let args = ["pr", "create", "--title", title, "--body", body, "--base", base]
        let (exitCode, stdout, stderr) = runGH(args: args, at: directory)
        if exitCode == 0 {
            return (true, stdout)
        }
        return (false, stderr?.isEmpty == false ? stderr : "Failed to create pull request")
    }

    /// Returns the list of remote branch names for use in the base branch picker.
    static func remoteBranches(in directory: URL) -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["branch", "-r", "--format=%(refname:short)"]
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { return [] }
        guard process.terminationStatus == 0 else { return [] }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasSuffix("/HEAD") && $0.contains("/") }
            .compactMap { branch -> String? in
                guard let slash = branch.firstIndex(of: "/") else { return nil }
                return String(branch[branch.index(after: slash)...])
            }
    }

    // MARK: - Private

    private static func runGH(args: [String], at directory: URL) -> (exitCode: Int32, stdout: String?, stderr: String?) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + args
        process.currentDirectoryURL = directory
        process.standardOutput = outPipe
        process.standardError = errPipe
        // Extend PATH so gh installed via Homebrew is found when launched from the Dock/Spotlight.
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/usr/local/bin:/opt/homebrew/bin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env

        do { try process.run() } catch { return (-1, nil, error.localizedDescription) }

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
