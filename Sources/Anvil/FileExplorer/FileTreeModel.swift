import SwiftUI

/// Manages file tree state: entries, expanded directories, git status, and file watching.
final class FileTreeModel: ObservableObject {
    @Published private(set) var entries: [FileEntry] = []
    @Published private(set) var gitStatuses: [String: GitFileStatus] = [:]
    @Published var searchText: String = "" {
        didSet { rebuildEntries() }
    }
    /// Flat list of all files for search filtering.
    @Published private(set) var searchResults: [FileSearchResult] = []

    private(set) var expandedDirs: Set<URL> = []
    private var rootURL: URL?
    private var fileWatcher: FileWatcher?
    private var refreshGeneration: UInt64 = 0
    private var indexGeneration: UInt64 = 0
    /// Cached flat list of all files under root for fast search.
    private var allFiles: [FileSearchResult] = []

    deinit {
        fileWatcher?.stop()
    }

    var isSearching: Bool {
        !searchText.isEmpty
    }

    func start(rootURL: URL) {
        self.rootURL = rootURL
        rebuildFileIndex()
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

    // MARK: - File Operations

    /// Validates that a name is a safe single path component (no slashes, no `..`).
    private static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".."
    }

    /// Creates a new empty file inside the given directory.
    /// Returns the URL of the new file, or nil on failure.
    @discardableResult
    func createFile(named name: String, in directory: URL) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSafeFileName(trimmed) else { return nil }
        let newURL = directory.appendingPathComponent(trimmed).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: newURL.path) else { return nil }
        guard FileManager.default.createFile(atPath: newURL.path, contents: nil) else { return nil }
        expandedDirs.insert(directory)
        onFileSystemChange()
        return newURL
    }

    /// Creates a new folder inside the given directory.
    /// Returns the URL of the new folder, or nil on failure.
    @discardableResult
    func createFolder(named name: String, in directory: URL) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSafeFileName(trimmed) else { return nil }
        let newURL = directory.appendingPathComponent(trimmed).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: newURL.path) else { return nil }
        do {
            try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
        } catch {
            return nil
        }
        expandedDirs.insert(directory)
        onFileSystemChange()
        return newURL
    }

    /// Renames a file or folder. Returns the new URL, or nil on failure.
    @discardableResult
    func renameItem(at url: URL, to newName: String) -> URL? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSafeFileName(trimmed) else { return nil }
        let newURL = url.deletingLastPathComponent().appendingPathComponent(trimmed).standardizedFileURL
        guard newURL != url else { return url }
        guard !FileManager.default.fileExists(atPath: newURL.path) else { return nil }
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
        } catch {
            return nil
        }
        // Update expanded dirs if a directory was renamed
        if expandedDirs.contains(url) {
            expandedDirs.remove(url)
            expandedDirs.insert(newURL)
        }
        onFileSystemChange()
        return newURL
    }

    /// Moves a file or folder to the Trash. Returns true on success.
    @discardableResult
    func deleteItem(at url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            return false
        }
        expandedDirs.remove(url)
        onFileSystemChange()
        return true
    }

    // MARK: - Private

    private func onFileSystemChange() {
        rebuildFileIndex()
        rebuildEntries()
        refreshGitStatus()
    }

    private func rebuildEntries() {
        guard let rootURL = rootURL else { return }

        if isSearching {
            let query = searchText.lowercased()
            searchResults = allFiles.filter { $0.name.lowercased().contains(query) || $0.relativePath.lowercased().contains(query) }
        } else {
            searchResults = []
            var newEntries: [FileEntry] = []
            buildEntries(for: rootURL, depth: 0, into: &newEntries)
            entries = newEntries
        }
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

    /// Recursively indexes all non-hidden files for search. Runs on a background thread.
    private func rebuildFileIndex() {
        guard let rootURL = rootURL else { return }
        indexGeneration &+= 1
        let generation = indexGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var results: [FileSearchResult] = []
            Self.indexFiles(at: rootURL, rootURL: rootURL, into: &results)
            DispatchQueue.main.async {
                guard let self = self, self.indexGeneration == generation else { return }
                self.allFiles = results
                if self.isSearching {
                    self.rebuildEntries()
                }
            }
        }
    }

    private static func indexFiles(at directory: URL, rootURL: URL, into results: inout [FileSearchResult]) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let hidden: Set<String> = [".git", ".build", ".DS_Store", ".swiftpm", "node_modules"]
        for url in contents {
            let name = url.lastPathComponent
            if hidden.contains(name) { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                Self.indexFiles(at: url, rootURL: rootURL, into: &results)
            } else {
                let rootPath = rootURL.standardizedFileURL.path
                let absPath = url.standardizedFileURL.path
                var relPath = absPath
                if absPath.hasPrefix(rootPath) {
                    relPath = String(absPath.dropFirst(rootPath.count))
                    if relPath.hasPrefix("/") { relPath = String(relPath.dropFirst()) }
                }
                results.append(FileSearchResult(url: url, name: name, relativePath: relPath))
            }
        }
    }
}

/// A file entry used in search results — stores the name and relative path for display.
struct FileSearchResult: Identifiable {
    let url: URL
    let name: String
    let relativePath: String

    var id: URL { url }

    var directoryPath: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }
}
