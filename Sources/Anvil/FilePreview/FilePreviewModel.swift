import Foundation
import AppKit
import Combine

enum PreviewTab {
    case source
    case changes
    case rendered
    case history
}

final class FilePreviewModel: ObservableObject {
    @Published private(set) var selectedURL: URL?
    @Published private(set) var openTabs: [URL] = []
    @Published private(set) var fileContent: String?
    @Published private(set) var fileDiff: FileDiff?
    @Published private(set) var isLoading = false
    @Published var activeTab: PreviewTab = .source
    @Published private(set) var lineCount: Int = 0
    /// Set this to scroll the source view to a specific line number (1-based).
    @Published var scrollToLine: Int?
    /// Tracks the last line navigated to, used as reference for next/previous change.
    var lastNavigatedLine: Int = 1
    /// Controls the Go to Line overlay in the file preview.
    @Published var showGoToLine = false
    /// Controls the symbol outline popover in the file preview.
    @Published var showSymbolOutline = false
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var imageSize: CGSize?
    @Published private(set) var imageFileSize: Int?
    /// Git commit history for the currently selected file.
    @Published private(set) var fileHistory: [GitCommit] = []
    /// When set, the preview shows a commit-specific diff instead of working directory diff.
    private(set) var commitDiffContext: (sha: String, filePath: String)?

    /// Recently viewed file URLs in most-recent-first order, capped at 20.
    @Published private(set) var recentlyViewedURLs: [URL] = []

    /// The root directory for running git commands.
    var rootDirectory: URL? {
        didSet {
            setupWatcher()
            loadRecentFiles()
        }
    }

    private var fileWatcher: FileWatcher?

    deinit {
        fileWatcher?.stop()
    }

    var fileName: String {
        selectedURL?.lastPathComponent ?? ""
    }

    var fileExtension: String {
        selectedURL?.pathExtension.lowercased() ?? ""
    }

    /// Whether the selected file is a markdown file.
    var isMarkdownFile: Bool {
        guard let ext = selectedURL?.pathExtension.lowercased() else { return false }
        return ext == "md" || ext == "markdown" || ext == "mdown" || ext == "mkd"
    }

    /// Whether the selected file is an image.
    var isImageFile: Bool {
        guard let ext = selectedURL?.pathExtension.lowercased() else { return false }
        return Self.imageExtensions.contains(ext)
    }

    /// Whether the selected file has git changes.
    var hasDiff: Bool {
        fileDiff != nil
    }

    /// Maps file extensions to highlight.js language identifiers.
    var highlightLanguage: String? {
        guard let ext = selectedURL?.pathExtension.lowercased() else { return nil }
        return Self.extensionToLanguage[ext]
    }

    func select(_ url: URL, line: Int? = nil) {
        guard !url.hasDirectoryPath else { return }
        let wasCommitDiff = commitDiffContext != nil
        commitDiffContext = nil
        showSymbolOutline = false
        // Track in recent files
        trackRecent(url)
        // Add to tabs if not already open
        if !openTabs.contains(url) {
            openTabs.append(url)
        }
        // Reload if switching away from a commit diff for the same file
        if selectedURL == url && !wasCommitDiff {
            // Even if already selected, navigate to the requested line
            if let line = line {
                activeTab = .source
                scrollToLine = line
                lastNavigatedLine = line
            }
            return
        }
        selectedURL = url
        lastNavigatedLine = line ?? 1
        fileHistory = []
        pendingScrollLine = line
        loadFile(url)
    }

    /// Line to scroll to after the file finishes loading.
    private var pendingScrollLine: Int?

    /// Open a file showing the diff from a specific commit.
    func selectCommitFile(path: String, commitSHA: String, rootURL: URL) {
        let url = URL(fileURLWithPath: rootURL.path).appendingPathComponent(path)
        commitDiffContext = (sha: commitSHA, filePath: path)
        if !openTabs.contains(url) {
            openTabs.append(url)
        }
        selectedURL = url
        lastNavigatedLine = 1
        loadCommitFile(url: url, sha: commitSHA, filePath: path, rootURL: rootURL)
    }

    func closeTab(_ url: URL) {
        guard let index = openTabs.firstIndex(of: url) else { return }
        openTabs.remove(at: index)

        if openTabs.isEmpty {
            close()
        } else if selectedURL == url {
            // Switch to adjacent tab
            let newIndex = min(index, openTabs.count - 1)
            selectedURL = openTabs[newIndex]
            lastNavigatedLine = 1
            loadFile(openTabs[newIndex])
        }
    }

    func close() {
        selectedURL = nil
        openTabs.removeAll()
        fileContent = nil
        fileDiff = nil
        lineCount = 0
        lastNavigatedLine = 1
        previewImage = nil
        imageSize = nil
        imageFileSize = nil
        fileHistory = []
        activeTab = .source
        commitDiffContext = nil
        showSymbolOutline = false
    }

    /// Refresh both source content and diff for the current file.
    /// Called automatically by the internal FileWatcher when files change on disk.
    func refresh() {
        guard let url = selectedURL, let root = rootDirectory else { return }
        let isImage = Self.imageExtensions.contains(url.pathExtension.lowercased())
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if isImage {
                let image = NSImage(contentsOf: url)
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attrs?[.size] as? Int
                let pixelSize = image?.representations.first.map {
                    CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
                }
                DispatchQueue.main.async {
                    guard self?.selectedURL == url else { return }
                    self?.previewImage = image
                    self?.imageSize = pixelSize
                    self?.imageFileSize = fileSize
                }
            } else {
                let content: String?
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int, size <= 1_048_576 {
                    content = try? String(contentsOf: url, encoding: .utf8)
                } else {
                    content = nil
                }
                let diff = DiffProvider.diff(for: url, in: root)
                DispatchQueue.main.async {
                    guard self?.selectedURL == url else { return }
                    if content != self?.fileContent {
                        self?.fileContent = content
                        self?.lineCount = content?.components(separatedBy: "\n").count ?? 0
                    }
                    self?.fileDiff = diff
                    // Reconcile active tab if current selection is no longer valid
                    if let current = self?.activeTab {
                        if current == .changes && diff == nil {
                            let isMD = Self.markdownExtensions.contains(url.pathExtension.lowercased())
                            self?.activeTab = isMD ? .rendered : .source
                        }
                    }
                }
            }
        }
    }

    private func loadCommitFile(url: URL, sha: String, filePath: String, rootURL: URL) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let diff = DiffProvider.commitFileDiff(sha: sha, filePath: filePath, in: rootURL)
            // Also try to load the current file content for source view
            let content: String?
            if FileManager.default.fileExists(atPath: url.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size <= 1_048_576 {
                content = try? String(contentsOf: url, encoding: .utf8)
            } else {
                content = nil
            }

            DispatchQueue.main.async {
                guard self?.selectedURL == url else { return }
                self?.fileContent = content
                self?.lineCount = content?.components(separatedBy: "\n").count ?? 0
                self?.fileDiff = diff
                self?.previewImage = nil
                self?.imageSize = nil
                self?.imageFileSize = nil
                self?.isLoading = false
                self?.activeTab = diff != nil ? .changes : .source
            }
        }
    }

    private func setupWatcher() {
        fileWatcher?.stop()
        fileWatcher = nil
        guard let root = rootDirectory else { return }
        fileWatcher = FileWatcher(directory: root) { [weak self] in
            self?.refresh()
        }
    }

    private func loadFile(_ url: URL) {
        isLoading = true
        let root = rootDirectory
        let isImage = Self.imageExtensions.contains(url.pathExtension.lowercased())
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if isImage {
                let image = NSImage(contentsOf: url)
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attrs?[.size] as? Int
                let pixelSize = image?.representations.first.map {
                    CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
                }
                DispatchQueue.main.async {
                    guard self?.selectedURL == url else { return }
                    self?.previewImage = image
                    self?.imageSize = pixelSize
                    self?.imageFileSize = fileSize
                    self?.fileContent = nil
                    self?.fileDiff = nil
                    self?.lineCount = 0
                    self?.isLoading = false
                    self?.activeTab = .source
                }
            } else {
                let content: String?
                // Skip large files (> 1 MB) and binary files
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int, size <= 1_048_576 {
                    content = try? String(contentsOf: url, encoding: .utf8)
                } else {
                    content = nil
                }
                let diff: FileDiff? = root.flatMap { DiffProvider.diff(for: url, in: $0) }
                DispatchQueue.main.async {
                    guard self?.selectedURL == url else { return }
                    self?.fileContent = content
                    self?.lineCount = content?.components(separatedBy: "\n").count ?? 0
                    self?.fileDiff = diff
                    self?.previewImage = nil
                    self?.imageSize = nil
                    self?.imageFileSize = nil
                    self?.isLoading = false
                    // Navigate to pending line (from search click), overriding tab auto-switch
                    if let line = self?.pendingScrollLine {
                        self?.pendingScrollLine = nil
                        self?.activeTab = .source
                        self?.scrollToLine = line
                        self?.lastNavigatedLine = line
                    } else if diff != nil {
                        self?.activeTab = .changes
                    } else if Self.markdownExtensions.contains(url.pathExtension.lowercased()) {
                        self?.activeTab = .rendered
                    } else {
                        self?.activeTab = .source
                    }
                    self?.loadFileHistory(for: url)
                }
            }
        }
    }

    /// Loads the git commit history for a specific file in the background.
    private func loadFileHistory(for url: URL) {
        guard let root = rootDirectory else {
            fileHistory = []
            return
        }
        let relativePath = Self.relativePath(of: url, from: root)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let commits = GitLogProvider.fileLog(path: relativePath, in: root)
            DispatchQueue.main.async {
                guard self?.selectedURL == url else { return }
                self?.fileHistory = commits
            }
        }
    }

    private static let extensionToLanguage: [String: String] = [
        "swift": "swift",
        "js": "javascript",
        "jsx": "javascript",
        "ts": "typescript",
        "tsx": "typescript",
        "py": "python",
        "rb": "ruby",
        "rs": "rust",
        "go": "go",
        "java": "java",
        "kt": "kotlin",
        "c": "c",
        "h": "c",
        "cpp": "cpp",
        "cc": "cpp",
        "cs": "csharp",
        "m": "objectivec",
        "mm": "objectivec",
        "sh": "bash",
        "bash": "bash",
        "zsh": "bash",
        "json": "json",
        "yaml": "yaml",
        "yml": "yaml",
        "toml": "ini",
        "xml": "xml",
        "html": "xml",
        "css": "css",
        "scss": "scss",
        "sql": "sql",
        "md": "markdown",
        "dockerfile": "dockerfile",
        "makefile": "makefile",
        "r": "r",
        "lua": "lua",
        "php": "php",
        "pl": "perl",
        "ex": "elixir",
        "exs": "elixir",
        "hs": "haskell",
        "scala": "scala",
        "dart": "dart",
        "vim": "vim",
    ]

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif",
        "webp", "heic", "heif", "ico", "icns", "svg",
    ]

    static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd",
    ]

    // MARK: - Change Region Navigation

    /// Returns contiguous groups of changed lines as sorted ranges (1-based line numbers).
    func changeRegions(from gutterChanges: [Int: GutterChangeKind]) -> [ClosedRange<Int>] {
        guard !gutterChanges.isEmpty else { return [] }
        let sorted = gutterChanges.keys.sorted()
        var regions: [ClosedRange<Int>] = []
        var start = sorted[0]
        var end = sorted[0]
        for i in 1..<sorted.count {
            if sorted[i] == end + 1 {
                end = sorted[i]
            } else {
                regions.append(start...end)
                start = sorted[i]
                end = sorted[i]
            }
        }
        regions.append(start...end)
        return regions
    }

    /// Scrolls to the next change region after the current navigation position.
    func goToNextChange(gutterChanges: [Int: GutterChangeKind]) {
        let regions = changeRegions(from: gutterChanges)
        guard !regions.isEmpty else { return }
        if let next = regions.first(where: { $0.lowerBound > lastNavigatedLine }) {
            scrollToLine = next.lowerBound
            lastNavigatedLine = next.lowerBound
        } else {
            // Wrap around to first region
            scrollToLine = regions[0].lowerBound
            lastNavigatedLine = regions[0].lowerBound
        }
    }

    /// Scrolls to the previous change region before the current navigation position.
    func goToPreviousChange(gutterChanges: [Int: GutterChangeKind]) {
        let regions = changeRegions(from: gutterChanges)
        guard !regions.isEmpty else { return }
        if let prev = regions.last(where: { $0.lowerBound < lastNavigatedLine }) {
            scrollToLine = prev.lowerBound
            lastNavigatedLine = prev.lowerBound
        } else {
            // Wrap around to last region
            scrollToLine = regions.last!.lowerBound
            lastNavigatedLine = regions.last!.lowerBound
        }
    }

    // MARK: - Path Helpers

    /// The relative path of the selected file from the root directory.
    var relativePath: String {
        guard let url = selectedURL, let root = rootDirectory else { return fileName }
        return Self.relativePath(of: url, from: root)
    }

    /// The directory components of the relative path (excluding filename).
    var relativeDirectoryComponents: [String] {
        let components = relativePath.components(separatedBy: "/")
        guard components.count > 1 else { return [] }
        return Array(components.dropLast())
    }

    /// Computes a disambiguated display name for a tab URL.
    /// Shows only the filename when unique, adds minimal parent path when names collide.
    func tabDisplayName(for url: URL) -> String {
        let name = url.lastPathComponent
        let duplicates = openTabs.filter { $0.lastPathComponent == name }
        guard duplicates.count > 1, let root = rootDirectory else { return name }

        let paths = duplicates.map { Self.relativePath(of: $0, from: root).components(separatedBy: "/") }
        let targetPath = Self.relativePath(of: url, from: root).components(separatedBy: "/")

        // Find minimum suffix depth that makes this tab unique
        for depth in 2...targetPath.count {
            let suffix = targetPath.suffix(depth).joined(separator: "/")
            let matches = paths.filter { $0.suffix(depth).joined(separator: "/") == suffix }
            if matches.count == 1 {
                return suffix
            }
        }

        return Self.relativePath(of: url, from: root)
    }

    static func relativePath(of url: URL, from root: URL) -> String {
        let filePath = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if filePath.hasPrefix(rootPath) {
            var rel = String(filePath.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
            return rel.isEmpty ? url.lastPathComponent : rel
        }
        return url.lastPathComponent
    }

    // MARK: - Recent Files

    private static let maxRecentFiles = 20

    private func trackRecent(_ url: URL) {
        let standardized = url.standardizedFileURL
        recentlyViewedURLs.removeAll { $0 == standardized }
        recentlyViewedURLs.insert(standardized, at: 0)
        if recentlyViewedURLs.count > Self.maxRecentFiles {
            recentlyViewedURLs = Array(recentlyViewedURLs.prefix(Self.maxRecentFiles))
        }
        saveRecentFiles()
    }

    private var recentFilesKey: String? {
        guard let root = rootDirectory else { return nil }
        return "dev.anvil.recentFiles.\(root.standardizedFileURL.path)"
    }

    private func saveRecentFiles() {
        guard let key = recentFilesKey else { return }
        let paths = recentlyViewedURLs.map(\.path)
        UserDefaults.standard.set(paths, forKey: key)
    }

    private func loadRecentFiles() {
        guard let key = recentFilesKey,
              let paths = UserDefaults.standard.stringArray(forKey: key) else {
            recentlyViewedURLs = []
            return
        }
        let fm = FileManager.default
        recentlyViewedURLs = paths.compactMap { path in
            fm.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
    }
}
