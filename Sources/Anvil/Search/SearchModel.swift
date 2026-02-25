import Foundation
import Combine

/// A single match within a file.
struct SearchMatch: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let lineContent: String
    let matchRange: Range<String.Index>?
}

/// All matches within a single file.
struct SearchFileResult: Identifiable {
    let url: URL
    let relativePath: String
    let matches: [SearchMatch]

    var id: URL { url }
    var fileName: String { url.lastPathComponent }

    var directoryPath: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }
}

/// Drives project-wide text search using `git grep` (with `grep -rn` fallback).
/// Results are debounced and grouped by file for display in the sidebar.
final class SearchModel: ObservableObject {
    @Published var query: String = ""
    @Published var caseSensitive: Bool = false
    @Published private(set) var results: [SearchFileResult] = []
    @Published private(set) var totalMatches: Int = 0
    @Published private(set) var isSearching = false

    private var rootURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var searchGeneration: UInt64 = 0
    private let workQueue = DispatchQueue(label: "dev.anvil.search", qos: .userInitiated)
    /// Cap results to prevent UI stalls on broad queries.
    private let maxResults = 1000

    init() {
        // Debounce query changes — wait 300ms after the user stops typing
        Publishers.CombineLatest($query, $caseSensitive)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query, caseSensitive in
                self?.performSearch(query: query, caseSensitive: caseSensitive)
            }
            .store(in: &cancellables)
    }

    func setRoot(_ url: URL) {
        rootURL = url
        if !query.isEmpty {
            performSearch(query: query, caseSensitive: caseSensitive)
        }
    }

    func clear() {
        query = ""
        results = []
        totalMatches = 0
    }

    // MARK: - Search Execution

    private func performSearch(query: String, caseSensitive: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let rootURL = rootURL else {
            results = []
            totalMatches = 0
            isSearching = false
            return
        }

        isSearching = true
        searchGeneration &+= 1
        let generation = searchGeneration
        let maxResults = self.maxResults

        workQueue.async { [weak self] in
            let isGitRepo = FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent(".git").path
            )

            let output: String?
            if isGitRepo {
                output = Self.runGitGrep(query: trimmed, caseSensitive: caseSensitive, at: rootURL, maxResults: maxResults)
            } else {
                output = Self.runGrep(query: trimmed, caseSensitive: caseSensitive, at: rootURL, maxResults: maxResults)
            }

            let parsed = Self.parseGrepOutput(output ?? "", rootURL: rootURL)

            DispatchQueue.main.async {
                guard let self = self, self.searchGeneration == generation else { return }
                self.results = parsed
                self.totalMatches = parsed.reduce(0) { $0 + $1.matches.count }
                self.isSearching = false
            }
        }
    }

    // MARK: - git grep

    private static func runGitGrep(query: String, caseSensitive: Bool, at directory: URL, maxResults: Int) -> String? {
        var args = ["grep", "-n", "--color=never", "-I", "--max-count=50"]
        if !caseSensitive {
            args.append("-i")
        }
        args.append("--fixed-strings")
        args.append(query)

        return runProcess(
            executable: "/usr/bin/git",
            arguments: args,
            at: directory
        )
    }

    // MARK: - grep fallback

    private static func runGrep(query: String, caseSensitive: Bool, at directory: URL, maxResults: Int) -> String? {
        var args = ["-rn", "--color=never", "-I", "--include=*"]
        if !caseSensitive {
            args.append("-i")
        }
        // Exclude common noisy directories
        args.append(contentsOf: [
            "--exclude-dir=.git", "--exclude-dir=.build",
            "--exclude-dir=node_modules", "--exclude-dir=.swiftpm",
        ])
        args.append("--fixed-strings")
        args.append(query)
        args.append(".")

        return runProcess(
            executable: "/usr/bin/grep",
            arguments: args,
            at: directory
        )
    }

    // MARK: - Output Parsing

    /// Parses `file:line:content` output from git grep / grep into grouped results.
    private static func parseGrepOutput(_ output: String, rootURL: URL) -> [SearchFileResult] {
        guard !output.isEmpty else { return [] }

        var fileMap: [String: [SearchMatch]] = [:]
        var fileOrder: [String] = []

        for line in output.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }

            // Format: relativePath:lineNumber:content
            guard let firstColon = line.firstIndex(of: ":") else { continue }
            let relativePath = String(line[line.startIndex..<firstColon])

            let afterFirst = line.index(after: firstColon)
            guard afterFirst < line.endIndex,
                  let secondColon = line[afterFirst...].firstIndex(of: ":") else { continue }

            let lineNumStr = String(line[afterFirst..<secondColon])
            guard let lineNumber = Int(lineNumStr) else { continue }

            let contentStart = line.index(after: secondColon)
            let content = contentStart < line.endIndex ? String(line[contentStart...]) : ""

            let match = SearchMatch(
                lineNumber: lineNumber,
                lineContent: content,
                matchRange: nil
            )

            if fileMap[relativePath] == nil {
                fileOrder.append(relativePath)
            }
            fileMap[relativePath, default: []].append(match)
        }

        let rootPath = rootURL.standardizedFileURL.path
        return fileOrder.map { relPath in
            let absPath = relPath.hasPrefix("/") ? relPath : rootPath + "/" + relPath
            return SearchFileResult(
                url: URL(fileURLWithPath: absPath),
                relativePath: relPath,
                matches: fileMap[relPath] ?? []
            )
        }
    }

    private static func runProcess(executable: String, arguments: [String], at directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Read stdout BEFORE waitUntilExit to avoid deadlock when pipe buffer fills
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: data, encoding: .utf8)
    }
}
