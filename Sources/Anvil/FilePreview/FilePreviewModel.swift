import Foundation
import AppKit
import Combine

enum PreviewTab {
    case source
    case changes
    case rendered
}

final class FilePreviewModel: ObservableObject {
    @Published private(set) var selectedURL: URL?
    @Published private(set) var openTabs: [URL] = []
    @Published private(set) var fileContent: String?
    @Published private(set) var fileDiff: FileDiff?
    @Published private(set) var isLoading = false
    @Published var activeTab: PreviewTab = .source
    @Published private(set) var lineCount: Int = 0
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var imageSize: CGSize?
    @Published private(set) var imageFileSize: Int?
    /// When set, the preview shows a commit-specific diff instead of working directory diff.
    private(set) var commitDiffContext: (sha: String, filePath: String)?

    /// The root directory for running git commands.
    var rootDirectory: URL? {
        didSet { setupWatcher() }
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

    func select(_ url: URL) {
        guard !url.hasDirectoryPath else { return }
        let wasCommitDiff = commitDiffContext != nil
        commitDiffContext = nil
        // Add to tabs if not already open
        if !openTabs.contains(url) {
            openTabs.append(url)
        }
        // Reload if switching away from a commit diff for the same file
        if selectedURL == url && !wasCommitDiff { return }
        selectedURL = url
        loadFile(url)
    }

    /// Open a file showing the diff from a specific commit.
    func selectCommitFile(path: String, commitSHA: String, rootURL: URL) {
        let url = URL(fileURLWithPath: rootURL.path).appendingPathComponent(path)
        commitDiffContext = (sha: commitSHA, filePath: path)
        if !openTabs.contains(url) {
            openTabs.append(url)
        }
        selectedURL = url
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
            loadFile(openTabs[newIndex])
        }
    }

    func close() {
        selectedURL = nil
        openTabs.removeAll()
        fileContent = nil
        fileDiff = nil
        lineCount = 0
        previewImage = nil
        imageSize = nil
        imageFileSize = nil
        activeTab = .source
        commitDiffContext = nil
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
                    // Auto-switch to changes tab if file has a diff, rendered for markdown
                    if diff != nil {
                        self?.activeTab = .changes
                    } else if Self.markdownExtensions.contains(url.pathExtension.lowercased()) {
                        self?.activeTab = .rendered
                    } else {
                        self?.activeTab = .source
                    }
                }
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

    private static func relativePath(of url: URL, from root: URL) -> String {
        let filePath = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if filePath.hasPrefix(rootPath) {
            var rel = String(filePath.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
            return rel.isEmpty ? url.lastPathComponent : rel
        }
        return url.lastPathComponent
    }
}
