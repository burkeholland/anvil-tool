import Foundation

/// Tracks files currently pinned to the Copilot CLI agent context via `/context add`.
/// Lives as a session-scoped @StateObject in ContentView and is wired to TerminalInputProxy.
final class ContextStore: ObservableObject {
    /// Relative paths (project-relative) of files currently in context, in insertion order.
    @Published private(set) var pinnedPaths: [String] = []

    /// Adds a relative path to the context, silently ignoring duplicates.
    func add(relativePath: String) {
        guard !relativePath.isEmpty, !pinnedPaths.contains(relativePath) else { return }
        pinnedPaths.append(relativePath)
    }

    /// Removes a relative path from the context (no-op if not present).
    func remove(relativePath: String) {
        pinnedPaths.removeAll { $0 == relativePath }
    }

    /// Returns true when the given path is currently pinned.
    func contains(relativePath: String) -> Bool {
        pinnedPaths.contains(relativePath)
    }

    /// Clears all pinned paths. Call when switching projects or starting a new session.
    func clear() {
        pinnedPaths = []
    }
}
