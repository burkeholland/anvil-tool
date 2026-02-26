import Foundation
import CryptoKit

/// A single entry in the prompt history.
struct PromptEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let date: Date
}

/// Persists and retrieves the history of prompts sent to the Copilot terminal.
/// Each project has its own history stored as a JSON file in Application Support.
final class PromptHistoryStore: ObservableObject {
    @Published private(set) var entries: [PromptEntry] = []

    private let maxEntries = 200
    private var storageURL: URL?

    /// (Re-)loads history for the given project path.
    /// Pass `nil` to reset to an empty in-memory history without touching disk.
    func configure(projectPath: String?) {
        storageURL = projectPath.flatMap { path in
            let filename = Self.sha256Filename(for: path)
            return Self.appSupportDirectory?
                .appendingPathComponent("PromptHistory")
                .appendingPathComponent("\(filename).json")
        }
        load()
    }

    /// Records a new prompt at the top of the history list.
    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = PromptEntry(id: UUID(), text: trimmed, date: Date())
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    /// Removes a single entry from the history.
    func remove(_ entry: PromptEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Removes all entries from the history.
    func clearAll() {
        entries = []
        save()
    }

    // MARK: - Persistence

    private static var appSupportDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Anvil")
    }

    /// Returns a 64-character hex SHA-256 digest of `path`, safe to use as a filename.
    private static func sha256Filename(for path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func save() {
        guard let url = storageURL else { return }
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            // Non-fatal: history is available in-memory even if persistence fails
        }
    }

    private func load() {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([PromptEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }
}
