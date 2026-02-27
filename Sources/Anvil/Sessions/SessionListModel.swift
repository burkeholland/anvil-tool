import Foundation
import Combine

/// Scans `~/.copilot/session-state/` for Copilot CLI sessions, parses each
/// `workspace.yaml`, filters by the current project, and groups by date.
///
/// Auto-refreshes when new sessions appear using FSEvents (via `FileWatcher`).
final class SessionListModel: ObservableObject {
    /// Sessions filtered to the current project, sorted newest-first.
    @Published private(set) var sessions: [SessionItem] = []
    /// Sessions grouped by date bucket for display.
    @Published private(set) var groups: [(group: SessionDateGroup, items: [SessionItem])] = []

    /// Set to filter sessions by the current project directory path.
    var projectCWD: String? {
        didSet { if oldValue != projectCWD { applyFilter() } }
    }
    /// Set to filter sessions by the current project's `owner/repo` string.
    var projectRepository: String? {
        didSet { if oldValue != projectRepository { applyFilter() } }
    }

    /// Called when the user taps a session row to resume it in a terminal tab.
    var onOpenSession: ((String) -> Void)?
    /// Called when the user taps the "+" button to start a new Copilot session.
    var onNewSession: (() -> Void)?

    // MARK: - Deletion

    /// Removes the session directory at `~/.copilot/session-state/<id>/` and rescans.
    func deleteSession(id: String) {
        let dir = sessionStateURL.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: dir)
        scanSessions()
    }

    private var allSessions: [SessionItem] = []
    private var watcher: FileWatcher?
    private var pollTimer: Timer?
    let sessionStateURL: URL

    init(sessionStateURL: URL? = nil) {
        self.sessionStateURL = sessionStateURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".copilot/session-state")
    }

    // ISO 8601 formatter with fractional seconds (matches CLI output).
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // Fallback formatter without fractional seconds.
    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // Relative date formatter for the "Session from X ago" last-resort fallback.
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    deinit {
        stop()
    }

    /// Begins watching the session-state directory and loads existing sessions.
    func start() {
        scanSessions()
        startWatching()
    }

    /// Stops watching and clears all state.
    func stop() {
        watcher?.stop()
        watcher = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Scanning

    private func startWatching() {
        watcher?.stop()
        let dir = sessionStateURL
        let fm = FileManager.default

        // Create the directory if it doesn't exist yet so FSEvents can watch it.
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        if fm.fileExists(atPath: dir.path) {
            watcher = FileWatcher(directory: dir) { [weak self] in
                self?.scanSessions()
            }
        }

        // Always set up a 5-second poll as a safety net (handles newly-created
        // session-state directories and environments where FSEvents may lag).
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.scanSessions()
        }
    }

    private func scanSessions() {
        let baseURL = sessionStateURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            guard let subdirs = try? fm.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                DispatchQueue.main.async { self.allSessions = []; self.applyFilter() }
                return
            }

            var parsed: [SessionItem] = []
            for dir in subdirs {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let yamlURL = dir.appendingPathComponent("workspace.yaml")
                guard let contents = try? String(contentsOf: yamlURL, encoding: .utf8) else { continue }
                if let item = Self.parseWorkspaceYAML(contents, id: dir.lastPathComponent) {
                    parsed.append(item)
                }
            }

            // Sort newest-first by updatedAt.
            parsed.sort { $0.updatedAt > $1.updatedAt }

            DispatchQueue.main.async {
                self.allSessions = parsed
                self.applyFilter()
            }
        }
    }

    // MARK: - Filtering & Grouping

    private func applyFilter() {
        let cwd = projectCWD
        let repo = projectRepository

        let filtered: [SessionItem]
        if cwd == nil && repo == nil {
            filtered = allSessions
        } else {
            filtered = allSessions.filter { item in
                if let cwd = cwd, item.cwd == cwd { return true }
                if let repo = repo, let itemRepo = item.repository, itemRepo == repo { return true }
                return false
            }
        }

        sessions = filtered
        groups = buildGroups(filtered)
    }

    private func buildGroups(_ items: [SessionItem]) -> [(group: SessionDateGroup, items: [SessionItem])] {
        var buckets: [SessionDateGroup: [SessionItem]] = [:]
        for item in items {
            let g = SessionDateGroup.group(for: item.updatedAt)
            buckets[g, default: []].append(item)
        }
        // Return in canonical order, omitting empty buckets.
        return SessionDateGroup.allCases.compactMap { g in
            guard let bucket = buckets[g], !bucket.isEmpty else { return nil }
            return (group: g, items: bucket)
        }
    }

    // MARK: - YAML Parsing

    /// Parses a minimal `workspace.yaml` into a `SessionItem`.
    /// The file uses simple `key: value` lines — no third-party YAML library required.
    static func parseWorkspaceYAML(_ yaml: String, id: String) -> SessionItem? {
        var dict: [String: String] = [:]
        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIdx])
                .trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes (YAML scalar strings)
            let value = rawValue.hasPrefix("\"") && rawValue.hasSuffix("\"") && rawValue.count >= 2
                ? String(rawValue.dropFirst().dropLast())
                : rawValue
            dict[key] = value
        }

        guard
            let cwd = dict["cwd"], !cwd.isEmpty,
            let createdStr = dict["created_at"],
            let updatedStr = dict["updated_at"],
            let createdAt = parseDate(createdStr),
            let updatedAt = parseDate(updatedStr)
        else { return nil }

        let rawSummary = dict["summary"] ?? ""
        let branch = dict["branch"]?.isEmpty == false ? dict["branch"] : nil
        let isFallbackSummary = rawSummary.isEmpty
        let summary: String
        if rawSummary.isEmpty {
            if let b = branch {
                // Priority 1: branch name
                summary = b
            } else {
                // Priority 2: last path component of CWD (project folder name)
                let lastComponent = URL(fileURLWithPath: cwd).lastPathComponent
                if !lastComponent.isEmpty && lastComponent != "/" {
                    summary = lastComponent
                } else {
                    // Priority 3: relative creation time as last resort
                    summary = "Session from \(Self.relativeDateFormatter.localizedString(for: createdAt, relativeTo: Date()))"
                }
            }
        } else {
            summary = rawSummary
        }
        return SessionItem(
            id: id,
            cwd: cwd,
            summary: summary,
            isFallbackSummary: isFallbackSummary,
            repository: dict["repository"]?.isEmpty == false ? dict["repository"] : nil,
            branch: branch,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        if let d = isoFormatter.date(from: string) { return d }
        return isoFormatterNoFraction.date(from: string)
    }
}
