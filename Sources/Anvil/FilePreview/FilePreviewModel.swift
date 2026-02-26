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
    @Published private(set) var stagedFileDiff: FileDiff?
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
    /// When set, the preview shows a stash-entry diff instead of working directory diff.
    private(set) var stashDiffContext: (stashIndex: Int, filePath: String)?
    /// Per-line blame annotations for the current file.
    @Published private(set) var blameLines: [BlameLine] = []
    /// Whether blame annotations are shown in the source view gutter.
    @Published var showBlame = false
    /// Monotonic counter to discard stale async blame results.
    private var blameGeneration: UInt64 = 0
    /// The commit SHA selected via a blame annotation click; drives History tab scrolling.
    @Published var selectedHistoryCommitSHA: String?
    /// When true, the source view auto-scrolls to changed lines on every file-system update.
    @Published var isWatching = false
    /// The file content as of the last watch refresh, used to find the first changed line.
    private var watchPreviousContent: String?
    /// The URL of the test/implementation counterpart for the current file, if one exists on disk.
    @Published private(set) var testFileCounterpart: URL?

    /// Recently viewed file URLs in most-recent-first order, capped at 20.
    @Published private(set) var recentlyViewedURLs: [URL] = []

    /// The root directory for running git commands.
    var rootDirectory: URL? {
        didSet {
            setupWatcher()
            loadRecentFiles()
            restoreOpenTabs()
        }
    }

    /// When set, diffs are computed relative to this commit SHA instead of HEAD.
    /// Set by ContentView when the Changes panel baseline selector changes.
    var diffBaselineSHA: String?

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

    /// Maximum number of concurrently open tabs. Oldest (least-recently-used) tabs are
    /// evicted when the limit is exceeded.
    private static let maxOpenTabs = 12

    func select(_ url: URL, line: Int? = nil) {
        guard !url.hasDirectoryPath else { return }
        let wasCommitDiff = commitDiffContext != nil || stashDiffContext != nil
        commitDiffContext = nil
        stashDiffContext = nil
        showSymbolOutline = false
        // Track in recent files
        trackRecent(url)
        // Add to tabs if not already open
        if !openTabs.contains(url) {
            openTabs.append(url)
            evictLRUTabIfNeeded(keeping: url)
            saveOpenTabs()
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
        // Clear stale blame immediately when switching files
        blameLines = []
        blameGeneration &+= 1
        selectedURL = url
        lastNavigatedLine = line ?? 1
        fileHistory = []
        pendingScrollLine = line
        saveOpenTabs()
        loadFile(url)
        loadTestFileCounterpart(for: url)
    }

    /// Switches the preview to the given file as part of auto-follow mode.
    /// If the file is already displayed, refreshes it and switches to the Changes tab
    /// so the latest diff is visible. If it is a different file, behaves like select().
    func autoFollowChange(to url: URL) {
        guard !url.hasDirectoryPath else { return }
        if selectedURL == url && commitDiffContext == nil {
            // Same file already open — refresh the diff and show the Changes tab
            refresh()
            activeTab = .changes
        } else {
            select(url)
        }
    }

    /// Line to scroll to after the file finishes loading.
    private var pendingScrollLine: Int?

    /// Open a file showing the diff from a specific commit.
    func selectCommitFile(path: String, commitSHA: String, rootURL: URL) {
        let url = URL(fileURLWithPath: rootURL.path).appendingPathComponent(path)
        commitDiffContext = (sha: commitSHA, filePath: path)
        stashDiffContext = nil
        // Blame is not meaningful for commit diffs
        blameLines = []
        blameGeneration &+= 1
        if !openTabs.contains(url) {
            openTabs.append(url)
            evictLRUTabIfNeeded(keeping: url)
            saveOpenTabs()
        }
        selectedURL = url
        lastNavigatedLine = 1
        loadCommitFile(url: url, sha: commitSHA, filePath: path, rootURL: rootURL)
    }

    /// Open a file showing the diff from a specific stash entry.
    func selectStashFile(path: String, stashIndex: Int, rootURL: URL) {
        let url = URL(fileURLWithPath: rootURL.path).appendingPathComponent(path)
        stashDiffContext = (stashIndex: stashIndex, filePath: path)
        commitDiffContext = nil
        blameLines = []
        blameGeneration &+= 1
        if !openTabs.contains(url) {
            openTabs.append(url)
            saveOpenTabs()
        }
        selectedURL = url
        lastNavigatedLine = 1
        loadStashFile(url: url, stashIndex: stashIndex, filePath: path, rootURL: rootURL)
    }

    func closeTab(_ url: URL) {
        guard let index = openTabs.firstIndex(of: url) else { return }
        openTabs.remove(at: index)

        if openTabs.isEmpty {
            saveOpenTabs()
            close(persist: false)
        } else if selectedURL == url {
            // Switch to adjacent tab
            let newIndex = min(index, openTabs.count - 1)
            selectedURL = openTabs[newIndex]
            lastNavigatedLine = 1
            saveOpenTabs()
            loadFile(openTabs[newIndex])
        } else {
            saveOpenTabs()
        }
    }

    /// Resets all preview state.
    /// - Parameter persist: When false, skip saving tabs (used during project switch
    ///   so the old project's persisted tabs aren't overwritten).
    func close(persist: Bool = true) {
        selectedURL = nil
        openTabs.removeAll()
        fileContent = nil
        fileDiff = nil
        stagedFileDiff = nil
        lineCount = 0
        lastNavigatedLine = 1
        previewImage = nil
        imageSize = nil
        imageFileSize = nil
        fileHistory = []
        blameLines = []
        activeTab = .source
        commitDiffContext = nil
        stashDiffContext = nil
        showSymbolOutline = false
        showBlame = false
        selectedHistoryCommitSHA = nil
        isWatching = false
        watchPreviousContent = nil
        testFileCounterpart = nil
        if persist { saveOpenTabs() }
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
                let diff = DiffProvider.diff(for: url, in: root, baselineSHA: self?.diffBaselineSHA)
                let staged = DiffProvider.stagedDiff(for: url, in: root)
                DispatchQueue.main.async {
                    guard self?.selectedURL == url else { return }
                    if content != self?.fileContent {
                        // Auto-scroll to first changed line when watching
                        if self?.isWatching == true, let previous = self?.watchPreviousContent {
                            if let changedLine = self?.firstChangedLine(old: previous, new: content) {
                                self?.activeTab = .source
                                self?.scrollToLine = changedLine
                                self?.lastNavigatedLine = changedLine
                            }
                        }
                        self?.watchPreviousContent = content
                        self?.fileContent = content
                        self?.lineCount = content?.components(separatedBy: "\n").count ?? 0
                    }
                    self?.fileDiff = diff
                    self?.stagedFileDiff = staged
                    // Reconcile active tab if current selection is no longer valid
                    if let current = self?.activeTab {
                        if current == .changes && diff == nil {
                            let isMD = Self.markdownExtensions.contains(url.pathExtension.lowercased())
                            self?.activeTab = isMD ? .rendered : .source
                        }
                    }
                    // Refresh blame if active (file content may have changed on disk)
                    if self?.showBlame == true {
                        self?.loadBlame()
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
                self?.stagedFileDiff = nil
                self?.previewImage = nil
                self?.imageSize = nil
                self?.imageFileSize = nil
                self?.isLoading = false
                self?.activeTab = diff != nil ? .changes : .source
            }
        }
    }

    private func loadStashFile(url: URL, stashIndex: Int, filePath: String, rootURL: URL) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let diff = DiffProvider.stashFileDiff(stashIndex: stashIndex, filePath: filePath, in: rootURL)
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
                self?.stagedFileDiff = nil
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
                let diff: FileDiff? = root.flatMap { DiffProvider.diff(for: url, in: $0, baselineSHA: self?.diffBaselineSHA) }
                let staged: FileDiff? = root.flatMap { DiffProvider.stagedDiff(for: url, in: $0) }
                DispatchQueue.main.async {
                    guard self?.selectedURL == url else { return }
                    self?.fileContent = content
                    self?.lineCount = content?.components(separatedBy: "\n").count ?? 0
                    self?.fileDiff = diff
                    self?.stagedFileDiff = staged
                    self?.previewImage = nil
                    self?.imageSize = nil
                    self?.imageFileSize = nil
                    self?.isLoading = false
                    // Reset watch baseline for the newly loaded file
                    self?.watchPreviousContent = content
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
                    if self?.showBlame == true {
                        self?.loadBlame()
                    }
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

    /// Loads git blame for the current file if blame mode is active.
    func loadBlame() {
        blameGeneration &+= 1
        let generation = blameGeneration
        guard showBlame, let url = selectedURL, let root = rootDirectory else {
            blameLines = []
            return
        }
        let relativePath = Self.relativePath(of: url, from: root)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let blame = GitBlameProvider.blame(for: relativePath, in: root)
            DispatchQueue.main.async {
                guard let self,
                      self.blameGeneration == generation,
                      self.selectedURL == url,
                      self.showBlame else { return }
                self.blameLines = blame
            }
        }
    }

    /// Clears blame annotations.
    func clearBlame() {
        blameGeneration &+= 1
        blameLines = []
    }

    /// Searches the project tree in the background for the test/implementation counterpart
    /// of `url` and publishes the result to `testFileCounterpart`.
    private func loadTestFileCounterpart(for url: URL) {
        guard let root = rootDirectory else {
            testFileCounterpart = nil
            return
        }
        testFileCounterpart = nil
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let counterpart = TestFileMatcher.counterpart(for: url, in: root)
            DispatchQueue.main.async {
                guard self?.selectedURL == url else { return }
                self?.testFileCounterpart = counterpart
            }
        }
    }

    /// Switches to the History tab and highlights the commit matching the given full SHA.
    /// Uncommitted lines (SHA starts with "0000000") are ignored.
    func navigateToBlameCommit(sha: String) {
        guard !sha.hasPrefix("0000000") else { return }
        selectedHistoryCommitSHA = sha
        activeTab = .history
    }

    /// Returns the first 1-based line number where old and new content differ.
    private func firstChangedLine(old: String?, new: String?) -> Int? {
        guard let new = new, !new.isEmpty else { return nil }
        let oldLines = (old ?? "").components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        for (i, newLine) in newLines.enumerated() {
            if i >= oldLines.count || newLine != oldLines[i] {
                return i + 1
            }
        }
        // Lines were only removed from the end — scroll to the new last line
        if oldLines.count > newLines.count {
            return newLines.count
        }
        return nil
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

    // MARK: - Tab Cycling

    /// Switches to the next tab, wrapping around.
    func selectNextTab() {
        guard openTabs.count > 1, let current = selectedURL,
              let idx = openTabs.firstIndex(of: current) else { return }
        let next = openTabs[(idx + 1) % openTabs.count]
        select(next)
    }

    /// Switches to the previous tab, wrapping around.
    func selectPreviousTab() {
        guard openTabs.count > 1, let current = selectedURL,
              let idx = openTabs.firstIndex(of: current) else { return }
        let prev = openTabs[(idx - 1 + openTabs.count) % openTabs.count]
        select(prev)
    }

    /// Evicts the least-recently-used tab when the open tab count exceeds `maxOpenTabs`.
    /// The `keeping` URL is never evicted (it is the file just opened).
    private func evictLRUTabIfNeeded(keeping url: URL) {
        guard openTabs.count > Self.maxOpenTabs else { return }
        // recentlyViewedURLs is most-recent-first; scan from the end to find the LRU tab
        var evicted = false
        for i in recentlyViewedURLs.indices.reversed() {
            let candidate = recentlyViewedURLs[i]
            if candidate != url, let idx = openTabs.firstIndex(of: candidate) {
                openTabs.remove(at: idx)
                evicted = true
                break
            }
        }
        // Fallback: evict the first tab that isn't the current one
        if !evicted {
            if let idx = openTabs.firstIndex(where: { $0 != url }) {
                openTabs.remove(at: idx)
            }
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

    // MARK: - Open Tabs Persistence

    private var openTabsKey: String? {
        guard let root = rootDirectory else { return nil }
        return "dev.anvil.openTabs.\(root.standardizedFileURL.path)"
    }

    private var selectedTabKey: String? {
        guard let root = rootDirectory else { return nil }
        return "dev.anvil.selectedTab.\(root.standardizedFileURL.path)"
    }

    private func saveOpenTabs() {
        guard let tabsKey = openTabsKey, let selKey = selectedTabKey else { return }
        let paths = openTabs.map(\.path)
        UserDefaults.standard.set(paths, forKey: tabsKey)
        UserDefaults.standard.set(selectedURL?.path, forKey: selKey)
    }

    private func restoreOpenTabs() {
        guard let tabsKey = openTabsKey,
              let paths = UserDefaults.standard.stringArray(forKey: tabsKey),
              !paths.isEmpty else { return }
        let fm = FileManager.default
        let validURLs = paths.compactMap { path -> URL? in
            fm.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        guard !validURLs.isEmpty else { return }
        openTabs = validURLs

        // Restore the previously selected file, or fall back to the last tab
        let selKey = selectedTabKey
        let restoredSelection: URL
        if let selPath = selKey.flatMap({ UserDefaults.standard.string(forKey: $0) }),
           let selURL = validURLs.first(where: { $0.path == selPath }) {
            restoredSelection = selURL
        } else {
            restoredSelection = validURLs.last!
        }
        selectedURL = restoredSelection
        lastNavigatedLine = 1
        loadFile(restoredSelection)
        loadTestFileCounterpart(for: restoredSelection)
    }
}
