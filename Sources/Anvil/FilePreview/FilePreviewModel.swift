import Foundation
import Combine

enum PreviewTab {
    case source
    case changes
}

final class FilePreviewModel: ObservableObject {
    @Published private(set) var selectedURL: URL?
    @Published private(set) var openTabs: [URL] = []
    @Published private(set) var fileContent: String?
    @Published private(set) var fileDiff: FileDiff?
    @Published private(set) var isLoading = false
    @Published var activeTab: PreviewTab = .source
    @Published private(set) var lineCount: Int = 0

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
        // Add to tabs if not already open
        if !openTabs.contains(url) {
            openTabs.append(url)
        }
        if selectedURL == url { return }
        selectedURL = url
        loadFile(url)
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
        activeTab = .source
    }

    /// Refresh both source content and diff for the current file.
    /// Called automatically by the internal FileWatcher when files change on disk.
    func refresh() {
        guard let url = selectedURL, let root = rootDirectory else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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
                self?.isLoading = false
                // Auto-switch to changes tab if file has a diff
                if diff != nil {
                    self?.activeTab = .changes
                } else {
                    self?.activeTab = .source
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
}
