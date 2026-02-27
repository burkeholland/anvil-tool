import Foundation

/// A past Copilot CLI session as returned by `copilot session list --json`.
struct CopilotSession: Identifiable, Decodable {
    let id: String
    let title: String?
    let date: Date?

    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        return id
    }
}

/// Fetches and manages the list of past Copilot sessions, and coordinates
/// opening them in terminal tabs.
final class SessionListModel: ObservableObject {
    @Published private(set) var sessions: [CopilotSession] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    /// Called when the user taps a session row to resume it in a terminal tab.
    var onOpenSession: ((String) -> Void)?

    /// Called when the user taps "New Session" to start a fresh Copilot tab.
    var onNewSession: (() -> Void)?

    // MARK: - Public API

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.fetchSessions()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let list):
                    self.sessions = list
                case .failure(let err):
                    self.errorMessage = err.localizedDescription
                    self.sessions = []
                }
            }
        }
    }

    func openSession(_ session: CopilotSession) {
        onOpenSession?(session.id)
    }

    func openNewSession() {
        onNewSession?()
    }

    // MARK: - CLI

    /// Runs `copilot session list --json` via a login shell and decodes the result.
    private static func fetchSessions() -> Result<[CopilotSession], Error> {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "copilot session list --json 2>/dev/null"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .failure(error)
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return .success([]) }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let list = try decoder.decode([CopilotSession].self, from: data)
            return .success(list)
        } catch {
            return .failure(error)
        }
    }
}
