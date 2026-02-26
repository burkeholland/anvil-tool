import Foundation
import Combine

/// A single changed file entry for the changes list.
struct ChangedFile: Identifiable {
    let url: URL
    let relativePath: String
    let status: GitFileStatus
    let staging: StagingState
    var diff: FileDiff?
    /// The staged-only diff (`git diff --cached`) used to identify which hunks are staged.
    var stagedDiff: FileDiff?

    var id: URL { url }

    var fileName: String { url.lastPathComponent }

    var directoryPath: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }
}

/// Stores enough information to undo a single per-file discard.
struct DiscardedFileEntry: Identifiable {
    let id = UUID()
    /// Display name of the discarded file.
    let fileName: String
    /// Relative path within the repository.
    let relativePath: String
    /// The original git status (used to determine how to restore).
    let status: GitFileStatus
    /// Unified diff patch captured before the discard; nil for untracked/added files.
    let patch: String?
    /// Raw file contents captured before the discard; set for untracked and unstaged added files.
    let rawContent: Data?
}

/// Manages the list of git-changed files and their diffs.
/// Owns its own FileWatcher to refresh independently of the file tree tab.
final class ChangesModel: ObservableObject {
    @Published private(set) var changedFiles: [ChangedFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var recentCommits: [GitCommit] = []
    @Published private(set) var isLoadingCommits = false
    @Published private(set) var stashes: [StashEntry] = []
    @Published private(set) var isLoadingStashes = false
    @Published var lastStashError: String?

    @Published var commitMessage: String = ""
    @Published private(set) var isCommitting = false
    @Published private(set) var lastCommitError: String?
    @Published private(set) var isDiscardingAll = false
    /// The stash reference after a "Discard All" so the user can recover.
    @Published var lastDiscardStashRef: String?
    @Published private(set) var isUndoingCommit = false
    /// The SHA of the commit that was undone, so the user can see what was reverted.
    @Published var lastUndoneCommitSHA: String?
    /// Error message from the most recent hunk-level operation.
    @Published var lastHunkError: String?
    /// The patch that was last discarded via "Discard Hunk", kept for a few seconds so the user can undo.
    @Published var lastDiscardedHunkPatch: String?
    /// In-memory undo stack for per-file discards (last 5, most-recent last).
    @Published private(set) var discardUndoStack: [DiscardedFileEntry] = []
    /// The entry currently shown in the undo toast banner; nil when no banner is visible.
    /// Separate from discardUndoStack so dismissing the banner doesn't expose older entries.
    @Published var activeDiscardBannerEntry: DiscardedFileEntry?

    // MARK: - Task Scope Tracking

    /// Relative paths of files that were already changed when the most recent task was started.
    /// Used to filter the Changes panel to only files modified during the last task.
    @Published private(set) var taskStartFiles: Set<String> = []
    /// True once `recordTaskStart()` has been called at least once for the current project.
    @Published private(set) var hasTaskStart: Bool = false

    /// Files changed since the most recent task start.
    /// Returns all changed files when no task start has been recorded.
    var lastTaskChangedFiles: [ChangedFile] {
        guard hasTaskStart else { return changedFiles }
        return changedFiles.filter { !taskStartFiles.contains($0.relativePath) }
    }

    /// Records the current set of changed file paths as the task-start baseline.
    /// Call this when the user sends a new prompt to the agent.
    func recordTaskStart() {
        taskStartFiles = Set(changedFiles.map(\.relativePath))
        hasTaskStart = true
    }

    // MARK: - Diff Snapshots

    /// A point-in-time capture of the diff state for iteration-round comparison.
    struct DiffSnapshot: Identifiable {
        let id: UUID
        let timestamp: Date
        /// Maps relative file path → FileDiff at snapshot time.
        /// A `nil` inner value means the file had no parsed diff yet.
        let diffs: [String: FileDiff?]

        var label: String {
            let f = DateFormatter()
            f.timeStyle = .short
            return f.string(from: timestamp)
        }

        /// Content-based fingerprint for a single hunk (ignores line numbers).
        static func hunkFingerprint(_ hunk: DiffHunk) -> String {
            hunk.lines.map { "\($0.kind):\($0.text)" }.joined(separator: "\n")
        }
    }

    @Published private(set) var snapshots: [DiffSnapshot] = []
    /// ID of the snapshot to compare against; when `nil`, the latest snapshot is used.
    @Published var activeSnapshotID: UUID?

    var activeSnapshot: DiffSnapshot? {
        guard !snapshots.isEmpty else { return nil }
        if let id = activeSnapshotID {
            return snapshots.first { $0.id == id }
        }
        return snapshots.last
    }

    /// Captures the current diff state as a new snapshot and makes it the active one.
    func takeSnapshot() {
        let diffs = Dictionary(uniqueKeysWithValues: changedFiles.map { ($0.relativePath, $0.diff) })
        let snap = DiffSnapshot(id: UUID(), timestamp: Date(), diffs: diffs)
        snapshots.append(snap)
        activeSnapshotID = snap.id
    }

    /// Files that have new or changed diffs since the active snapshot, with each file's
    /// diff filtered to include only hunks not present in the snapshot.
    var snapshotDeltaFiles: [ChangedFile] {
        guard let snapshot = activeSnapshot else { return changedFiles }
        var result: [ChangedFile] = []
        for file in changedFiles {
            if let snapshotEntry = snapshot.diffs[file.relativePath] {
                // File was in snapshot — show only new/changed hunks
                let snapshotPrints = Set((snapshotEntry?.hunks ?? []).map(DiffSnapshot.hunkFingerprint))
                let newHunks = (file.diff?.hunks ?? []).filter {
                    !snapshotPrints.contains(DiffSnapshot.hunkFingerprint($0))
                }
                guard !newHunks.isEmpty else { continue }
                var filtered = file
                if var diff = filtered.diff {
                    diff.hunks = newHunks
                    filtered.diff = diff
                }
                result.append(filtered)
            } else {
                // File not in snapshot → entirely new since snapshot
                result.append(file)
            }
        }
        return result
    }

    // MARK: - Review Tracking

    /// Relative paths the user has marked as reviewed in this session.
    @Published private(set) var reviewedPaths: Set<String> = []
    /// Relative paths the user has marked as needing work.
    @Published private(set) var needsWorkPaths: Set<String> = []

    // MARK: - Keyboard Navigation State

    /// Index of the currently keyboard-focused file in changedFiles.
    @Published var focusedFileIndex: Int? = nil
    /// Index of the currently keyboard-focused hunk within the focused file's diff.
    @Published var focusedHunkIndex: Int? = nil

    var focusedFile: ChangedFile? {
        guard let idx = focusedFileIndex, changedFiles.indices.contains(idx) else { return nil }
        return changedFiles[idx]
    }

    var focusedHunk: DiffHunk? {
        guard let file = focusedFile,
              let idx = focusedHunkIndex,
              let hunks = file.diff?.hunks,
              hunks.indices.contains(idx) else { return nil }
        return hunks[idx]
    }

    /// Fingerprints (adds:dels:staging) captured when each file was marked reviewed.
    /// Used to auto-clear review marks when a file's diff changes.
    private var reviewedFingerprints: [String: String] = [:]
    /// Fingerprints captured when each file was marked as needing work.
    private var needsWorkFingerprints: [String: String] = [:]

    private(set) var rootDirectory: URL?
    private var refreshGeneration: UInt64 = 0
    private var commitGeneration: UInt64 = 0
    private var stashGeneration: UInt64 = 0
    private var discardHunkGeneration: UInt64 = 0
    private var discardFileGeneration: UInt64 = 0
    private var fileWatcher: FileWatcher?

    deinit {
        fileWatcher?.stop()
    }

    var totalAdditions: Int {
        changedFiles.compactMap(\.diff).reduce(0) { $0 + $1.additionCount }
    }

    var totalDeletions: Int {
        changedFiles.compactMap(\.diff).reduce(0) { $0 + $1.deletionCount }
    }

    var stagedFiles: [ChangedFile] {
        changedFiles.filter { $0.staging == .staged || $0.staging == .partial }
    }

    var unstagedFiles: [ChangedFile] {
        changedFiles.filter { $0.staging == .unstaged || $0.staging == .partial }
    }

    var conflictedFiles: [ChangedFile] {
        changedFiles.filter { $0.status == .conflicted }
    }

    var canCommit: Bool {
        !stagedFiles.isEmpty && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCommitting
    }

    // MARK: - Commit Message Style

    /// Defines the formatting style for auto-generated commit messages.
    enum CommitMessageStyle: String, CaseIterable, Identifiable {
        case conventional = "conventional"
        case descriptive  = "descriptive"
        case bulletList   = "bulletList"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .conventional: return "Conventional"
            case .descriptive:  return "Descriptive"
            case .bulletList:   return "Bullet List"
            }
        }
    }

    // MARK: - Commit Message Generation

    /// Generates a commit message from the current changes.
    /// - Parameters:
    ///   - style: The formatting style. When `nil` (default), uses `.conventional` if `sessionStats`
    ///     are active, otherwise `.descriptive` — preserving existing auto-fill behaviour.
    ///   - allFiles: When `true`, uses all changed files (for Stage All & Commit).
    ///     When `false` (default), uses staged files if any are staged, otherwise all changed files.
    ///   - sessionStats: Optional activity-feed session stats used to infer the conventional commit type.
    func generateCommitMessage(
        style: CommitMessageStyle? = nil,
        allFiles: Bool = false,
        sessionStats: ActivityFeedModel.SessionStats? = nil
    ) -> String {
        let files: [ChangedFile]
        if allFiles {
            files = changedFiles
        } else {
            files = stagedFiles.isEmpty ? changedFiles : stagedFiles
        }
        guard !files.isEmpty else { return "" }

        let added = files.filter { $0.status == .added || $0.status == .untracked }
        let modified = files.filter { $0.status == .modified }
        let deleted = files.filter { $0.status == .deleted }
        let renamed = files.filter { $0.status == .renamed }

        // Resolve effective style: explicit > auto-detect from sessionStats
        let effectiveStyle = style ?? (sessionStats?.isActive == true ? .conventional : .descriptive)

        // Bullet-list: subject + per-file descriptions via DiffChangeDescriber
        if effectiveStyle == .bulletList {
            return buildBulletListMessage(files: files, added: added, modified: modified, deleted: deleted)
        }

        // Build subject line
        let subject: String
        if effectiveStyle == .conventional {
            subject = buildConventionalSubject(
                files: files, added: added, modified: modified, deleted: deleted,
                sessionStats: sessionStats?.isActive == true ? sessionStats : nil
            )
        } else {
            subject = buildSubject(added: added, modified: modified, deleted: deleted, renamed: renamed)
        }

        // Build body with per-directory grouping, per-file stats, and extracted symbols
        var bodyLines: [String] = []
        if files.count > 1 {
            bodyLines.append("")
            let groups = Dictionary(grouping: files) { $0.directoryPath }
            let sortedDirs = groups.keys.sorted()
            if sortedDirs.count > 1 {
                // Multiple directories: group files under their parent directory
                for dir in sortedDirs {
                    let dirLabel = dir.isEmpty ? "(root)" : "\(dir)/"
                    bodyLines.append(dirLabel)
                    for file in groups[dir]! {
                        let stats = fileStatsLabel(file)
                        let symbols = extractedSymbols(file)
                        let symbolSuffix = symbols.isEmpty ? "" : ": \(symbols)"
                        bodyLines.append("  - \(file.fileName)\(stats)\(symbolSuffix)")
                    }
                }
            } else {
                // Single directory: flat list with optional symbol annotation
                for file in files {
                    let stats = fileStatsLabel(file)
                    let symbols = extractedSymbols(file)
                    let symbolSuffix = symbols.isEmpty ? "" : ": \(symbols)"
                    bodyLines.append("- \(file.relativePath)\(stats)\(symbolSuffix)")
                }
            }
        }

        return subject + bodyLines.joined(separator: "\n")
    }

    /// Builds a bullet-list commit message using `DiffChangeDescriber` for per-file descriptions.
    private func buildBulletListMessage(
        files: [ChangedFile],
        added: [ChangedFile],
        modified: [ChangedFile],
        deleted: [ChangedFile]
    ) -> String {
        // Subject: concise summary of the dominant operation
        let subject: String
        if files.count == 1, let file = files.first {
            let verb: String
            switch file.status {
            case .added, .untracked: verb = "Add"
            case .deleted:           verb = "Remove"
            case .renamed:           verb = "Rename"
            default:                 verb = "Update"
            }
            subject = "\(verb) \(file.fileName)"
        } else {
            var parts: [String] = []
            if !added.isEmpty    { parts.append("\(added.count) added") }
            if !modified.isEmpty { parts.append("\(modified.count) modified") }
            if !deleted.isEmpty  { parts.append("\(deleted.count) deleted") }
            let fileWord = files.count == 1 ? "file" : "files"
            subject = "Update \(files.count) \(fileWord)" + (parts.isEmpty ? "" : " — \(parts.joined(separator: ", "))")
        }

        guard files.count > 1 else { return subject }

        // Body: one bullet per file, annotated with DiffChangeDescriber when possible
        var lines: [String] = [subject, ""]
        for file in files {
            let ext = (file.relativePath as NSString).pathExtension.lowercased()
            var row = "- \(file.relativePath)"
            if let diff = file.diff,
               let desc = DiffChangeDescriber.describe(diff: diff, fileExtension: ext) {
                row += ": \(desc)"
            } else {
                let stats = fileStatsLabel(file)
                if !stats.isEmpty { row += " \(stats)" }
            }
            lines.append(row)
        }

        return lines.joined(separator: "\n")
    }

    /// Extracts up to three top-level symbol names (functions, types, etc.) from
    /// the addition lines of a file's diff, using `SymbolParser`.
    private func extractedSymbols(_ file: ChangedFile) -> String {
        guard let diff = file.diff, !diff.hunks.isEmpty else { return "" }
        let ext = (file.relativePath as NSString).pathExtension.lowercased()
        let language = languageFromExtension(ext)
        guard !language.isEmpty else { return "" }
        let addedLines = diff.hunks.flatMap(\.lines)
            .filter { $0.kind == .addition }
            .compactMap { $0.text.hasPrefix("+") ? String($0.text.dropFirst()) : nil }
        guard !addedLines.isEmpty else { return "" }
        let source = addedLines.joined(separator: "\n")
        let symbols = SymbolParser.parse(source: source, language: language)
        let topLevel = symbols.filter { $0.depth == 0 }.prefix(3).map(\.name)
        guard !topLevel.isEmpty else { return "" }
        return topLevel.joined(separator: ", ")
    }

    /// Maps a file extension to the Highlightr language identifier used by `SymbolParser`.
    private func languageFromExtension(_ ext: String) -> String {
        switch ext {
        case "swift":             return "swift"
        case "ts", "tsx":        return "typescript"
        case "js", "jsx":        return "javascript"
        case "py":               return "python"
        case "go":               return "go"
        case "rs":               return "rust"
        case "java":             return "java"
        case "kt", "kts":        return "kotlin"
        case "cs":               return "csharp"
        case "c", "h":           return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "m", "mm":          return "objectivec"
        case "rb":               return "ruby"
        case "php":              return "php"
        default:                 return ""
        }
    }

    /// Builds a conventional commit subject line (`type(scope): description`).
    /// When `sessionStats` is provided its diff totals are used to improve type inference.
    private func buildConventionalSubject(
        files: [ChangedFile],
        added: [ChangedFile],
        modified: [ChangedFile],
        deleted: [ChangedFile],
        sessionStats: ActivityFeedModel.SessionStats? = nil
    ) -> String {
        // Infer type from the dominant operation and diff stats
        let commitType: String
        let (fallbackAdditions, fallbackDeletions) = files.compactMap(\.diff)
            .reduce((0, 0)) { ($0.0 + $1.additionCount, $0.1 + $1.deletionCount) }
        let totalAdditions = sessionStats?.totalAdditions ?? fallbackAdditions
        let totalDeletions = sessionStats?.totalDeletions ?? fallbackDeletions
        if !added.isEmpty && added.count >= modified.count {
            commitType = "feat"
        } else if totalDeletions > totalAdditions && !deleted.isEmpty {
            commitType = "fix"
        } else if !modified.isEmpty && added.isEmpty {
            commitType = "refactor"
        } else {
            commitType = added.isEmpty ? "fix" : "feat"
        }

        // Infer scope from the most common directory
        let dirs = files.map(\.directoryPath).filter { !$0.isEmpty }
        let scopeCandidate: String
        if let mostCommon = dirs.max(by: { a, b in dirs.filter { $0 == a }.count < dirs.filter { $0 == b }.count }) {
            // Use the last component of the directory path as a compact scope
            scopeCandidate = (mostCommon as NSString).lastPathComponent
        } else {
            scopeCandidate = ""
        }
        let scopePart = scopeCandidate.isEmpty ? "" : "(\(scopeCandidate))"

        // Build description from the primary change
        let description: String
        let dominantFiles: [ChangedFile]
        if !added.isEmpty && added.count >= modified.count {
            dominantFiles = added
            let names = dominantFiles.prefix(2).map(\.fileName).joined(separator: ", ")
            let extra = dominantFiles.count > 2 ? " and \(dominantFiles.count - 2) more" : ""
            description = "add \(names)\(extra)"
        } else if !modified.isEmpty {
            dominantFiles = modified
            let names = dominantFiles.prefix(2).map(\.fileName).joined(separator: ", ")
            let extra = dominantFiles.count > 2 ? " and \(dominantFiles.count - 2) more" : ""
            description = "update \(names)\(extra)"
        } else if !deleted.isEmpty {
            let names = deleted.prefix(2).map(\.fileName).joined(separator: ", ")
            let extra = deleted.count > 2 ? " and \(deleted.count - 2) more" : ""
            description = "remove \(names)\(extra)"
        } else {
            description = "update \(files.prefix(2).map(\.fileName).joined(separator: ", "))"
        }

        return "\(commitType)\(scopePart): \(description)"
    }

    private func buildSubject(added: [ChangedFile], modified: [ChangedFile], deleted: [ChangedFile], renamed: [ChangedFile]) -> String {
        var parts: [String] = []

        if !added.isEmpty {
            let names = added.prefix(3).map(\.fileName)
            let label = names.joined(separator: ", ")
            parts.append("Add \(label)\(added.count > 3 ? " and \(added.count - 3) more" : "")")
        }
        if !modified.isEmpty {
            let names = modified.prefix(3).map(\.fileName)
            let label = names.joined(separator: ", ")
            parts.append("Update \(label)\(modified.count > 3 ? " and \(modified.count - 3) more" : "")")
        }
        if !deleted.isEmpty {
            let names = deleted.prefix(3).map(\.fileName)
            let label = names.joined(separator: ", ")
            parts.append("Remove \(label)\(deleted.count > 3 ? " and \(deleted.count - 3) more" : "")")
        }
        if !renamed.isEmpty {
            let names = renamed.prefix(2).map(\.fileName)
            let label = names.joined(separator: ", ")
            parts.append("Rename \(label)\(renamed.count > 2 ? " and \(renamed.count - 2) more" : "")")
        }

        if parts.isEmpty { return "Update files" }
        return parts.joined(separator: "; ")
    }

    private func fileStatsLabel(_ file: ChangedFile) -> String {
        guard let diff = file.diff else {
            return file.status == .untracked ? " (new)" : ""
        }
        let adds = diff.additionCount
        let dels = diff.deletionCount
        if adds > 0 && dels > 0 { return " (+\(adds)/-\(dels))" }
        if adds > 0 { return " (+\(adds))" }
        if dels > 0 { return " (-\(dels))" }
        return ""
    }

    // MARK: - Review Tracking Methods

    var reviewedCount: Int {
        changedFiles.filter { reviewedPaths.contains($0.relativePath) }.count
    }

    /// Number of files marked as needing work.
    var needsWorkCount: Int {
        changedFiles.filter { needsWorkPaths.contains($0.relativePath) }.count
    }

    /// Number of staged files that have not yet been marked reviewed or needs-work.
    var unreviewedStagedCount: Int {
        stagedFiles.filter { !reviewedPaths.contains($0.relativePath) && !needsWorkPaths.contains($0.relativePath) }.count
    }

    func isReviewed(_ file: ChangedFile) -> Bool {
        reviewedPaths.contains(file.relativePath)
    }

    func isNeedsWork(_ file: ChangedFile) -> Bool {
        needsWorkPaths.contains(file.relativePath)
    }

    /// Cycles the review state: unreviewed → reviewed ✓ → needs work ✗ → unreviewed.
    func toggleReviewed(_ file: ChangedFile) {
        if reviewedPaths.contains(file.relativePath) {
            // reviewed → needs work
            reviewedPaths.remove(file.relativePath)
            reviewedFingerprints.removeValue(forKey: file.relativePath)
            needsWorkPaths.insert(file.relativePath)
            needsWorkFingerprints[file.relativePath] = diffFingerprint(file)
        } else if needsWorkPaths.contains(file.relativePath) {
            // needs work → unreviewed
            needsWorkPaths.remove(file.relativePath)
            needsWorkFingerprints.removeValue(forKey: file.relativePath)
        } else {
            // unreviewed → reviewed
            reviewedPaths.insert(file.relativePath)
            reviewedFingerprints[file.relativePath] = diffFingerprint(file)
        }
        saveReviewedState()
    }

    func markAllReviewed() {
        for file in changedFiles {
            needsWorkPaths.remove(file.relativePath)
            needsWorkFingerprints.removeValue(forKey: file.relativePath)
            reviewedPaths.insert(file.relativePath)
            reviewedFingerprints[file.relativePath] = diffFingerprint(file)
        }
        saveReviewedState()
    }

    func clearAllReviewed() {
        reviewedPaths.removeAll()
        reviewedFingerprints.removeAll()
        needsWorkPaths.removeAll()
        needsWorkFingerprints.removeAll()
        saveReviewedState()
    }

    // MARK: - Review Persistence

    private static let reviewedFingerprintsKeyPrefix = "com.anvil.reviewedFingerprints."
    private static let needsWorkFingerprintsKeyPrefix = "com.anvil.needsWorkFingerprints."

    private func reviewedStateKey(for rootURL: URL) -> String {
        Self.reviewedFingerprintsKeyPrefix + rootURL.path
    }

    private func needsWorkStateKey(for rootURL: URL) -> String {
        Self.needsWorkFingerprintsKeyPrefix + rootURL.path
    }

    private func saveReviewedState() {
        guard let rootURL = rootDirectory else { return }
        UserDefaults.standard.set(reviewedFingerprints, forKey: reviewedStateKey(for: rootURL))
        UserDefaults.standard.set(needsWorkFingerprints, forKey: needsWorkStateKey(for: rootURL))
    }

    private func loadReviewedState(for rootURL: URL) {
        let key = reviewedStateKey(for: rootURL)
        if let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: String] {
            reviewedFingerprints = stored
            reviewedPaths = Set(stored.keys)
        }
        let nwKey = needsWorkStateKey(for: rootURL)
        if let stored = UserDefaults.standard.dictionary(forKey: nwKey) as? [String: String] {
            needsWorkFingerprints = stored
            needsWorkPaths = Set(stored.keys)
        }
    }

    // MARK: - Keyboard Navigation

    func focusNextFile() {
        guard !changedFiles.isEmpty else { return }
        if let current = focusedFileIndex {
            focusedFileIndex = min(current + 1, changedFiles.count - 1)
        } else {
            focusedFileIndex = 0
        }
        focusedHunkIndex = nil
    }

    func focusPreviousFile() {
        guard !changedFiles.isEmpty else { return }
        if let current = focusedFileIndex {
            focusedFileIndex = max(current - 1, 0)
        } else {
            focusedFileIndex = changedFiles.count - 1
        }
        focusedHunkIndex = nil
    }

    func focusNextUnreviewedFile() {
        let unreviewedIndices = changedFiles.indices.filter {
            !reviewedPaths.contains(changedFiles[$0].relativePath) &&
            !needsWorkPaths.contains(changedFiles[$0].relativePath)
        }
        guard let firstUnreviewed = unreviewedIndices.first else { return }
        if let current = focusedFileIndex,
           let next = unreviewedIndices.first(where: { $0 > current }) {
            focusedFileIndex = next
        } else {
            focusedFileIndex = firstUnreviewed
        }
        focusedHunkIndex = nil
    }

    func focusPreviousUnreviewedFile() {
        let unreviewedIndices = changedFiles.indices.filter {
            !reviewedPaths.contains(changedFiles[$0].relativePath) &&
            !needsWorkPaths.contains(changedFiles[$0].relativePath)
        }
        guard let lastUnreviewed = unreviewedIndices.last else { return }
        if let current = focusedFileIndex,
           let prev = unreviewedIndices.last(where: { $0 < current }) {
            focusedFileIndex = prev
        } else {
            focusedFileIndex = lastUnreviewed
        }
        focusedHunkIndex = nil
    }

    func focusNextHunk() {
        guard let file = focusedFile,
              let hunks = file.diff?.hunks,
              !hunks.isEmpty else {
            if focusedFileIndex == nil { focusNextFile() }
            return
        }
        if let current = focusedHunkIndex {
            focusedHunkIndex = min(current + 1, hunks.count - 1)
        } else {
            focusedHunkIndex = 0
        }
    }

    func focusPreviousHunk() {
        guard let file = focusedFile,
              let hunks = file.diff?.hunks,
              !hunks.isEmpty else {
            if focusedFileIndex == nil { focusPreviousFile() }
            return
        }
        if let current = focusedHunkIndex {
            focusedHunkIndex = max(current - 1, 0)
        } else {
            focusedHunkIndex = hunks.count - 1
        }
    }

    func stageFocusedHunk() {
        guard let file = focusedFile, let hunk = focusedHunk, let diff = file.diff else { return }
        stageHunk(patch: DiffParser.reconstructPatch(fileDiff: diff, hunk: hunk))
    }

    func unstageFocusedHunk() {
        guard let file = focusedFile, let hunk = focusedHunk, let diff = file.diff else { return }
        unstageHunk(patch: DiffParser.reconstructPatch(fileDiff: diff, hunk: hunk))
    }

    func discardFocusedHunk() {
        guard let file = focusedFile, let hunk = focusedHunk, let diff = file.diff else { return }
        discardHunk(patch: DiffParser.reconstructPatch(fileDiff: diff, hunk: hunk))
    }

    func toggleFocusedFileReviewed() {
        guard let file = focusedFile else { return }
        toggleReviewed(file)
    }

    private func diffFingerprint(_ file: ChangedFile) -> String {
        if let diff = file.diff {
            // Include hunk headers for sensitivity to content changes, not just counts
            let hunkSummary = diff.hunks.map(\.header).joined(separator: "|")
            return "\(diff.additionCount):\(diff.deletionCount):\(file.staging):\(hunkSummary)"
        }
        // For files with no diff (e.g., untracked), use file size as a proxy
        let size = (try? FileManager.default.attributesOfItem(atPath: file.url.path))?[.size] as? Int ?? 0
        return "nodiff:\(file.status):\(size)"
    }

    /// Prunes review marks for files that no longer exist or whose diff changed.
    private func pruneReviewedPaths(newFiles: [ChangedFile]) {
        let currentPaths = Set(newFiles.map(\.relativePath))
        // Remove paths that are no longer in the changed list
        reviewedPaths = reviewedPaths.intersection(currentPaths)
        reviewedFingerprints = reviewedFingerprints.filter { currentPaths.contains($0.key) }
        needsWorkPaths = needsWorkPaths.intersection(currentPaths)
        needsWorkFingerprints = needsWorkFingerprints.filter { currentPaths.contains($0.key) }
        // Clear marks where the diff changed since review
        for file in newFiles {
            if let fingerprint = reviewedFingerprints[file.relativePath],
               fingerprint != diffFingerprint(file) {
                reviewedPaths.remove(file.relativePath)
                reviewedFingerprints.removeValue(forKey: file.relativePath)
            }
            if let fingerprint = needsWorkFingerprints[file.relativePath],
               fingerprint != diffFingerprint(file) {
                needsWorkPaths.remove(file.relativePath)
                needsWorkFingerprints.removeValue(forKey: file.relativePath)
            }
        }
        saveReviewedState()
    }

    func start(rootURL: URL) {
        self.rootDirectory = rootURL
        loadReviewedState(for: rootURL)
        fileWatcher?.stop()
        fileWatcher = FileWatcher(directory: rootURL) { [weak self] in
            self?.refresh()
            self?.refreshCommits()
            self?.refreshStashes()
        }
        refresh()
        refreshCommits()
        refreshStashes()
    }

    func stop() {
        fileWatcher?.stop()
        fileWatcher = nil
        rootDirectory = nil
        // Advance generations so any in-flight refresh is discarded
        refreshGeneration &+= 1
        commitGeneration &+= 1
        stashGeneration &+= 1
        changedFiles = []
        recentCommits = []
        stashes = []
        isLoading = false
        isLoadingCommits = false
        isLoadingStashes = false
        commitMessage = ""
        isCommitting = false
        lastCommitError = nil
        isDiscardingAll = false
        lastDiscardStashRef = nil
        isUndoingCommit = false
        lastUndoneCommitSHA = nil
        lastHunkError = nil
        lastStashError = nil
        reviewedPaths = []
        reviewedFingerprints = [:]
        focusedFileIndex = nil
        focusedHunkIndex = nil
        taskStartFiles = []
        hasTaskStart = false
        snapshots = []
        activeSnapshotID = nil
    }

    func refresh() {
        guard let rootURL = rootDirectory else { return }
        isLoading = true
        refreshGeneration &+= 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let detailed = GitStatusProvider.detailedStatus(for: rootURL)
            let gitRoot = detailed?.gitRoot ?? rootURL
            let statuses = detailed?.files ?? [:]
            let diffs = DiffProvider.allChanges(in: rootURL)
            let stagedDiffs = DiffProvider.allStagedChanges(in: rootURL)

            // Build a lookup from relative path → FileDiff
            var diffMap: [String: FileDiff] = [:]
            for diff in diffs {
                diffMap[diff.newPath] = diff
            }

            // Build a lookup from relative path → staged FileDiff
            var stagedDiffMap: [String: FileDiff] = [:]
            for diff in stagedDiffs {
                stagedDiffMap[diff.newPath] = diff
            }

            let gitRootPath = gitRoot.standardizedFileURL.path
            var files: [ChangedFile] = []
            for (absPath, detail) in statuses {
                let url = URL(fileURLWithPath: absPath)
                // Skip directories
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: absPath, isDirectory: &isDir), isDir.boolValue {
                    continue
                }

                let relativePath: String
                if absPath.hasPrefix(gitRootPath) {
                    var rel = String(absPath.dropFirst(gitRootPath.count))
                    if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
                    relativePath = rel
                } else {
                    relativePath = url.lastPathComponent
                }

                let fileDiff: FileDiff?
                if let mapped = diffMap[relativePath] {
                    fileDiff = mapped
                } else if detail.status == .untracked {
                    fileDiff = DiffProvider.newFileDiff(for: url, relativePath: relativePath)
                } else {
                    fileDiff = nil
                }

                files.append(ChangedFile(
                    url: url,
                    relativePath: relativePath,
                    status: detail.status,
                    staging: detail.staging,
                    diff: fileDiff,
                    stagedDiff: stagedDiffMap[relativePath]
                ))
            }

            files.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }

            DispatchQueue.main.async {
                guard let self = self, self.refreshGeneration == generation else { return }
                self.pruneReviewedPaths(newFiles: files)
                self.changedFiles = files
                self.isLoading = false
                // Clamp focused index to valid range after refresh
                if let idx = self.focusedFileIndex {
                    if files.isEmpty {
                        self.focusedFileIndex = nil
                        self.focusedHunkIndex = nil
                    } else if idx >= files.count {
                        self.focusedFileIndex = files.count - 1
                        self.focusedHunkIndex = nil
                    }
                }
            }
        }
    }

    func refreshCommits() {
        guard let rootURL = rootDirectory else { return }
        isLoadingCommits = true
        commitGeneration &+= 1
        let generation = commitGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let commits = GitLogProvider.recentCommits(in: rootURL, count: 50)
            DispatchQueue.main.async {
                guard let self = self, self.commitGeneration == generation else { return }
                self.recentCommits = commits
                self.isLoadingCommits = false
            }
        }
    }

    /// Load the file list for a commit (lazy-loaded on expand).
    func loadCommitFiles(for sha: String) {
        guard let rootURL = rootDirectory else { return }
        guard let index = recentCommits.firstIndex(where: { $0.sha == sha }),
              recentCommits[index].files == nil else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = GitLogProvider.commitFiles(sha: sha, in: rootURL)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.recentCommits.firstIndex(where: { $0.sha == sha }) else { return }
                self.recentCommits[idx].files = files
            }
        }
    }

    /// Discard all uncommitted changes to a file.
    /// Handles different git statuses appropriately.
    /// Saves a snapshot to the undo stack (max 5) so the discard can be reversed.
    func discardChanges(for file: ChangedFile) {
        guard let rootURL = rootDirectory else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Capture undo data before destroying the changes.
            let patch: String?
            let rawContent: Data?
            switch file.status {
            case .untracked:
                patch = nil
                rawContent = try? Data(contentsOf: file.url)
            case .added:
                // Prefer capturing from the index (staged); fall back to reading from disk.
                if file.staging == .staged || file.staging == .partial,
                   let stagedContent = Self.runGitOutput(args: ["show", ":\(file.relativePath)"], at: rootURL) {
                    patch = stagedContent
                    rawContent = nil
                } else {
                    patch = nil
                    rawContent = try? Data(contentsOf: file.url)
                }
            default:
                // Capture a combined diff of both staged and unstaged changes.
                if file.staging == .staged || file.staging == .partial {
                    // Include staged changes: diff tree HEAD vs index + index vs work-tree
                    let staged = Self.runGitOutput(
                        args: ["diff", "--cached", "--binary", "HEAD", "--", file.relativePath],
                        at: rootURL) ?? ""
                    let unstaged = Self.runGitOutput(
                        args: ["diff", "--binary", "--", file.relativePath],
                        at: rootURL) ?? ""
                    patch = staged.isEmpty && unstaged.isEmpty ? nil : staged + unstaged
                } else {
                    patch = Self.runGitOutput(
                        args: ["diff", "--binary", "HEAD", "--", file.relativePath],
                        at: rootURL)
                }
                rawContent = nil
            }

            // For staged files, unstage first so the working-tree restore works cleanly.
            if file.staging == .staged || file.staging == .partial {
                switch file.status {
                case .untracked, .added:
                    Self.runGitSync(args: ["reset", "HEAD", "--", file.relativePath], at: rootURL)
                default:
                    Self.runGitSync(args: ["restore", "--staged", "--", file.relativePath], at: rootURL)
                }
            }

            switch file.status {
            case .untracked:
                // Remove untracked file from disk
                Self.runGitSync(args: ["clean", "-f", "--", file.relativePath], at: rootURL)
            case .added:
                // Unstage if not already done above, then remove from disk.
                if file.staging != .staged && file.staging != .partial {
                    Self.runGitSync(args: ["reset", "HEAD", "--", file.relativePath], at: rootURL)
                }
                Self.runGitSync(args: ["clean", "-f", "--", file.relativePath], at: rootURL)
            default:
                // For modified, deleted, renamed, conflicted: restore from HEAD
                Self.runGitSync(args: ["checkout", "HEAD", "--", file.relativePath], at: rootURL)
            }

            let entry = DiscardedFileEntry(
                fileName: file.fileName,
                relativePath: file.relativePath,
                status: file.status,
                patch: patch,
                rawContent: rawContent
            )

            DispatchQueue.main.async {
                guard let self else { return }
                // Push onto undo stack, capping at 5.
                self.discardUndoStack.append(entry)
                if self.discardUndoStack.count > 5 {
                    self.discardUndoStack.removeFirst()
                }
                // Show in the banner and auto-dismiss after 8 seconds.
                self.activeDiscardBannerEntry = entry
                self.discardFileGeneration &+= 1
                let generation = self.discardFileGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                    if self?.discardFileGeneration == generation {
                        self?.activeDiscardBannerEntry = nil
                    }
                }
                self.refresh()
            }
        }
    }

    /// Undo the most recent per-file discard by re-applying its captured patch or content.
    func undoDiscardFile() {
        guard let rootURL = rootDirectory, let entry = activeDiscardBannerEntry ?? discardUndoStack.last else { return }
        discardFileGeneration &+= 1
        activeDiscardBannerEntry = nil
        // Remove this entry from the stack if present.
        if let idx = discardUndoStack.firstIndex(where: { $0.id == entry.id }) {
            discardUndoStack.remove(at: idx)
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var succeeded = true
            switch entry.status {
            case .untracked:
                // Restore the raw file content.
                if let data = entry.rawContent {
                    let fileURL = rootURL.appendingPathComponent(entry.relativePath)
                    let dir = fileURL.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    succeeded = (try? data.write(to: fileURL)) != nil
                }
            case .added:
                // Restore from staged blob or raw content, then re-stage.
                let restoreData: Data?
                if let blob = entry.patch {
                    restoreData = blob.data(using: .utf8)
                } else {
                    restoreData = entry.rawContent
                }
                if let data = restoreData {
                    let fileURL = rootURL.appendingPathComponent(entry.relativePath)
                    let dir = fileURL.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    succeeded = (try? data.write(to: fileURL)) != nil
                    if succeeded && entry.patch != nil {
                        // Re-stage only if we originally captured from the index.
                        Self.runGitSync(args: ["add", "--", entry.relativePath], at: rootURL)
                    }
                }
            default:
                if let patch = entry.patch, !patch.isEmpty {
                    let (ok, _) = Self.runGitApply(patch: patch, args: ["apply"], at: rootURL)
                    succeeded = ok
                }
            }
            DispatchQueue.main.async {
                if !succeeded {
                    self?.lastHunkError = "Failed to undo file discard for \(entry.fileName)"
                }
                self?.refresh()
            }
        }
    }

    /// Dismiss the undo toast banner without reverting the file.
    func dismissDiscardUndo() {
        discardFileGeneration &+= 1
        activeDiscardBannerEntry = nil
    }

    // MARK: - Staging

    /// Stage a file (add to the git index).
    func stageFile(_ file: ChangedFile) {
        guard let rootURL = rootDirectory else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.runGitSync(args: ["add", "--", file.relativePath], at: rootURL)
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    /// Unstage a file (remove from the git index but keep changes).
    func unstageFile(_ file: ChangedFile) {
        guard let rootURL = rootDirectory else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if file.status == .untracked || file.status == .added {
                Self.runGitSync(args: ["reset", "HEAD", "--", file.relativePath], at: rootURL)
            } else {
                Self.runGitSync(args: ["restore", "--staged", "--", file.relativePath], at: rootURL)
            }
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    /// Stage all changed files.
    func stageAll(completion: (() -> Void)? = nil) {
        guard let rootURL = rootDirectory else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.runGitSync(args: ["add", "-A"], at: rootURL)
            DispatchQueue.main.async {
                self?.refresh()
                completion?()
            }
        }
    }

    /// Unstage all staged files.
    func unstageAll() {
        guard let rootURL = rootDirectory else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.runGitSync(args: ["reset", "HEAD"], at: rootURL)
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    // MARK: - Hunk-level Staging

    /// Stage a single hunk by applying a patch to the index.
    func stageHunk(patch: String) {
        guard let rootURL = rootDirectory else { return }
        lastHunkError = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = Self.runGitApply(patch: patch, args: ["apply", "--cached"], at: rootURL)
            DispatchQueue.main.async {
                if !success { self?.lastHunkError = error ?? "Failed to stage hunk" }
                self?.refresh()
            }
        }
    }

    /// Unstage a single hunk by reverse-applying the patch from the index.
    func unstageHunk(patch: String) {
        guard let rootURL = rootDirectory else { return }
        lastHunkError = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = Self.runGitApply(patch: patch, args: ["apply", "--cached", "--reverse"], at: rootURL)
            DispatchQueue.main.async {
                if !success { self?.lastHunkError = error ?? "Failed to unstage hunk" }
                self?.refresh()
            }
        }
    }

    /// Discard a single hunk by reverse-applying the patch to the working tree.
    func discardHunk(patch: String) {
        guard let rootURL = rootDirectory else { return }
        lastHunkError = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = Self.runGitApply(patch: patch, args: ["apply", "--reverse"], at: rootURL)
            DispatchQueue.main.async {
                if success {
                    self?.discardHunkGeneration &+= 1
                    let generation = self?.discardHunkGeneration ?? 0
                    self?.lastDiscardedHunkPatch = patch
                    // Auto-dismiss the undo toast after 8 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                        if self?.discardHunkGeneration == generation {
                            self?.lastDiscardedHunkPatch = nil
                        }
                    }
                } else {
                    self?.lastHunkError = error ?? "Failed to discard hunk"
                }
                self?.refresh()
            }
        }
    }

    /// Re-apply the last discarded hunk patch to undo a hunk discard.
    func undoDiscardHunk() {
        guard let rootURL = rootDirectory, let patch = lastDiscardedHunkPatch else { return }
        discardHunkGeneration &+= 1
        lastDiscardedHunkPatch = nil
        lastHunkError = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = Self.runGitApply(patch: patch, args: ["apply"], at: rootURL)
            DispatchQueue.main.async {
                if !success { self?.lastHunkError = error ?? "Failed to undo hunk discard" }
                self?.refresh()
            }
        }
    }

    /// Commit staged changes with the current commit message.
    func commit() {
        guard let rootURL = rootDirectory else { return }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !stagedFiles.isEmpty else { return }

        isCommitting = true
        lastCommitError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = Self.runGitCommit(message: message, at: rootURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isCommitting = false
                if success {
                    self.commitMessage = ""
                    self.lastCommitError = nil
                } else {
                    self.lastCommitError = error ?? "Commit failed"
                }
                self.refresh()
                self.refreshCommits()
            }
        }
    }

    /// Stage all files and commit atomically, without relying on intermediate
    /// UI state refresh between the two git operations.
    func stageAllAndCommit(completion: (() -> Void)? = nil) {
        guard let rootURL = rootDirectory else { return }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !changedFiles.isEmpty else { return }

        isCommitting = true
        lastCommitError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.runGitSync(args: ["add", "-A"], at: rootURL)
            let (success, error) = Self.runGitCommit(message: message, at: rootURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isCommitting = false
                if success {
                    self.commitMessage = ""
                    self.lastCommitError = nil
                    completion?()
                } else {
                    self.lastCommitError = error ?? "Commit failed"
                }
                self.refresh()
                self.refreshCommits()
            }
        }
    }

    /// Commit staged changes and then push to the remote.
    func commitAndPush(pushAction: @escaping () -> Void) {
        guard let rootURL = rootDirectory else { return }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !stagedFiles.isEmpty else { return }

        isCommitting = true
        lastCommitError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = Self.runGitCommit(message: message, at: rootURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isCommitting = false
                if success {
                    self.commitMessage = ""
                    self.lastCommitError = nil
                    pushAction()
                } else {
                    self.lastCommitError = error ?? "Commit failed"
                }
                self.refresh()
                self.refreshCommits()
            }
        }
    }

    /// Stage all files, commit atomically, and then push to the remote.
    func stageAllAndCommitAndPush(pushAction: @escaping () -> Void) {
        guard let rootURL = rootDirectory else { return }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !changedFiles.isEmpty else { return }

        isCommitting = true
        lastCommitError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.runGitSync(args: ["add", "-A"], at: rootURL)
            let (success, error) = Self.runGitCommit(message: message, at: rootURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isCommitting = false
                if success {
                    self.commitMessage = ""
                    self.lastCommitError = nil
                    pushAction()
                } else {
                    self.lastCommitError = error ?? "Commit failed"
                }
                self.refresh()
                self.refreshCommits()
            }
        }
    }

    /// Discard all uncommitted changes. Stashes first so the user can recover.
    func discardAll() {
        guard let rootURL = rootDirectory, !changedFiles.isEmpty else { return }
        isDiscardingAll = true
        lastDiscardStashRef = nil
        refreshGeneration &+= 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Count stashes before push to verify a new one was created
            let countBefore = Self.runGitOutput(args: ["stash", "list"], at: rootURL)?
                .components(separatedBy: "\n").filter { !$0.isEmpty }.count ?? 0

            // Stash everything (including untracked) for recovery
            _ = Self.runGitOutput(args: ["stash", "push", "--include-untracked", "-m", "Anvil: discard all changes"], at: rootURL)

            let countAfter = Self.runGitOutput(args: ["stash", "list"], at: rootURL)?
                .components(separatedBy: "\n").filter { !$0.isEmpty }.count ?? 0

            // Resolve stash@{0} to an immutable SHA so index drift doesn't matter
            let stashRef: String?
            if countAfter > countBefore {
                stashRef = Self.runGitOutput(args: ["rev-parse", "stash@{0}"], at: rootURL)
            } else {
                stashRef = nil
            }

            DispatchQueue.main.async {
                guard let self = self, self.refreshGeneration == generation else { return }
                self.lastDiscardStashRef = stashRef
                self.isDiscardingAll = false
                self.refresh()
            }
        }
    }

    /// Recover changes from the last discard-all stash.
    func recoverDiscarded() {
        guard let rootURL = rootDirectory, let sha = lastDiscardStashRef else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = Self.runGitWithStatus(args: ["stash", "apply", sha], at: rootURL)
            if success {
                // Drop the stash entry only after successful apply
                Self.runGitSync(args: ["stash", "drop", sha], at: rootURL)
            }
            DispatchQueue.main.async {
                guard let self = self, self.refreshGeneration == generation else { return }
                if success {
                    self.lastDiscardStashRef = nil
                }
                // Always refresh to reflect current state
                self.refresh()
            }
        }
    }

    // MARK: - Undo Commit

    /// Whether the most recent commit can be undone (soft reset).
    /// Returns false if there's only one commit (no parent), or an undo is already in progress.
    var canUndoCommit: Bool {
        guard !recentCommits.isEmpty && !isUndoingCommit else { return false }
        // Need at least 2 commits so HEAD~1 exists
        return recentCommits.count >= 2
    }

    /// Undo the most recent commit via `git reset --soft HEAD~1`.
    /// Changes from the undone commit become staged, preserving all work.
    func undoLastCommit() {
        guard let rootURL = rootDirectory, let commit = recentCommits.first else { return }
        isUndoingCommit = true
        lastUndoneCommitSHA = nil
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let sha = commit.shortSHA

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Verify HEAD~1 exists before attempting reset
            let parentExists = Self.runGitWithStatus(args: ["rev-parse", "--verify", "HEAD~1"], at: rootURL)
            let success: Bool
            if parentExists {
                success = Self.runGitWithStatus(args: ["reset", "--soft", "HEAD~1"], at: rootURL)
            } else {
                success = false
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Always clear the loading flag regardless of generation
                self.isUndoingCommit = false
                guard self.refreshGeneration == generation else { return }
                if success {
                    self.lastUndoneCommitSHA = sha
                } else {
                    self.lastCommitError = "Failed to undo commit"
                }
                self.refresh()
                self.refreshCommits()
            }
        }
    }

    // MARK: - Stash Management

    /// Stash all uncommitted changes (staged and unstaged) with an optional message.
    func stashAll(message: String = "") {
        guard let rootURL = rootDirectory, !changedFiles.isEmpty else { return }
        lastStashError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let (success, error) = GitStashProvider.push(
                message: msg.isEmpty ? nil : msg,
                in: rootURL
            )
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !success { self.lastStashError = error ?? "Failed to stash" }
                self.refresh()
                self.refreshStashes()
            }
        }
    }

    func refreshStashes() {
        guard let rootURL = rootDirectory else { return }
        isLoadingStashes = true
        stashGeneration &+= 1
        let generation = stashGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = GitStashProvider.list(in: rootURL)
            DispatchQueue.main.async {
                guard let self = self, self.stashGeneration == generation else { return }
                self.stashes = entries
                self.isLoadingStashes = false
            }
        }
    }

    /// Load the file list for a stash entry (lazy-loaded on expand).
    func loadStashFiles(for sha: String) {
        guard let rootURL = rootDirectory else { return }
        guard let index = stashes.firstIndex(where: { $0.sha == sha }),
              stashes[index].files == nil else { return }
        let stashIndex = stashes[index].index

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = GitStashProvider.stashFiles(index: stashIndex, in: rootURL)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.stashes.firstIndex(where: { $0.sha == sha }) else { return }
                self.stashes[idx].files = files
            }
        }
    }

    /// Apply a stash without removing it.
    func applyStash(sha: String) {
        guard let rootURL = rootDirectory else { return }
        lastStashError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = GitStashProvider.apply(sha: sha, in: rootURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !success {
                    self.lastStashError = error ?? "Failed to apply stash"
                }
                self.refresh()
            }
        }
    }

    /// Pop a stash (apply and remove). Uses SHA to prevent index drift.
    func popStash(sha: String) {
        guard let rootURL = rootDirectory else { return }
        lastStashError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = GitStashProvider.pop(sha: sha, in: rootURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !success {
                    self.lastStashError = error ?? "Failed to pop stash"
                }
                self.refresh()
                self.refreshStashes()
            }
        }
    }

    /// Drop a stash without applying it. Uses SHA to prevent index drift.
    func dropStash(sha: String) {
        guard let rootURL = rootDirectory else { return }
        lastStashError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (success, error) = GitStashProvider.drop(sha: sha, in: rootURL)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !success {
                    self.lastStashError = error ?? "Failed to drop stash"
                }
                self.refreshStashes()
            }
        }
    }

    private static func runGitOutput(args: [String], at directory: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runGitWithStatus(args: [String], at directory: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func runGitSync(args: [String], at directory: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// Applies a patch via stdin to `git apply` with the given arguments.
    private static func runGitApply(patch: String, args: [String], at directory: URL) -> (success: Bool, error: String?) {
        let process = Process()
        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
            if let data = patch.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }

        if process.terminationStatus == 0 {
            return (true, nil)
        }
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, msg)
    }

    private static func runGitCommit(message: String, at directory: URL) -> (success: Bool, error: String?) {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["commit", "-m", message]
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }

        if process.terminationStatus == 0 {
            return (true, nil)
        }
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, msg)
    }

    #if DEBUG
    /// Test helper to set changed files directly.
    func setChangedFilesForTesting(_ files: [ChangedFile]) {
        changedFiles = files
    }
    #endif
}
