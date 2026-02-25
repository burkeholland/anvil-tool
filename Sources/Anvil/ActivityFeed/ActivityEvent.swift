import Foundation

/// Line-level diff statistics for a single file change.
struct DiffStats: Equatable {
    let additions: Int
    let deletions: Int

    var total: Int { additions + deletions }
    var isEmpty: Bool { additions == 0 && deletions == 0 }
}

/// A single event in the activity feed — a file change, git commit, or agent terminal action.
struct ActivityEvent: Identifiable {
    enum Kind: Equatable {
        case fileCreated
        case fileModified
        case fileDeleted
        case fileRenamed(from: String)
        case gitCommit(message: String, sha: String)
        /// A shell command the agent executed, e.g. `git diff HEAD`.
        case commandRun(command: String)
        /// A file the agent read from disk.
        case fileRead(path: String)
        /// An agent status transition, e.g. "Thinking…" or "✓ Done".
        case agentStatus(status: String)
    }

    let id: UUID
    let timestamp: Date
    let kind: Kind
    /// Relative path from the project root (e.g. "Sources/Anvil/ContentView.swift").
    let path: String
    /// Absolute URL for opening preview. Nil for deleted files.
    let fileURL: URL?
    /// Line-level diff statistics (only for fileModified/fileCreated events).
    var diffStats: DiffStats?

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var directoryPath: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    var icon: String {
        switch kind {
        case .fileCreated:  return "plus.circle.fill"
        case .fileModified: return "pencil.circle.fill"
        case .fileDeleted:  return "minus.circle.fill"
        case .fileRenamed:  return "arrow.right.circle.fill"
        case .gitCommit:    return "arrow.triangle.branch"
        case .commandRun:   return "terminal"
        case .fileRead:     return "eye"
        case .agentStatus:  return "circle.fill"
        }
    }

    var iconColor: String {
        switch kind {
        case .fileCreated:  return "green"
        case .fileModified: return "orange"
        case .fileDeleted:  return "red"
        case .fileRenamed:  return "blue"
        case .gitCommit:    return "purple"
        case .commandRun:   return "cyan"
        case .fileRead:     return "teal"
        case .agentStatus:  return "mint"
        }
    }

    var label: String {
        switch kind {
        case .fileCreated:              return "Created"
        case .fileModified:             return "Modified"
        case .fileDeleted:              return "Deleted"
        case .fileRenamed(let old):     return "Renamed from \(old)"
        case .gitCommit(let msg, _):    return msg
        case .commandRun(let command):  return command
        case .fileRead(let path):       return path
        case .agentStatus(let status):  return status
        }
    }
}

/// Groups events that happened close together (within a few seconds), so rapid
/// saves or multi-file writes appear as a single batch in the timeline.
struct ActivityGroup: Identifiable {
    let id: UUID
    let timestamp: Date
    let events: [ActivityEvent]

    /// Aggregate diff stats across all events in this group.
    var aggregateStats: DiffStats {
        let adds = events.compactMap(\.diffStats).reduce(0) { $0 + $1.additions }
        let dels = events.compactMap(\.diffStats).reduce(0) { $0 + $1.deletions }
        return DiffStats(additions: adds, deletions: dels)
    }

    var summary: String {
        if events.count == 1 {
            return events[0].label
        }
        let kinds = Set(events.map { kindName($0.kind) })
        if kinds.count == 1, let kind = kinds.first {
            return "\(events.count) files \(kind)"
        }
        return "\(events.count) file changes"
    }

    private func kindName(_ kind: ActivityEvent.Kind) -> String {
        switch kind {
        case .fileCreated:  return "created"
        case .fileModified: return "modified"
        case .fileDeleted:  return "deleted"
        case .fileRenamed:  return "renamed"
        case .gitCommit:    return "committed"
        case .commandRun:   return "run"
        case .fileRead:     return "read"
        case .agentStatus:  return "status"
        }
    }
}
