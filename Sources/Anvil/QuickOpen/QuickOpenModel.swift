import Foundation
import Combine

/// Manages file indexing and fuzzy search for the Quick Open palette.
final class QuickOpenModel: ObservableObject {
    @Published var query: String = "" {
        didSet { performSearch() }
    }
    @Published private(set) var results: [QuickOpenResult] = []
    @Published var selectedIndex: Int = 0

    private var allFiles: [IndexedFile] = []
    private var rootURL: URL?
    private var indexGeneration: UInt64 = 0
    private var gitIgnoreFilter: GitIgnoreFilter?

    struct IndexedFile {
        let url: URL
        let name: String
        let nameLower: String
        let relativePath: String
        let relativePathLower: String
    }

    func index(rootURL: URL) {
        if rootURL == self.rootURL {
            performSearch()
            return
        }
        self.rootURL = rootURL
        let filter = GitIgnoreFilter(rootURL: rootURL)
        self.gitIgnoreFilter = filter
        indexGeneration &+= 1
        let generation = indexGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            filter.refresh()
            var files: [IndexedFile] = []
            Self.indexFiles(at: rootURL, rootURL: rootURL, filter: filter, into: &files)
            DispatchQueue.main.async {
                guard let self = self, self.indexGeneration == generation else { return }
                self.allFiles = files
                self.performSearch()
            }
        }
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }

    func reset() {
        query = ""
        selectedIndex = 0
        results = []
    }

    var selectedResult: QuickOpenResult? {
        guard selectedIndex >= 0 && selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    // MARK: - Fuzzy Search

    private func performSearch() {
        selectedIndex = 0
        guard !query.isEmpty else {
            // Show recent/all files when query is empty (capped)
            results = allFiles.prefix(50).map {
                QuickOpenResult(url: $0.url, name: $0.name, relativePath: $0.relativePath, score: 0)
            }
            return
        }

        let queryLower = query.lowercased()
        var scored: [(IndexedFile, Int)] = []

        for file in allFiles {
            if let score = fuzzyScore(query: queryLower, target: file.nameLower, original: file.name) {
                // Boost if path also matches
                let pathBoost = file.relativePathLower.contains(queryLower) ? 20 : 0
                scored.append((file, score + pathBoost))
            } else if file.relativePathLower.contains(queryLower) {
                // Substring match on full path as fallback
                scored.append((file, 10))
            }
        }

        scored.sort { $0.1 > $1.1 }

        results = scored.prefix(50).map {
            QuickOpenResult(url: $0.0.url, name: $0.0.name, relativePath: $0.0.relativePath, score: $0.1)
        }
    }

    /// Scores a fuzzy match of query characters against a target string.
    /// Returns nil if no match. Higher scores = better match.
    private func fuzzyScore(query: String, target: String, original: String) -> Int? {
        guard !query.isEmpty else { return 0 }

        var score = 0
        var queryIndex = query.startIndex
        var targetIndex = target.startIndex
        var lastMatchIndex: String.Index?
        var consecutiveMatches = 0

        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            if query[queryIndex] == target[targetIndex] {
                score += 1

                // Bonus for consecutive matches
                if let last = lastMatchIndex, target.index(after: last) == targetIndex {
                    consecutiveMatches += 1
                    score += consecutiveMatches * 3
                } else {
                    consecutiveMatches = 0
                }

                // Bonus for matching at word boundaries (after /, ., -, _)
                if targetIndex == target.startIndex {
                    score += 10
                } else {
                    let prev = target[target.index(before: targetIndex)]
                    if prev == "/" || prev == "." || prev == "-" || prev == "_" {
                        score += 8
                    }
                    // Bonus for matching uppercase in camelCase
                    let origIndex = original.index(original.startIndex, offsetBy: target.distance(from: target.startIndex, to: targetIndex))
                    if original[origIndex].isUppercase {
                        score += 5
                    }
                }

                lastMatchIndex = targetIndex
                queryIndex = query.index(after: queryIndex)
            }
            targetIndex = target.index(after: targetIndex)
        }

        // All query characters must be found
        guard queryIndex == query.endIndex else { return nil }

        // Bonus for shorter filenames (more precise match)
        score += max(0, 30 - target.count)

        return score
    }

    // MARK: - File Indexing

    private static func indexFiles(at directory: URL, rootURL: URL, filter: GitIgnoreFilter?, into results: inout [IndexedFile]) {
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
                let hidden: Set<String> = [
                    ".git", ".build", ".DS_Store", ".swiftpm", "node_modules",
                    ".Trash", "DerivedData", "xcuserdata"
                ]
                if hidden.contains(name) { continue }
            }

            if isDir {
                indexFiles(at: url, rootURL: rootURL, filter: filter, into: &results)
            } else {
                results.append(IndexedFile(
                    url: url,
                    name: name,
                    nameLower: name.lowercased(),
                    relativePath: relPath,
                    relativePathLower: relPath.lowercased()
                ))
            }
        }
    }
}

/// A single result in the Quick Open list.
struct QuickOpenResult: Identifiable {
    let url: URL
    let name: String
    let relativePath: String
    let score: Int

    var id: URL { url }

    var directoryPath: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }
}
