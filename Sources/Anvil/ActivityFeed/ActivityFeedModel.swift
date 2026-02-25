import Foundation
import Combine

/// Monitors the project directory for file changes and git commits,
/// building a live timeline of activity events.
final class ActivityFeedModel: ObservableObject {
    @Published private(set) var groups: [ActivityGroup] = []
    @Published private(set) var events: [ActivityEvent] = []

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
    }

    func start(rootURL: URL) {
        self.rootURL = rootURL
        events.removeAll()
        groups.removeAll()

        // Take initial snapshot so we only report *changes*, not the initial state
        takeSnapshot(rootURL: rootURL)
        lastHeadSHA = currentHeadSHA(at: rootURL)

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

    func clear() {
        events.removeAll()
        groups.removeAll()
    }

    // MARK: - File System Change Detection

    private func onFileSystemChange() {
        guard let rootURL = rootURL else { return }

        workQueue.async { [weak self] in
            guard let self = self else { return }
            let newSnapshot = Self.scanFiles(rootURL: rootURL)
            let detectedEvents = self.diffSnapshots(old: self.knownFiles, new: newSnapshot, rootURL: rootURL)
            self.knownFiles = newSnapshot

            if !detectedEvents.isEmpty {
                DispatchQueue.main.async {
                    self.appendEvents(detectedEvents)
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
                        id: UUID(), timestamp: now, kind: .fileModified,
                        path: relPath, fileURL: URL(fileURLWithPath: path)
                    ))
                }
            } else {
                let relPath = Self.relativePath(path, root: rootPath)
                events.append(ActivityEvent(
                    id: UUID(), timestamp: now, kind: .fileCreated,
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

            DispatchQueue.main.async {
                self.appendEvents([event])
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

    private func appendEvents(_ newEvents: [ActivityEvent]) {
        events.append(contentsOf: newEvents)
        // Trim if needed
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        rebuildGroups()
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
}
