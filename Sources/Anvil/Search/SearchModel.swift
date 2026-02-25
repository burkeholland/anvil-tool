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
    @Published var wholeWord: Bool = false
    @Published var fileFilter: String = ""
    @Published private(set) var results: [SearchFileResult] = []
    @Published private(set) var totalMatches: Int = 0
    @Published private(set) var isSearching = false
    /// Non-nil when the regex pattern is invalid; displayed in the UI.
    @Published private(set) var regexError: String?

    // MARK: - Replace

    @Published var replaceText: String = ""
    @Published var showReplace: Bool = false
    /// True while a replacement operation is in progress.
    @Published private(set) var isReplacing = false
    /// Summary of the last replacement operation.
    @Published var lastReplaceResult: ReplaceResult?

    struct ReplaceResult: Equatable {
        let filesChanged: Int
        let replacementsCount: Int
    }

    private var rootURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var searchGeneration: UInt64 = 0
    private let workQueue = DispatchQueue(label: "dev.anvil.search", qos: .userInitiated)
    /// Cap results to prevent UI stalls on broad queries.
    private let maxResults = 1000

    init() {
        // Debounce query changes — wait 300ms after the user stops typing
        Publishers.CombineLatest(
            Publishers.CombineLatest3($query, $caseSensitive, $useRegex),
            Publishers.CombineLatest($wholeWord, $fileFilter)
        )
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] first, second in
                let (query, caseSensitive, useRegex) = first
                let (wholeWord, fileFilter) = second
                self?.performSearch(query: query, caseSensitive: caseSensitive, useRegex: useRegex, wholeWord: wholeWord, fileFilter: fileFilter)
            }
            .store(in: &cancellables)
    }

    func setRoot(_ url: URL) {
        rootURL = url
        results = []
        totalMatches = 0
        lastReplaceResult = nil
        if !query.isEmpty {
            performSearch(query: query, caseSensitive: caseSensitive, useRegex: useRegex, wholeWord: wholeWord, fileFilter: fileFilter)
        }
    }

    func clear() {
        query = ""
        fileFilter = ""
        replaceText = ""
        results = []
        totalMatches = 0
        regexError = nil
        lastReplaceResult = nil
    }

    // MARK: - Replace

    /// Replace all occurrences of the search query in a single file.
    func replaceInFile(_ fileResult: SearchFileResult) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let rootURL = rootURL else { return }
        // Safety: verify the file is under the current project root
        guard fileResult.url.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path) else { return }
        isReplacing = true
        let r = replaceText
        let cs = caseSensitive
        let regex = useRegex
        let ww = wholeWord
        workQueue.async { [weak self] in
            let count = Self.performReplace(
                in: fileResult.url, query: trimmed, replacement: r,
                caseSensitive: cs, useRegex: regex, wholeWord: ww
            )
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isReplacing = false
                if count > 0 {
                    self.lastReplaceResult = ReplaceResult(filesChanged: 1, replacementsCount: count)
                    self.refreshSearch()
                }
            }
        }
    }

    /// Replace all occurrences of the search query across all result files.
    func replaceAll() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let rootURL = rootURL else { return }
        let rootPath = rootURL.standardizedFileURL.path
        let files = results.filter { $0.url.standardizedFileURL.path.hasPrefix(rootPath) }
        isReplacing = true
        let r = replaceText
        let cs = caseSensitive
        let regex = useRegex
        let ww = wholeWord
        workQueue.async { [weak self] in
            var totalCount = 0
            var filesChanged = 0
            for fileResult in files {
                let count = Self.performReplace(
                    in: fileResult.url, query: trimmed, replacement: r,
                    caseSensitive: cs, useRegex: regex, wholeWord: ww
                )
                if count > 0 {
                    totalCount += count
                    filesChanged += 1
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isReplacing = false
                if totalCount > 0 {
                    self.lastReplaceResult = ReplaceResult(filesChanged: filesChanged, replacementsCount: totalCount)
                    self.refreshSearch()
                }
            }
        }
    }

    /// Perform text replacement in a file, returning the number of replacements made.
    static func performReplace(
        in url: URL, query: String, replacement: String,
        caseSensitive: Bool, useRegex: Bool, wholeWord: Bool
    ) -> Int {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return 0
        }

        let (newContent, count) = applyReplacement(
            content: content, query: query, replacement: replacement,
            caseSensitive: caseSensitive, useRegex: useRegex, wholeWord: wholeWord
        )

        guard count > 0, newContent != content else { return 0 }

        do {
            try newContent.write(to: url, atomically: true, encoding: .utf8)
            return count
        } catch {
            return 0
        }
    }

    /// Pure function: apply replacements to a string, returning the new string and count.
    static func applyReplacement(
        content: String, query: String, replacement: String,
        caseSensitive: Bool, useRegex: Bool, wholeWord: Bool
    ) -> (String, Int) {
        if useRegex {
            let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: query, options: options) else {
                return (content, 0)
            }
            let nsRange = NSRange(content.startIndex..., in: content)
            let count = regex.numberOfMatches(in: content, range: nsRange)
            guard count > 0 else { return (content, 0) }
            let result = regex.stringByReplacingMatches(in: content, range: nsRange, withTemplate: replacement)
            return (result, count)
        }

        // Build a pattern for fixed-string matching
        let escaped = NSRegularExpression.escapedPattern(for: query)
        var pattern = escaped
        if wholeWord {
            pattern = "\\b\(pattern)\\b"
        }
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return (content, 0)
        }
        let nsRange = NSRange(content.startIndex..., in: content)
        let count = regex.numberOfMatches(in: content, range: nsRange)
        guard count > 0 else { return (content, 0) }
        let escaped_replacement = NSRegularExpression.escapedTemplate(for: replacement)
        let result = regex.stringByReplacingMatches(in: content, range: nsRange, withTemplate: escaped_replacement)
        return (result, count)
    }

    /// Re-run the current search to refresh results after a replacement.
    func refreshSearch() {
        performSearch(query: query, caseSensitive: caseSensitive, useRegex: useRegex, wholeWord: wholeWord, fileFilter: fileFilter)
    }

    // MARK: - Search Execution

    private func performSearch(query: String, caseSensitive: Bool, useRegex: Bool, wholeWord: Bool, fileFilter: String) {
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
        let trimmedFilter = fileFilter.trimmingCharacters(in: .whitespaces)

        workQueue.async { [weak self] in
            let isGitRepo = FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent(".git").path
            )

            let result: ProcessResult
            if isGitRepo {
                result = Self.runGitGrep(query: trimmed, caseSensitive: caseSensitive, useRegex: useRegex, wholeWord: wholeWord, fileFilter: trimmedFilter, at: rootURL, maxResults: maxResults)
            } else {
                result = Self.runGrep(query: trimmed, caseSensitive: caseSensitive, useRegex: useRegex, wholeWord: wholeWord, fileFilter: trimmedFilter, at: rootURL, maxResults: maxResults)
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

    private static func runGitGrep(query: String, caseSensitive: Bool, useRegex: Bool, wholeWord: Bool, fileFilter: String, at directory: URL, maxResults: Int) -> ProcessResult {
        var args = ["grep", "-n", "--color=never", "-I", "--max-count=50"]
        if !caseSensitive {
            args.append("-i")
        }
        if wholeWord {
            args.append("-w")
        }
        if useRegex {
            args.append("-E")
        } else {
            args.append("--fixed-strings")
        }
        args.append(query)

        // Path filter: supports glob patterns like "*.swift" or "src/"
        if !fileFilter.isEmpty {
            args.append("--")
            for pattern in fileFilter.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !pattern.isEmpty {
                args.append(pattern)
            }
        }

        return runProcess(
            executable: "/usr/bin/git",
            arguments: args,
            at: directory
        )
    }

    // MARK: - grep fallback

    private static func runGrep(query: String, caseSensitive: Bool, useRegex: Bool, wholeWord: Bool, fileFilter: String, at directory: URL, maxResults: Int) -> ProcessResult {
        var args = ["-rn", "--color=never", "-I"]
        if !caseSensitive {
            args.append("-i")
        }
        if wholeWord {
            args.append("-w")
        }
        // Exclude common noisy directories
        args.append(contentsOf: [
            "--exclude-dir=.git", "--exclude-dir=.build",
            "--exclude-dir=node_modules", "--exclude-dir=.swiftpm",
        ])
        // File include patterns: glob patterns go to --include, directory paths become search roots
        var searchPaths: [String] = []
        if !fileFilter.isEmpty {
            for pattern in fileFilter.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !pattern.isEmpty {
                if pattern.hasSuffix("/") || !pattern.contains("*") && !pattern.contains(".") {
                    // Directory path — use as positional search root
                    searchPaths.append(pattern)
                } else {
                    args.append("--include=\(pattern)")
                }
            }
        }
        if useRegex {
            args.append("-E")
        } else {
            args.append("--fixed-strings")
        }
        args.append(query)
        args.append(contentsOf: searchPaths.isEmpty ? ["."] : searchPaths)

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
