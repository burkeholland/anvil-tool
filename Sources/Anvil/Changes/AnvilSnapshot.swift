import Foundation

/// A lightweight pre-task snapshot of the working tree state,
/// created automatically when the Copilot agent starts modifying files.
struct AnvilSnapshot: Identifiable {
    let id: UUID
    let date: Date
    /// Human-readable label, e.g. "Pre-task snapshot".
    let label: String
    /// The HEAD commit SHA at snapshot time.
    let headSHA: String
    /// The SHA returned by `git stash create`, or nil if the working tree was clean.
    let stashSHA: String?

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
