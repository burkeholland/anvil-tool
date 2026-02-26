import Foundation
import Combine

/// Manages paginated, filtered git commit history for the project-wide history sidebar tab.
final class CommitHistoryModel: ObservableObject {
    /// The currently loaded commits in chronological (newest-first) order.
    @Published private(set) var commits: [GitCommit] = []
    /// Whether a page fetch is in progress.
    @Published private(set) var isLoading = false
    /// Whether more commits are available to load.
    @Published private(set) var hasMore = true

    /// Text to match against commit authors (case-insensitive substring match).
    @Published var authorFilter: String = "" {
        didSet {
            guard authorFilter != oldValue else { return }
            scheduleReload()
        }
    }
    /// Only show commits on or after this date.
    @Published var sinceDate: Date? = nil {
        didSet { scheduleReload() }
    }
    /// Only show commits on or before this date.
    @Published var untilDate: Date? = nil {
        didSet { scheduleReload() }
    }

    private let pageSize = 30
    private var loadedCount = 0
    /// Monotonic generation counter to discard stale async results.
    private var loadGeneration: UInt64 = 0
    private var rootURL: URL?
    private var reloadWorkItem: DispatchWorkItem?

    // MARK: - Public API

    /// Start (or restart) the model for the given repository root.
    func start(rootURL: URL) {
        self.rootURL = rootURL
        reload()
    }

    /// Reload from the beginning, discarding any loaded pages.
    func reload() {
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        loadGeneration &+= 1
        commits = []
        loadedCount = 0
        hasMore = true
        fetchNextPage()
    }

    /// Load the next page of 30 commits.
    func loadNextPage() {
        guard !isLoading, hasMore else { return }
        fetchNextPage()
    }

    /// Lazily load the changed-file list for a commit when the user expands it.
    func loadFiles(for commit: GitCommit) {
        guard let url = rootURL, commit.files == nil else { return }
        let sha = commit.sha
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = GitLogProvider.commitFiles(sha: sha, in: url)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let idx = self.commits.firstIndex(where: { $0.sha == sha }) {
                    self.commits[idx].files = files
                }
            }
        }
    }

    // MARK: - Private

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func fetchNextPage() {
        guard let url = rootURL else { return }
        isLoading = true
        loadGeneration &+= 1
        let gen = loadGeneration
        let skip = loadedCount
        let limit = pageSize
        let author = authorFilter.trimmingCharacters(in: .whitespaces)
        let since = sinceDate
        let until = untilDate

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let newCommits = GitLogProvider.pagedCommits(
                in: url,
                skip: skip,
                count: limit,
                author: author.isEmpty ? nil : author,
                since: since,
                until: until
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadGeneration == gen else { return }
                self.commits.append(contentsOf: newCommits)
                self.loadedCount += newCommits.count
                self.hasMore = newCommits.count == limit
                self.isLoading = false
            }
        }
    }
}
