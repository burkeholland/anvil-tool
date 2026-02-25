import Foundation

/// Represents a single terminal tab session.
struct TerminalTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    let launchCopilot: Bool
    /// The original title assigned at creation, used as fallback when terminal title is empty.
    let defaultTitle: String

    static func == (lhs: TerminalTab, rhs: TerminalTab) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages multiple terminal tabs with one active at a time.
final class TerminalTabsModel: ObservableObject {
    @Published var tabs: [TerminalTab] = []
    @Published var activeTabID: UUID?

    init(autoLaunchCopilot: Bool = true) {
        let title = autoLaunchCopilot ? "Copilot" : "Shell"
        let first = TerminalTab(
            id: UUID(),
            title: title,
            launchCopilot: autoLaunchCopilot,
            defaultTitle: title
        )
        tabs = [first]
        activeTabID = first.id
    }

    var activeTab: TerminalTab? {
        tabs.first { $0.id == activeTabID }
    }

    func addTab() {
        let shellCount = tabs.filter { !$0.launchCopilot }.count
        let title = shellCount == 0 ? "Shell" : "Shell \(shellCount + 1)"
        let tab = TerminalTab(id: UUID(), title: title, launchCopilot: false, defaultTitle: title)
        tabs.append(tab)
        activeTabID = tab.id
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        let wasActive = activeTabID == id
        tabs.removeAll { $0.id == id }
        if wasActive {
            activeTabID = tabs.last?.id
        }
    }

    func selectTab(_ id: UUID) {
        activeTabID = id
    }

    /// Update the title of a tab from terminal OSC title sequences.
    func updateTitle(for id: UUID, to newTitle: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle: String
        if trimmed.isEmpty {
            // Terminal cleared its title — revert to default
            displayTitle = tabs[index].defaultTitle
        } else {
            // Truncate long titles for tab bar readability
            displayTitle = trimmed.count > 30 ? String(trimmed.prefix(30)) + "…" : trimmed
        }
        if tabs[index].title != displayTitle {
            tabs[index].title = displayTitle
        }
    }

    /// Reset to a single tab (used when switching projects).
    func reset(autoLaunchCopilot: Bool = true) {
        let title = autoLaunchCopilot ? "Copilot" : "Shell"
        let first = TerminalTab(
            id: UUID(),
            title: title,
            launchCopilot: autoLaunchCopilot,
            defaultTitle: title
        )
        tabs = [first]
        activeTabID = first.id
    }
}
