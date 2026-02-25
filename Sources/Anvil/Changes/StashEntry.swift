import Foundation

/// A single git stash entry.
struct StashEntry: Identifiable {
    let index: Int
    let sha: String
    let message: String
    let date: Date
    /// Files changed in this stash, lazy-loaded on expand.
    var files: [CommitFile]?

    var id: String { sha }

    var displayName: String {
        "stash@{\(index)}"
    }

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// The user-facing message, stripping the "On branch: " prefix if present.
    var cleanMessage: String {
        // Git stash messages look like "On branch-name: message" or "WIP on branch: sha message"
        if let colonRange = message.range(of: ": ") {
            return String(message[colonRange.upperBound...])
        }
        return message
    }
}
