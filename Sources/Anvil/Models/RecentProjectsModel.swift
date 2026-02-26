import Foundation
import Combine

/// Git metadata for a project directory, fetched in the background.
struct GitProjectInfo: Equatable {
    let branch: String?
    let isDirty: Bool
    let changedFileCount: Int
}

/// Persists and retrieves recently opened project directories using UserDefaults.
final class RecentProjectsModel: ObservableObject {
    @Published private(set) var recentProjects: [RecentProject] = []
    /// Background-scanned git info keyed by project path.
    @Published private(set) var gitInfo: [String: GitProjectInfo] = [:]

    private let maxRecents = 10
    private let defaultsKey = "dev.anvil.recentProjects"
    private let scanQueue = DispatchQueue(label: "dev.anvil.recent-projects-scan", qos: .utility)

    struct RecentProject: Identifiable, Codable, Equatable {
        let path: String
        let name: String
        var lastOpened: Date

        var id: String { path }

        var url: URL { URL(fileURLWithPath: path) }

        /// Whether the directory still exists on disk.
        var exists: Bool {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    init() {
        load()
    }

    /// Scans all recent projects for git metadata in the background.
    func refreshGitInfo() {
        let projects = recentProjects
        scanQueue.async { [weak self] in
            var results: [String: GitProjectInfo] = [:]
            for project in projects {
                guard project.exists else { continue }
                let info = Self.scanGitInfo(at: URL(fileURLWithPath: project.path))
                results[project.path] = info
            }
            DispatchQueue.main.async {
                self?.gitInfo = results
            }
        }
    }

    private static func scanGitInfo(at directory: URL) -> GitProjectInfo {
        let branch = runGit(["rev-parse", "--abbrev-ref", "HEAD"], at: directory)
        let statusOutput = runGit(["status", "--porcelain"], at: directory) ?? ""
        let changedCount = statusOutput.isEmpty ? 0 : statusOutput.components(separatedBy: "\n").filter { !$0.isEmpty }.count
        return GitProjectInfo(
            branch: branch,
            isDirty: changedCount > 0,
            changedFileCount: changedCount
        )
    }

    private static func runGit(_ args: [String], at directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Record that a directory was opened. Moves it to the top if already present.
    func recordOpen(_ url: URL) {
        let path = url.standardizedFileURL.path
        let name = url.lastPathComponent

        var projects = recentProjects
        projects.removeAll { $0.path == path }
        projects.insert(RecentProject(path: path, name: name, lastOpened: Date()), at: 0)

        if projects.count > maxRecents {
            projects = Array(projects.prefix(maxRecents))
        }

        recentProjects = projects
        save()
    }

    /// Remove a specific project from recents.
    func remove(_ project: RecentProject) {
        recentProjects.removeAll { $0.path == project.path }
        save()
    }

    func clearAll() {
        recentProjects = []
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(recentProjects) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([RecentProject].self, from: data) else {
            return
        }
        // Filter out directories that no longer exist
        recentProjects = decoded.filter(\.exists)
    }
}
