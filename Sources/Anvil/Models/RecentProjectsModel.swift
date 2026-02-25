import Foundation
import Combine

/// Persists and retrieves recently opened project directories using UserDefaults.
final class RecentProjectsModel: ObservableObject {
    @Published private(set) var recentProjects: [RecentProject] = []

    private let maxRecents = 10
    private let defaultsKey = "dev.anvil.recentProjects"

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
