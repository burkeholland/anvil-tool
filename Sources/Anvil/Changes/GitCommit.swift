import Foundation

/// A single git commit for the history view.
struct GitCommit: Identifiable {
    let sha: String
    let shortSHA: String
    let message: String
    let author: String
    let date: Date
    /// Files changed in this commit with their stats.
    var files: [CommitFile]?

    var id: String { sha }

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// A file changed in a commit.
struct CommitFile: Identifiable {
    let path: String
    let additions: Int
    let deletions: Int
    let status: String // "M", "A", "D", "R"

    var id: String { path }

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var directoryPath: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    var statusColor: String {
        switch status {
        case "A": return "green"
        case "D": return "red"
        case "R": return "blue"
        default:  return "orange"
        }
    }
}
