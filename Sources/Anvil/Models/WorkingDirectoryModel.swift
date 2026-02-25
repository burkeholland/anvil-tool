import Foundation
import Combine

final class WorkingDirectoryModel: ObservableObject {
    @Published private(set) var directoryURL: URL?
    @Published private(set) var gitBranch: String?

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
            DispatchQueue.main.async {
                guard self?.directoryURL == directory else { return }
                if self?.gitBranch != branch {
                    self?.gitBranch = branch
                }
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
