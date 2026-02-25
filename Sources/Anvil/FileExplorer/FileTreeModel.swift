import SwiftUI

/// Manages file tree state: entries, expanded directories, git status, and file watching.
final class FileTreeModel: ObservableObject {
    @Published private(set) var entries: [FileEntry] = []
    @Published private(set) var gitStatuses: [String: GitFileStatus] = [:]
    /// Number of changed files contained (recursively) in each directory.
    @Published private(set) var dirChangeCounts: [String: Int] = [:]
    /// Precomputed count of leaf-level changed files (excludes propagated directory statuses).
    @Published private(set) var changedFileCount: Int = 0
    @Published var searchText: String = "" {
        didSet { rebuildEntries() }
    }
    /// When true, the tree shows only files with git changes and their ancestor directories.
    @Published var showChangedOnly: Bool = false {
        didSet { rebuildEntries() }
    }
    /// Flat list of all files for search filtering.
    @Published private(set) var searchResults: [FileSearchResult] = []
    /// Set when a file should be scrolled into view. Each reveal gets a unique token
    /// so ScrollViewReader fires even when revealing the same file twice.
    @Published private(set) var revealTarget: RevealTarget?

    struct RevealTarget: Equatable {
        let url: URL
        let token: UUID
    }

    private(set) var expandedDirs: Set<URL> = []
    private var rootURL: URL?
    private var fileWatcher: FileWatcher?
    private var refreshGeneration: UInt64 = 0
    private var indexGeneration: UInt64 = 0
    /// Cached flat list of all files under root for fast search.
    private var allFiles: [FileSearchResult] = []
    /// Gitignore-aware filter for hiding ignored files and directories.
    private var gitIgnoreFilter: GitIgnoreFilter?

    deinit {
        fileWatcher?.stop()
    }

    var isSearching: Bool {
        !searchText.isEmpty
    }

    func start(rootURL: URL) {
        // Avoid redundant re-initialization for the same directory
        if self.rootURL == rootURL, fileWatcher != nil { return }
        self.rootURL = rootURL
        let filter = GitIgnoreFilter(rootURL: rootURL)
        self.gitIgnoreFilter = filter
        // Run initial git filter refresh off main thread, then build the tree
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            filter.refresh()
            DispatchQueue.main.async {
                self?.rebuildFileIndex()
                self?.rebuildEntries()
                self?.refreshGitStatus()
            }
        }
        // Show tree immediately with fallback filter while git loads
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
        if showChangedOnly { return true }
        return expandedDirs.contains(url)
    }

    /// Expands all ancestor directories of `url` so it becomes visible, then
    /// sets `revealTarget` to trigger a scroll-to in the view.
    func revealFile(url: URL) {
        guard let rootURL = rootURL else { return }
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath == rootPath || filePath.hasPrefix(rootPath + "/") else { return }

        // Clear search so the tree is visible
        if isSearching { searchText = "" }

        // Expand every ancestor directory from root down to the file's parent
        var parent = url.deletingLastPathComponent().standardizedFileURL
        while parent.path.count > rootPath.count {
            expandedDirs.insert(parent)
            parent = parent.deletingLastPathComponent().standardizedFileURL
        }
        // Include root if it's a direct child (root itself isn't in entries but children are)

        rebuildEntries()
        revealTarget = RevealTarget(url: url.standardizedFileURL, token: UUID())
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
        // Refresh gitignore filter on a background thread, then rebuild
        if rootURL != nil {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.gitIgnoreFilter?.refresh()
                DispatchQueue.main.async {
                    self?.rebuildFileIndex()
                    self?.rebuildEntries()
                    self?.refreshGitStatus()
                }
            }
        } else {
            rebuildFileIndex()
            rebuildEntries()
            refreshGitStatus()
        }
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
        let children = FileEntry.loadChildren(of: directory, depth: depth, filter: gitIgnoreFilter)
        for child in children {
            if showChangedOnly {
                let path = child.url.standardizedFileURL.path
                if child.isDirectory {
                    // Only include directories that contain changed files
                    guard dirChangeCounts[path] != nil && dirChangeCounts[path]! > 0 else { continue }
                    entries.append(child)
                    // Auto-expand directories in changed-only mode
                    buildEntries(for: child.url, depth: depth + 1, into: &entries)
                } else {
                    guard gitStatuses[path] != nil else { continue }
                    entries.append(child)
                }
            } else {
                entries.append(child)
                if child.isDirectory && expandedDirs.contains(child.url) {
                    buildEntries(for: child.url, depth: depth + 1, into: &entries)
                }
            }
        }
    }

    private func refreshGitStatus() {
        guard let rootURL = rootURL else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let rootPath = rootURL.standardizedFileURL.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let statuses = GitStatusProvider.status(for: rootURL)
            let counts = Self.computeDirChangeCounts(statuses: statuses, rootPath: rootPath)
            DispatchQueue.main.async {
                guard let self = self, self.refreshGeneration == generation else { return }
                self.gitStatuses = statuses
                self.dirChangeCounts = counts
                self.changedFileCount = Self.countLeafPaths(statuses: statuses, rootPath: rootPath)
                if self.showChangedOnly {
                    self.rebuildEntries()
                }
            }
        }
    }

    /// Counts changed files per directory by walking ancestor paths of each changed file.
    /// Filters out propagated directory entries from the git status map to avoid double-counting.
    static func computeDirChangeCounts(statuses: [String: GitFileStatus], rootPath: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        let filePaths = leafPaths(from: statuses)
        for filePath in filePaths {
            var dir = (filePath as NSString).deletingLastPathComponent
            while dir.count >= rootPath.count {
                counts[dir, default: 0] += 1
                let parent = (dir as NSString).deletingLastPathComponent
                if parent == dir { break }
                dir = parent
            }
        }
        return counts
    }

    /// Returns the number of leaf-level changed files (excludes propagated directory entries).
    static func countLeafPaths(statuses: [String: GitFileStatus], rootPath: String) -> Int {
        leafPaths(from: statuses).filter { $0.hasPrefix(rootPath) }.count
    }

    /// Filters status keys to only leaf paths (actual files, not propagated directory statuses).
    /// Uses sorted-order comparison for near-linear performance.
    private static func leafPaths(from statuses: [String: GitFileStatus]) -> [String] {
        let sorted = statuses.keys.sorted()
        return sorted.enumerated().filter { index, path in
            let nextIndex = index + 1
            if nextIndex < sorted.count {
                return !sorted[nextIndex].hasPrefix(path + "/")
            }
            return true
        }.map(\.element)
    }

    /// Recursively indexes all non-hidden files for search. Runs on a background thread.
    private func rebuildFileIndex() {
        guard let rootURL = rootURL else { return }
        indexGeneration &+= 1
        let generation = indexGeneration
        let filter = gitIgnoreFilter
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var results: [FileSearchResult] = []
            Self.indexFiles(at: rootURL, rootURL: rootURL, filter: filter, into: &results)
            DispatchQueue.main.async {
                guard let self = self, self.indexGeneration == generation else { return }
                self.allFiles = results
                if self.isSearching {
                    self.rebuildEntries()
                }
            }
        }
    }

    private static func indexFiles(at directory: URL, rootURL: URL, filter: GitIgnoreFilter?, into results: inout [FileSearchResult]) {
        let options: FileManager.DirectoryEnumerationOptions = filter?.isGitRepo == true ? [] : [.skipsHiddenFiles]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        ) else { return }

        let rootPath = rootURL.standardizedFileURL.path

        for url in contents {
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let absPath = url.standardizedFileURL.path
            var relPath = absPath
            if absPath.hasPrefix(rootPath) {
                relPath = String(absPath.dropFirst(rootPath.count))
                if relPath.hasPrefix("/") { relPath = String(relPath.dropFirst()) }
            }

            if let filter = filter {
                guard filter.shouldShow(name: name, relativePath: relPath, isDirectory: isDir) else { continue }
            } else {
                let hidden: Set<String> = [".git", ".build", ".DS_Store", ".swiftpm", "node_modules"]
                if hidden.contains(name) { continue }
            }

            if isDir {
                Self.indexFiles(at: url, rootURL: rootURL, filter: filter, into: &results)
            } else {
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
