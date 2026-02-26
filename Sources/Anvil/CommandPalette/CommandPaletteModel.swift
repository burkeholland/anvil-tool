import Foundation

/// A single command that can be executed from the command palette.
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let icon: String
    let shortcut: String?
    let category: String
    /// When non-nil, the palette shows a secondary text-input prompt before executing.
    /// The placeholder text describes the expected argument (e.g. "Model name (optional)").
    let argumentPrompt: String?
    let isAvailable: () -> Bool
    let action: () -> Void
    /// Called instead of `action` when the command has an `argumentPrompt`.
    /// Receives the text the user typed (may be empty).
    let actionWithArgument: ((String) -> Void)?

    init(
        id: String,
        title: String,
        icon: String,
        shortcut: String?,
        category: String,
        argumentPrompt: String? = nil,
        isAvailable: @escaping () -> Bool,
        action: @escaping () -> Void,
        actionWithArgument: ((String) -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.category = category
        self.argumentPrompt = argumentPrompt
        self.isAvailable = isAvailable
        self.action = action
        self.actionWithArgument = actionWithArgument
    }
}

/// A matched command with a fuzzy search score.
struct PaletteResult: Identifiable {
    let command: PaletteCommand
    let score: Int

    var id: String { command.id }
}

/// Manages the command registry and fuzzy search for the command palette.
final class CommandPaletteModel: ObservableObject {
    @Published var query: String = "" {
        didSet { performSearch() }
    }
    @Published private(set) var results: [PaletteResult] = []
    @Published var selectedIndex: Int = 0
    /// Set when the selected command requires an argument before executing.
    @Published var pendingCommand: PaletteCommand? = nil
    /// The argument text typed in the secondary input prompt.
    @Published var argumentInput: String = ""

    private var commands: [PaletteCommand] = []

    func register(_ commands: [PaletteCommand]) {
        self.commands = commands
        performSearch()
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }

    func reset() {
        query = ""
        selectedIndex = 0
        pendingCommand = nil
        argumentInput = ""
    }

    var selectedResult: PaletteResult? {
        guard selectedIndex >= 0 && selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    /// Executes the selected command, or enters the argument-prompt phase if the command requires one.
    func executeSelected() {
        guard let result = selectedResult else { return }
        if result.command.argumentPrompt != nil {
            pendingCommand = result.command
            argumentInput = ""
        } else {
            result.command.action()
        }
    }

    /// Confirms the argument input and executes the pending command.
    func confirmArgument() {
        guard let cmd = pendingCommand else { return }
        if let handler = cmd.actionWithArgument {
            handler(argumentInput)
        } else {
            cmd.action()
        }
        pendingCommand = nil
        argumentInput = ""
    }

    /// Cancels the argument-prompt phase and returns to the command list.
    func cancelArgument() {
        pendingCommand = nil
        argumentInput = ""
    }

    // MARK: - Fuzzy Search

    private func performSearch() {
        selectedIndex = 0
        let available = commands.filter { $0.isAvailable() }

        guard !query.isEmpty else {
            results = available.map { PaletteResult(command: $0, score: 0) }
            return
        }

        let queryLower = query.lowercased()
        var scored: [(PaletteCommand, Int)] = []

        for cmd in available {
            let titleLower = cmd.title.lowercased()
            let catLower = cmd.category.lowercased()
            let combined = catLower + " " + titleLower

            if let score = fuzzyScore(query: queryLower, target: titleLower) {
                scored.append((cmd, score))
            } else if let score = fuzzyScore(query: queryLower, target: combined) {
                scored.append((cmd, score / 2))
            }
        }

        scored.sort { $0.1 > $1.1 }
        results = scored.map { PaletteResult(command: $0.0, score: $0.1) }
    }

    /// Scores a fuzzy match of query characters against a target string.
    /// Returns nil if no match. Higher scores = better match.
    private func fuzzyScore(query: String, target: String) -> Int? {
        guard !query.isEmpty else { return 0 }

        var score = 0
        var queryIndex = query.startIndex
        var targetIndex = target.startIndex
        var lastMatchIndex: String.Index?
        var consecutiveMatches = 0

        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            if query[queryIndex] == target[targetIndex] {
                score += 1

                if let last = lastMatchIndex, target.index(after: last) == targetIndex {
                    consecutiveMatches += 1
                    score += consecutiveMatches * 3
                } else {
                    consecutiveMatches = 0
                }

                if targetIndex == target.startIndex {
                    score += 10
                } else {
                    let prev = target[target.index(before: targetIndex)]
                    if prev == " " || prev == ":" || prev == "-" || prev == "_" {
                        score += 8
                    }
                }

                lastMatchIndex = targetIndex
                queryIndex = query.index(after: queryIndex)
            }
            targetIndex = target.index(after: targetIndex)
        }

        guard queryIndex == query.endIndex else { return nil }

        // Shorter titles get a bonus (more precise match)
        score += max(0, 30 - target.count)

        return score
    }
}
