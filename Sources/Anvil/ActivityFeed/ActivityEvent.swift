import Foundation

/// A single event in the activity feed — a file change or git commit observed while the agent works.
struct ActivityEvent: Identifiable {
    enum Kind: Equatable {
        case fileCreated
        case fileModified
        case fileDeleted
        case fileRenamed(from: String)
        case gitCommit(message: String, sha: String)
    }

    let id: UUID
    let timestamp: Date
    let kind: Kind
    /// Relative path from the project root (e.g. "Sources/Anvil/ContentView.swift").
    let path: String
    /// Absolute URL for opening preview. Nil for deleted files.
    let fileURL: URL?

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
        }
    }

    var iconColor: String {
        switch kind {
        case .fileCreated:  return "green"
        case .fileModified: return "orange"
        case .fileDeleted:  return "red"
        case .fileRenamed:  return "blue"
        case .gitCommit:    return "purple"
        }
    }

    var label: String {
        switch kind {
        case .fileCreated:          return "Created"
        case .fileModified:         return "Modified"
        case .fileDeleted:          return "Deleted"
        case .fileRenamed(let old): return "Renamed from \(old)"
        case .gitCommit(let msg, _): return msg
        }
    }
}

/// Groups events that happened close together (within a few seconds), so rapid
/// saves or multi-file writes appear as a single batch in the timeline.
struct ActivityGroup: Identifiable {
    let id: UUID
    let timestamp: Date
    let events: [ActivityEvent]

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
        }
    }
}
