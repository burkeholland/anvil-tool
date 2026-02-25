import SwiftUI

/// Manages file tree state: entries, expanded directories, git status, and file watching.
final class FileTreeModel: ObservableObject {
    @Published private(set) var entries: [FileEntry] = []
    @Published private(set) var gitStatuses: [String: GitFileStatus] = [:]

    private(set) var expandedDirs: Set<URL> = []
    private var rootURL: URL?
    private var fileWatcher: FileWatcher?
    private var refreshGeneration: UInt64 = 0

    deinit {
        fileWatcher?.stop()
    }

    func start(rootURL: URL) {
        self.rootURL = rootURL
        rebuildEntries()
        refreshGitStatus()
        fileWatcher = FileWatcher(directory: rootURL) { [weak self] in
            self?.onFileSystemChange()
        }
    }

    func toggleDirectory(_ entry: FileEntry) {
        guard entry.isDirectory else { return }
        if expandedDirs.contains(entry.url) {
            expandedDirs.remove(entry.url)
            expandedDirs = expandedDirs.filter { !$0.path.hasPrefix(entry.url.path + "/") }
        } else {
            expandedDirs.insert(entry.url)
        }
        rebuildEntries()
    }

    func isExpanded(_ url: URL) -> Bool {
        expandedDirs.contains(url)
    }

    // MARK: - Private

    private func onFileSystemChange() {
        rebuildEntries()
        refreshGitStatus()
    }

    private func rebuildEntries() {
        guard let rootURL = rootURL else { return }
        var newEntries: [FileEntry] = []
        buildEntries(for: rootURL, depth: 0, into: &newEntries)
        entries = newEntries
    }

    private func buildEntries(for directory: URL, depth: Int, into entries: inout [FileEntry]) {
        let children = FileEntry.loadChildren(of: directory, depth: depth)
        for child in children {
            entries.append(child)
            if child.isDirectory && expandedDirs.contains(child.url) {
                buildEntries(for: child.url, depth: depth + 1, into: &entries)
            }
        }
    }

    private func refreshGitStatus() {
        guard let rootURL = rootURL else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let statuses = GitStatusProvider.status(for: rootURL)
            DispatchQueue.main.async {
                guard let self = self, self.refreshGeneration == generation else { return }
                self.gitStatuses = statuses
            }
        }
    }
}
