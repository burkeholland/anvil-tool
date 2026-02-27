import Foundation

/// A parsed Copilot CLI session read from `~/.copilot/session-state/<UUID>/workspace.yaml`.
struct SessionItem: Identifiable, Equatable {
    let id: String
    let cwd: String
    let summary: String
    let repository: String?
    let branch: String?
    let createdAt: Date
    let updatedAt: Date
}

/// Date-based grouping for the session list.
enum SessionDateGroup: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case earlier = "Earlier"

    static func group(for date: Date, relativeTo now: Date = Date()) -> SessionDateGroup {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
           date > weekAgo { return .thisWeek }
        return .earlier
    }
}
