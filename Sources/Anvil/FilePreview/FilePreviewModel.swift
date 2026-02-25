import Foundation
import Combine

final class FilePreviewModel: ObservableObject {
    @Published private(set) var selectedURL: URL?
    @Published private(set) var fileContent: String?
    @Published private(set) var isLoading = false

    var fileName: String {
        selectedURL?.lastPathComponent ?? ""
    }

    var fileExtension: String {
        selectedURL?.pathExtension.lowercased() ?? ""
    }

    /// Maps file extensions to highlight.js language identifiers.
    var highlightLanguage: String? {
        guard let ext = selectedURL?.pathExtension.lowercased() else { return nil }
        return Self.extensionToLanguage[ext]
    }

    func select(_ url: URL) {
        guard !url.hasDirectoryPath else { return }
        if selectedURL == url {
            close()
            return
        }
        selectedURL = url
        loadFile(url)
    }

    func close() {
        selectedURL = nil
        fileContent = nil
    }

    private func loadFile(_ url: URL) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let content: String?
            // Skip large files (> 1 MB) and binary files
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size <= 1_048_576 {
                content = try? String(contentsOf: url, encoding: .utf8)
            } else {
                content = nil
            }
            DispatchQueue.main.async {
                guard self?.selectedURL == url else { return }
                self?.fileContent = content
                self?.isLoading = false
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
