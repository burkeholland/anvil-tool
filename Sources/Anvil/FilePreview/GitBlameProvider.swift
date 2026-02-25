import Foundation

/// A single blame annotation for one line of a file.
struct BlameLine: Equatable {
    let sha: String
    let shortSHA: String
    let author: String
    let date: Date
    let summary: String
    /// 1-based line number in the current file.
    let lineNumber: Int

    /// True when this line comes from the working tree (uncommitted).
    var isUncommitted: Bool {
        sha.hasPrefix("0000000")
    }

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Runs `git blame --porcelain` and parses the output into per-line annotations.
enum GitBlameProvider {

    /// Returns one `BlameLine` per source line, or an empty array on failure.
    static func blame(for relativePath: String, in directory: URL) -> [BlameLine] {
        guard let output = runGit(
            args: ["blame", "--porcelain", "--", relativePath],
            at: directory
        ), !output.isEmpty else {
            return []
        }
        return parsePorcelain(output)
    }

    // MARK: - Porcelain Parser

    /// Parses `git blame --porcelain` output.
    ///
    /// Format per group:
    /// ```
    /// <sha> <orig-line> <final-line> [<group-lines>]
    /// author <name>
    /// author-mail <email>
    /// author-time <epoch>
    /// author-tz <tz>
    /// committer <name>
    /// ...
    /// summary <message>
    /// [previous <sha> <path>]
    /// [boundary]
    /// filename <path>
    /// \t<line-content>
    /// ```
    /// Subsequent lines in the same group only have the short header
    /// `<sha> <orig-line> <final-line>` followed by `\t<content>`.
    static func parsePorcelain(_ output: String) -> [BlameLine] {
        var results: [BlameLine] = []
        // Cache of commit metadata keyed by full SHA
        var commitCache: [String: (author: String, date: Date, summary: String)] = [:]

        let lines = output.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Header line: "<sha> <orig-line> <final-line> [<count>]"
            let parts = line.split(separator: " ", maxSplits: 3)
            guard parts.count >= 3,
                  parts[0].count >= 7,
                  let _ = Int(parts[1]),
                  let finalLine = Int(parts[2]) else {
                i += 1
                continue
            }

            let sha = String(parts[0])
            let isNewCommit = commitCache[sha] == nil

            if isNewCommit {
                // Parse metadata lines until we hit the tab-prefixed content line
                var author = ""
                var epoch: TimeInterval = 0
                var summary = ""
                i += 1

                while i < lines.count && !lines[i].hasPrefix("\t") {
                    let metaLine = lines[i]
                    if metaLine.hasPrefix("author ") {
                        author = String(metaLine.dropFirst("author ".count))
                    } else if metaLine.hasPrefix("author-time ") {
                        let timeStr = String(metaLine.dropFirst("author-time ".count))
                        epoch = TimeInterval(timeStr) ?? 0
                    } else if metaLine.hasPrefix("summary ") {
                        summary = String(metaLine.dropFirst("summary ".count))
                    }
                    i += 1
                }

                let date = epoch > 0 ? Date(timeIntervalSince1970: epoch) : Date.distantPast
                commitCache[sha] = (author: author, date: date, summary: summary)
            } else {
                // Skip to the content line
                i += 1
                while i < lines.count && !lines[i].hasPrefix("\t") {
                    i += 1
                }
            }

            // We should now be at the "\t<content>" line — skip past it
            if i < lines.count && lines[i].hasPrefix("\t") {
                i += 1
            }

            if let meta = commitCache[sha] {
                results.append(BlameLine(
                    sha: sha,
                    shortSHA: String(sha.prefix(8)),
                    author: meta.author,
                    date: meta.date,
                    summary: meta.summary,
                    lineNumber: finalLine
                ))
            }
        }

        return results
    }

    // MARK: - Private

    private static func runGit(args: [String], at directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
