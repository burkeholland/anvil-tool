import Foundation
import Combine

/// Monitors the project directory for file changes and git commits,
/// building a live timeline of activity events.
/// Identifies the most recent file change for auto-follow.
struct LatestFileChange: Equatable {
    let id: UUID
    let url: URL
}

final class ActivityFeedModel: ObservableObject {
    @Published private(set) var groups: [ActivityGroup] = []
    @Published private(set) var events: [ActivityEvent] = []
    /// The most recently changed file (non-deleted). Each mutation has a unique id
    /// so `.onChange` fires even when the same file changes again.
    @Published private(set) var latestFileChange: LatestFileChange?
    /// Aggregate session stats, updated as events arrive.
    @Published private(set) var sessionStats = SessionStats()
    /// True when file changes were detected within the last 10 seconds.
    @Published private(set) var isAgentActive = false
    /// Active file-tree pulse tokens keyed by absolute path.
    /// Updated on every file create/modify event so views can animate a flash.
    /// Parent directory paths are also included (same mechanism) so collapsed
    /// folders still convey activity. Cleared when isAgentActive → false.
    @Published private(set) var activePulses: [String: UUID] = [:]
    /// Timestamp of the last detected activity event.
    private(set) var lastActivityTime: Date?
    /// Timer that clears the active state after a quiet period.
    private var activityCooldownTimer: Timer?

    /// Tracks aggregate statistics for the current activity session.
    struct SessionStats {
        var startTime: Date?
        var totalAdditions: Int = 0
        var totalDeletions: Int = 0
        var filesCreated: Int = 0
        var filesModified: Int = 0
        var filesDeleted: Int = 0
        var commitCount: Int = 0
        /// Baseline numstat captured at session start, subtracted from current.
        var baselineNumstat: [String: DiffStats] = [:]
        /// Latest full numstat snapshot from `git diff --numstat HEAD`.
        var currentNumstat: [String: DiffStats] = [:]

        var totalFilesTouched: Int { filesCreated + filesModified + filesDeleted }
        var isActive: Bool { startTime != nil && totalFilesTouched > 0 }

        /// Recompute totals as (current - baseline) per path, floored at 0.
        mutating func recomputeTotals() {
            var adds = 0
            var dels = 0
            for (path, current) in currentNumstat {
                let base = baselineNumstat[path] ?? DiffStats(additions: 0, deletions: 0)
                adds += max(current.additions - base.additions, 0)
                dels += max(current.deletions - base.deletions, 0)
            }
            totalAdditions = adds
            totalDeletions = dels
        }
    }

    private var rootURL: URL?
    private var fileWatcher: FileWatcher?
    /// Snapshot of file modification dates taken after each scan.
    private var knownFiles: [String: Date] = [:]
    /// Last known HEAD commit SHA, used to detect new commits.
    private var lastHeadSHA: String?
    /// Timer for periodic git log polling.
    private var gitPollTimer: Timer?
    /// Serial queue for all snapshot/diff/git work to prevent races.
    private let workQueue = DispatchQueue(label: "dev.anvil.activity-feed", qos: .userInitiated)
    /// Grouping window — events within this interval are batched together.
    private let groupingInterval: TimeInterval = 2.0
    /// Maximum events to retain.
    private let maxEvents = 500

    deinit {
        fileWatcher?.stop()
        gitPollTimer?.invalidate()
        activityCooldownTimer?.invalidate()
    }

    func start(rootURL: URL) {
        self.rootURL = rootURL
        events.removeAll()
        groups.removeAll()
        sessionStats = SessionStats(startTime: Date())

        // Take initial snapshot so we only report *changes*, not the initial state
        takeSnapshot(rootURL: rootURL)
        lastHeadSHA = currentHeadSHA(at: rootURL)

        // Capture baseline numstat so pre-existing dirty changes aren't counted
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let baseline = self.runNumstat(at: rootURL)
            DispatchQueue.main.async {
                self.sessionStats.baselineNumstat = baseline
            }
        }

        // Watch for file system events
        fileWatcher?.stop()
        fileWatcher = FileWatcher(directory: rootURL) { [weak self] in
            self?.onFileSystemChange()
        }

        // Poll git HEAD every 3 seconds to detect commits
        gitPollTimer?.invalidate()
        gitPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkForNewCommits()
        }
    }

    func stop() {
        fileWatcher?.stop()
        fileWatcher = nil
        gitPollTimer?.invalidate()
        gitPollTimer = nil
        activityCooldownTimer?.invalidate()
        activityCooldownTimer = nil
        rootURL = nil
        knownFiles = [:]
        lastHeadSHA = nil
        events.removeAll()
        groups.removeAll()
        latestFileChange = nil
        isAgentActive = false
        activePulses = [:]
        lastActivityTime = nil
        sessionStats = SessionStats()
    }

    func clear() {
        events.removeAll()
        groups.removeAll()
        sessionStats = SessionStats(startTime: sessionStats.startTime)
    }

    // MARK: - File System Change Detection

    private func onFileSystemChange() {
        guard let rootURL = rootURL else { return }

        workQueue.async { [weak self] in
            guard let self = self else { return }
            let newSnapshot = Self.scanFiles(rootURL: rootURL)
            var detectedEvents = self.diffSnapshots(old: self.knownFiles, new: newSnapshot, rootURL: rootURL)
            self.knownFiles = newSnapshot

            if !detectedEvents.isEmpty {
                // Enrich modification/creation events with diff stats
                let numStats = self.runNumstat(at: rootURL)
                for i in 0..<detectedEvents.count {
                    let event = detectedEvents[i]
                    guard event.kind == .fileModified || event.kind == .fileCreated,
                          !event.path.isEmpty else { continue }
                    if let stats = numStats[event.path] {
                        detectedEvents[i].diffStats = stats
                    }
                }

                DispatchQueue.main.async {
                    self.appendEvents(detectedEvents, latestNumstat: numStats)
                }
            }
        }
    }

    private func diffSnapshots(old: [String: Date], new: [String: Date], rootURL: URL) -> [ActivityEvent] {
        var events: [ActivityEvent] = []
        let now = Date()
        let rootPath = rootURL.standardizedFileURL.path

        // Created or modified
        for (path, newDate) in new {
            if let oldDate = old[path] {
                if newDate > oldDate {
                    let relPath = Self.relativePath(path, root: rootPath)
                    events.append(ActivityEvent(
                        id: UUID(), timestamp: newDate, kind: .fileModified,
                        path: relPath, fileURL: URL(fileURLWithPath: path)
                    ))
                }
            } else {
                let relPath = Self.relativePath(path, root: rootPath)
                events.append(ActivityEvent(
                    id: UUID(), timestamp: newDate, kind: .fileCreated,
                    path: relPath, fileURL: URL(fileURLWithPath: path)
                ))
            }
        }

        // Deleted
        for path in old.keys where new[path] == nil {
            let relPath = Self.relativePath(path, root: rootPath)
            events.append(ActivityEvent(
                id: UUID(), timestamp: now, kind: .fileDeleted,
                path: relPath, fileURL: nil
            ))
        }

        return events
    }

    // MARK: - Git Commit Detection

    private func checkForNewCommits() {
        guard let rootURL = rootURL else { return }

        workQueue.async { [weak self] in
            guard let self = self else { return }
            guard let newSHA = self.currentHeadSHA(at: rootURL) else { return }
            guard newSHA != self.lastHeadSHA else { return }

            let message = self.commitMessage(sha: newSHA, at: rootURL) ?? "New commit"
            self.lastHeadSHA = newSHA

            let event = ActivityEvent(
                id: UUID(), timestamp: Date(),
                kind: .gitCommit(message: message, sha: String(newSHA.prefix(8))),
                path: "", fileURL: nil
            )

            // Recompute numstat after commit (HEAD moved, so diff vs HEAD changes)
            let numStats = self.runNumstat(at: rootURL)

            DispatchQueue.main.async {
                self.appendEvents([event], latestNumstat: numStats)
            }
        }
    }

    private func currentHeadSHA(at directory: URL) -> String? {
        runGit(args: ["rev-parse", "HEAD"], at: directory)
    }

    private func commitMessage(sha: String, at directory: URL) -> String? {
        runGit(args: ["log", "-1", "--format=%s", sha], at: directory)
    }

    // MARK: - Helpers

    private func appendEvents(_ newEvents: [ActivityEvent], latestNumstat: [String: DiffStats]) {
        events.append(contentsOf: newEvents)
        // Trim if needed
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        rebuildGroups()

        // Update session stats with event counts
        for event in newEvents {
            switch event.kind {
            case .fileCreated:
                sessionStats.filesCreated += 1
            case .fileModified:
                sessionStats.filesModified += 1
            case .fileDeleted:
                sessionStats.filesDeleted += 1
            case .fileRenamed:
                sessionStats.filesModified += 1
            case .gitCommit:
                sessionStats.commitCount += 1
            }
        }

        // Replace numstat snapshot (authoritative) and recompute totals.
        // Full replacement ensures reverted files drop out of the tally.
        if !latestNumstat.isEmpty {
            sessionStats.currentNumstat = latestNumstat
            sessionStats.recomputeTotals()
        } else {
            // Empty snapshot (e.g. after commit clears all diffs)
            sessionStats.currentNumstat = [:]
            sessionStats.recomputeTotals()
        }

        // Publish the most recently modified file for auto-follow
        if let latest = newEvents
            .filter({ $0.fileURL != nil && $0.kind != .fileDeleted })
            .max(by: { $0.timestamp < $1.timestamp }) {
            latestFileChange = LatestFileChange(id: UUID(), url: latest.fileURL!)
        }

        // Update file-tree pulse tokens for create/modify events
        if let rootURL = rootURL {
            let rootPath = rootURL.standardizedFileURL.path
            for event in newEvents {
                guard (event.kind == .fileCreated || event.kind == .fileModified),
                      let fileURL = event.fileURL else { continue }
                let absPath = fileURL.standardizedFileURL.path
                activePulses[absPath] = UUID()
                // Propagate a pulse token to every ancestor directory up to (not
                // including) the root so that collapsed folders still flash.
                var dir = fileURL.deletingLastPathComponent().standardizedFileURL
                while dir.path.hasPrefix(rootPath + "/") {
                    activePulses[dir.path] = UUID()
                    let parent = dir.deletingLastPathComponent().standardizedFileURL
                    if parent.path == dir.path { break }
                    dir = parent
                }
            }
        }

        // Mark agent as active and schedule cooldown
        lastActivityTime = Date()
        isAgentActive = true
        activityCooldownTimer?.invalidate()
        activityCooldownTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.isAgentActive = false
            self?.activePulses = [:]
        }
    }

    private func rebuildGroups() {
        guard !events.isEmpty else {
            groups = []
            return
        }

        var result: [ActivityGroup] = []
        var currentBatch: [ActivityEvent] = [events[0]]

        for i in 1..<events.count {
            let event = events[i]
            let lastInBatch = currentBatch.last!
            if event.timestamp.timeIntervalSince(lastInBatch.timestamp) <= groupingInterval {
                currentBatch.append(event)
            } else {
                result.append(ActivityGroup(
                    id: currentBatch[0].id,
                    timestamp: currentBatch[0].timestamp,
                    events: currentBatch
                ))
                currentBatch = [event]
            }
        }
        // Flush last batch
        result.append(ActivityGroup(
            id: currentBatch[0].id,
            timestamp: currentBatch[0].timestamp,
            events: currentBatch
        ))

        groups = result
    }

    private func takeSnapshot(rootURL: URL) {
        knownFiles = Self.scanFiles(rootURL: rootURL)
    }

    /// Scans all non-hidden files under the root and returns [absolutePath: modificationDate].
    private static func scanFiles(rootURL: URL) -> [String: Date] {
        var result: [String: Date] = [:]
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return result
        }

        for case let url as URL in enumerator {
            // Skip .build and other noisy directories
            let name = url.lastPathComponent
            if name == ".build" || name == ".git" || name == ".swiftpm" || name == "node_modules" {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modDate = values.contentModificationDate else {
                continue
            }
            result[url.standardizedFileURL.path] = modDate
        }
        return result
    }

    private static func relativePath(_ absPath: String, root: String) -> String {
        if absPath.hasPrefix(root) {
            var rel = String(absPath.dropFirst(root.count))
            if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
            return rel
        }
        return (absPath as NSString).lastPathComponent
    }

    private func runGit(args: [String], at directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
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
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs `git diff --numstat HEAD` and returns a map of relative path → DiffStats.
    private func runNumstat(at directory: URL) -> [String: DiffStats] {
        guard let output = runGit(args: ["diff", "--numstat", "HEAD"], at: directory),
              !output.isEmpty else {
            return [:]
        }
        var result: [String: DiffStats] = [:]
        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3,
                  let adds = Int(parts[0]),
                  let dels = Int(parts[1]) else { continue }
            let path = String(parts[2])
            result[path] = DiffStats(additions: adds, deletions: dels)
        }
        return result
    }
}
