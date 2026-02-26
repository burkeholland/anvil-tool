import Foundation
import Combine

final class WorkingDirectoryModel: ObservableObject {
    @Published private(set) var directoryURL: URL?
    @Published private(set) var gitBranch: String?
    @Published private(set) var aheadCount: Int = 0
    @Published private(set) var behindCount: Int = 0
    @Published private(set) var hasUpstream: Bool = false
    @Published private(set) var hasRemotes: Bool = false
    @Published private(set) var isPushing = false
    @Published private(set) var isPulling = false
    @Published var lastSyncError: String?
    /// URL of an open pull request for the current branch, if one exists.
    @Published var openPRURL: String?
    /// Title of the open pull request for the current branch.
    @Published var openPRTitle: String?

    private var branchWatcher: FileWatcher?
    private var branchPollTimer: Timer?
    private static let lastDirectoryKey = "dev.anvil.lastOpenedDirectory"

    deinit {
        branchWatcher?.stop()
        branchPollTimer?.invalidate()
    }

    var displayPath: String {
        guard let url = directoryURL else { return "No directory selected" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var projectName: String {
        directoryURL?.lastPathComponent ?? "Anvil"
    }

    var path: String? {
        directoryURL?.path
    }

    init() {
        // CLI argument takes priority: `Anvil /path/to/project` or `Anvil .`
        if let cliURL = Self.directoryFromArguments() {
            self.directoryURL = cliURL
            UserDefaults.standard.set(cliURL.standardizedFileURL.path, forKey: Self.lastDirectoryKey)
            startBranchTracking(cliURL)
            return
        }

        // Restore last opened directory if it still exists
        if let savedPath = UserDefaults.standard.string(forKey: Self.lastDirectoryKey) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: savedPath, isDirectory: &isDir), isDir.boolValue {
                let url = URL(fileURLWithPath: savedPath)
                self.directoryURL = url
                startBranchTracking(url)
                return
            }
        }
        self.directoryURL = nil
    }

    /// Parses CLI arguments for a directory path (e.g. `Anvil .` or `Anvil /path/to/project`).
    private static func directoryFromArguments() -> URL? {
        let args = ProcessInfo.processInfo.arguments
        guard args.count >= 2 else { return nil }
        let pathArg = args[1]

        // Skip flags (e.g. -NSDocumentRevisionsDebugMode, -AppleLanguages)
        guard !pathArg.hasPrefix("-") else { return nil }

        // Expand ~ to home directory
        let expanded = NSString(string: pathArg).expandingTildeInPath

        // Resolve relative paths against the current working directory
        let resolved: String
        if expanded.hasPrefix("/") {
            resolved = expanded
        } else {
            let cwd = FileManager.default.currentDirectoryPath
            resolved = (cwd as NSString).appendingPathComponent(expanded)
        }

        let url = URL(fileURLWithPath: resolved).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return nil
        }
        return url
    }

    func setDirectory(_ url: URL) {
        directoryURL = url
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: Self.lastDirectoryKey)
        startBranchTracking(url)
    }

    func closeProject() {
        branchWatcher?.stop()
        branchPollTimer?.invalidate()
        branchPollTimer = nil
        gitBranch = nil
        aheadCount = 0
        behindCount = 0
        hasUpstream = false
        hasRemotes = false
        isPushing = false
        isPulling = false
        lastSyncError = nil
        openPRURL = nil
        openPRTitle = nil
        directoryURL = nil
        UserDefaults.standard.removeObject(forKey: Self.lastDirectoryKey)
    }

    // MARK: - Git Branch Tracking

    private func startBranchTracking(_ url: URL) {
        branchWatcher?.stop()
        branchPollTimer?.invalidate()
        branchPollTimer = nil

        refreshBranch(at: url)

        // Watch .git directory for branch changes (checkout, commit, etc.)
        let gitDir = url.appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: gitDir.path) {
            branchWatcher = FileWatcher(directory: gitDir) { [weak self] in
                self?.refreshBranch(at: url)
            }
        } else {
            // No .git directory — poll as fallback (repo may be initialized later)
            branchPollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let gitExists = FileManager.default.fileExists(atPath: gitDir.path)
                if gitExists {
                    // .git appeared — switch to FileWatcher and stop polling
                    self.branchPollTimer?.invalidate()
                    self.branchPollTimer = nil
                    self.startBranchTracking(url)
                }
            }
        }
    }

    private func refreshBranch(at directory: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let branch = Self.currentBranch(at: directory)
            let remotes = GitRemoteProvider.hasRemotes(in: directory)
            let upstream = GitRemoteProvider.upstream(in: directory)
            let counts = GitRemoteProvider.aheadBehind(in: directory)
            DispatchQueue.main.async {
                guard self?.directoryURL == directory else { return }
                let branchChanged = self?.gitBranch != branch
                if branchChanged {
                    self?.gitBranch = branch
                    // Clear stale PR info when branch changes; a fresh check will be triggered.
                    self?.openPRURL = nil
                    self?.openPRTitle = nil
                }
                self?.hasRemotes = remotes
                self?.hasUpstream = upstream != nil
                self?.aheadCount = counts?.ahead ?? 0
                self?.behindCount = counts?.behind ?? 0
                if branchChanged {
                    self?.refreshOpenPR()
                }
            }
        }
    }

    /// Asynchronously checks for an open pull request on the current branch via `gh pr view`
    /// and updates `openPRURL` / `openPRTitle`.
    func refreshOpenPR() {
        guard let url = directoryURL else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pr = PullRequestProvider.openPR(in: url)
            DispatchQueue.main.async {
                guard self?.directoryURL == url else { return }
                self?.openPRURL = pr?.url
                self?.openPRTitle = pr?.title
            }
        }
    }

    /// True when any remote sync operation is in progress.
    var isSyncing: Bool { isPushing || isPulling }

    // MARK: - Push / Pull

    func push() {
        guard let url = directoryURL, let branch = gitBranch, !isSyncing else { return }
        isPushing = true
        lastSyncError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: (success: Bool, error: String?)
            if self?.hasUpstream == true {
                result = GitRemoteProvider.push(in: url)
            } else {
                result = GitRemoteProvider.pushSetUpstream(branch: branch, in: url)
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isPushing = false
                if result.success {
                    self.lastSyncError = nil
                    self.refreshBranch(at: url)
                    self.refreshOpenPR()
                } else {
                    self.lastSyncError = result.error ?? "Push failed"
                }
            }
        }
    }

    func pull() {
        guard let url = directoryURL, !isSyncing else { return }
        isPulling = true
        lastSyncError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = GitRemoteProvider.pull(in: url)

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isPulling = false
                if result.success {
                    self.lastSyncError = nil
                    self.refreshBranch(at: url)
                } else {
                    self.lastSyncError = result.error ?? "Pull failed"
                }
            }
        }
    }

    func fetch() {
        guard let url = directoryURL else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = GitRemoteProvider.fetch(in: url)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.refreshBranch(at: url)
            }
        }
    }

    private static func currentBranch(at directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
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
        let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result?.isEmpty == false ? result : nil
    }
}
