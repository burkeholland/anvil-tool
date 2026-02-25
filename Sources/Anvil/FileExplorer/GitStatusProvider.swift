import SwiftUI

enum GitFileStatus: Equatable {
    case modified
    case added
    case deleted
    case untracked
    case renamed
    case conflicted

    var color: Color {
        switch self {
        case .modified:   return .orange
        case .added:      return .green
        case .deleted:    return .red
        case .untracked:  return .gray
        case .renamed:    return .blue
        case .conflicted: return .red
        }
    }

    var label: String {
        switch self {
        case .modified:   return "Modified"
        case .added:      return "Added"
        case .deleted:    return "Deleted"
        case .untracked:  return "Untracked"
        case .renamed:    return "Renamed"
        case .conflicted: return "Merge Conflict"
        }
    }
}

/// Parses `git status --porcelain` output into a map of absolute paths to statuses.
enum GitStatusProvider {

    /// Returns a map of absolute file paths to their git status for the given directory.
    static func status(for directory: URL) -> [String: GitFileStatus] {
        guard let gitRoot = findGitRoot(for: directory) else { return [:] }
        guard let output = runGitStatus(at: directory) else { return [:] }
        return parse(output: output, gitRoot: gitRoot)
    }

    /// Parse porcelain v1 output into status map. Exposed for testing.
    static func parse(output: String, gitRoot: URL) -> [String: GitFileStatus] {
        var statuses: [String: GitFileStatus] = [:]
        let gitRootPath = gitRoot.standardizedFileURL.path

        for line in output.components(separatedBy: "\n") where line.count >= 4 {
            let indexChar = line[line.startIndex]
            let worktreeChar = line[line.index(after: line.startIndex)]
            let pathStart = line.index(line.startIndex, offsetBy: 3)
            let relativePath = unquoteGitPath(String(line[pathStart...]))

            // Handle renamed files: "old -> new"
            let filePath: String
            if let arrowRange = relativePath.range(of: " -> ") {
                filePath = String(relativePath[arrowRange.upperBound...])
            } else {
                filePath = relativePath
            }

            let absolutePath = gitRoot.appendingPathComponent(filePath).standardizedFileURL.path

            let status: GitFileStatus
            switch (indexChar, worktreeChar) {
            case ("?", "?"): status = .untracked
            case ("U", _), (_, "U"): status = .conflicted
            case ("D", _), (_, "D"): status = .deleted
            case ("A", _):           status = .added
            case ("R", _):           status = .renamed
            default:                 status = .modified
            }

            statuses[absolutePath] = status

            // Propagate to parent directories so folders show change indicators
            var parentPath = (absolutePath as NSString).deletingLastPathComponent
            while parentPath.count > gitRootPath.count {
                if let existing = statuses[parentPath] {
                    statuses[parentPath] = higherPriority(existing, status)
                } else {
                    statuses[parentPath] = status
                }
                parentPath = (parentPath as NSString).deletingLastPathComponent
            }
        }

        return statuses
    }

    // MARK: - Private

    private static func runGitStatus(at directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--porcelain=v1"]
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    /// Strips C-style quoting that git uses for paths with spaces/special characters.
    private static func unquoteGitPath(_ path: String) -> String {
        guard path.hasPrefix("\"") && path.hasSuffix("\"") && path.count >= 2 else {
            return path
        }
        let inner = String(path.dropFirst().dropLast())
        var result = ""
        var i = inner.startIndex
        while i < inner.endIndex {
            if inner[i] == "\\" && inner.index(after: i) < inner.endIndex {
                let next = inner[inner.index(after: i)]
                switch next {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                default: result.append("\\"); result.append(next)
                }
                i = inner.index(i, offsetBy: 2)
            } else {
                result.append(inner[i])
                i = inner.index(after: i)
            }
        }
        return result
    }

    private static func findGitRoot(for directory: URL) -> URL? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--show-toplevel"]
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func higherPriority(_ a: GitFileStatus, _ b: GitFileStatus) -> GitFileStatus {
        func priority(_ s: GitFileStatus) -> Int {
            switch s {
            case .conflicted: return 6
            case .deleted:    return 5
            case .modified:   return 4
            case .added:      return 3
            case .renamed:    return 2
            case .untracked:  return 1
            }
        }
        return priority(a) >= priority(b) ? a : b
    }
}
