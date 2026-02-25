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
    @Published var useRegex: Bool = false
    @Published private(set) var results: [SearchFileResult] = []
    @Published private(set) var totalMatches: Int = 0
    @Published private(set) var isSearching = false
    /// Non-nil when the regex pattern is invalid; displayed in the UI.
    @Published private(set) var regexError: String?

    private var rootURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var searchGeneration: UInt64 = 0
    private let workQueue = DispatchQueue(label: "dev.anvil.search", qos: .userInitiated)
    /// Cap results to prevent UI stalls on broad queries.
    private let maxResults = 1000

    init() {
        // Debounce query changes — wait 300ms after the user stops typing
        Publishers.CombineLatest3($query, $caseSensitive, $useRegex)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query, caseSensitive, useRegex in
                self?.performSearch(query: query, caseSensitive: caseSensitive, useRegex: useRegex)
            }
            .store(in: &cancellables)
    }

    func setRoot(_ url: URL) {
        rootURL = url
        if !query.isEmpty {
            performSearch(query: query, caseSensitive: caseSensitive, useRegex: useRegex)
        }
    }

    func clear() {
        query = ""
        results = []
        totalMatches = 0
        regexError = nil
    }

    // MARK: - Search Execution

    private func performSearch(query: String, caseSensitive: Bool, useRegex: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        searchGeneration &+= 1
        let generation = searchGeneration

        guard !trimmed.isEmpty, let rootURL = rootURL else {
            results = []
            totalMatches = 0
            isSearching = false
            regexError = nil
            return
        }

        regexError = nil
        isSearching = true
        let maxResults = self.maxResults

        workQueue.async { [weak self] in
            let isGitRepo = FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent(".git").path
            )

            let result: ProcessResult
            if isGitRepo {
                result = Self.runGitGrep(query: trimmed, caseSensitive: caseSensitive, useRegex: useRegex, at: rootURL, maxResults: maxResults)
            } else {
                result = Self.runGrep(query: trimmed, caseSensitive: caseSensitive, useRegex: useRegex, at: rootURL, maxResults: maxResults)
            }

            let parsed = Self.parseGrepOutput(result.stdout ?? "", rootURL: rootURL)

            // Surface regex errors from grep/git-grep stderr
            let errorMsg: String?
            if useRegex, let stderr = result.stderr, !stderr.isEmpty, result.exitCode != 0 && result.exitCode != 1 {
                errorMsg = stderr.components(separatedBy: "\n").first
            } else {
                errorMsg = nil
            }

            DispatchQueue.main.async {
                guard let self = self, self.searchGeneration == generation else { return }
                self.regexError = errorMsg
                self.results = errorMsg != nil ? [] : parsed
                self.totalMatches = errorMsg != nil ? 0 : parsed.reduce(0) { $0 + $1.matches.count }
                self.isSearching = false
            }
        }
    }

    // MARK: - git grep

    private static func runGitGrep(query: String, caseSensitive: Bool, useRegex: Bool, at directory: URL, maxResults: Int) -> ProcessResult {
        var args = ["grep", "-n", "--color=never", "-I", "--max-count=50"]
        if !caseSensitive {
            args.append("-i")
        }
        if useRegex {
            args.append("-E")
        } else {
            args.append("--fixed-strings")
        }
        args.append(query)

        return runProcess(
            executable: "/usr/bin/git",
            arguments: args,
            at: directory
        )
    }

    // MARK: - grep fallback

    private static func runGrep(query: String, caseSensitive: Bool, useRegex: Bool, at directory: URL, maxResults: Int) -> ProcessResult {
        var args = ["-rn", "--color=never", "-I", "--include=*"]
        if !caseSensitive {
            args.append("-i")
        }
        // Exclude common noisy directories
        args.append(contentsOf: [
            "--exclude-dir=.git", "--exclude-dir=.build",
            "--exclude-dir=node_modules", "--exclude-dir=.swiftpm",
        ])
        if useRegex {
            args.append("-E")
        } else {
            args.append("--fixed-strings")
        }
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

    /// Result of running a subprocess, capturing stdout, stderr, and exit code.
    private struct ProcessResult {
        let stdout: String?
        let stderr: String?
        let exitCode: Int32
    }

    private static func runProcess(executable: String, arguments: [String], at directory: URL) -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ProcessResult(stdout: nil, stderr: error.localizedDescription, exitCode: -1)
        }

        // Read stdout and stderr BEFORE waitUntilExit to avoid deadlock when pipe buffer fills
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            stdout: String(data: stdoutData, encoding: .utf8),
            stderr: String(data: stderrData, encoding: .utf8),
            exitCode: process.terminationStatus
        )
    }
}
