import Foundation

/// Direction for a terminal split pane.
enum SplitDirection {
    case horizontal  // side-by-side (left | right)
    case vertical    // stacked (top / bottom)
}

/// Represents a single terminal tab session.
struct TerminalTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    let launchCopilot: Bool
    /// The original title assigned at creation, used as fallback when terminal title is empty.
    let defaultTitle: String
    /// A short summary describing the session's purpose, sourced from workspace.yaml.
    /// Shown as the primary label in the tab bar instead of the shell process title.
    var sessionSummary: String? = nil

    static func == (lhs: TerminalTab, rhs: TerminalTab) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages multiple terminal tabs with one active at a time, plus an optional split pane.
final class TerminalTabsModel: ObservableObject {
    @Published var tabs: [TerminalTab] = []
    @Published var activeTabID: UUID?
    /// The terminal session shown in the secondary split pane, or nil when not split.
    @Published var splitTab: TerminalTab? = nil
    /// The direction of the split when `splitTab` is non-nil.
    @Published var splitDirection: SplitDirection = .horizontal
    /// IDs of tabs (including the split tab) whose agent is currently blocked
    /// waiting for user input.
    @Published private(set) var waitingForInputTabIDs: Set<UUID> = []
    /// The current Copilot CLI agent mode detected from the active terminal.
    @Published var agentMode: AgentMode? = nil
    /// The current Copilot CLI model name detected from the active terminal.
    @Published var agentModel: String? = nil

    var isSplit: Bool { splitTab != nil }

    /// True when at least one tab (including the split pane) is waiting for input.
    var isAnyTabWaitingForInput: Bool { !waitingForInputTabIDs.isEmpty }

    /// Sets or clears the "waiting for input" flag for the given tab ID.
    func setWaitingForInput(_ waiting: Bool, tabID: UUID) {
        if waiting {
            waitingForInputTabIDs.insert(tabID)
        } else {
            waitingForInputTabIDs.remove(tabID)
        }
    }

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

    func addCopilotTab() {
        let copilotCount = tabs.filter(\.launchCopilot).count
        let title = copilotCount == 0 ? "Copilot" : "Copilot \(copilotCount + 1)"
        let tab = TerminalTab(id: UUID(), title: title, launchCopilot: true, defaultTitle: title)
        tabs.append(tab)
        activeTabID = tab.id
    }

    func closeOtherTabs(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        tabs.removeAll { $0.id != id }
        waitingForInputTabIDs = waitingForInputTabIDs.intersection([id])
        activeTabID = id
    }

    func closeTabsToRight(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = Set(tabs[(index + 1)...].map(\.id))
        tabs.removeSubrange((index + 1)...)
        waitingForInputTabIDs.subtract(removed)
        if let active = activeTabID, !tabs.contains(where: { $0.id == active }) {
            activeTabID = id
        }
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        let wasActive = activeTabID == id
        tabs.removeAll { $0.id == id }
        waitingForInputTabIDs.remove(id)
        if wasActive {
            activeTabID = tabs.last?.id
        }
    }

    func selectTab(_ id: UUID) {
        activeTabID = id
    }

    /// Split the terminal pane, creating a new shell (or Copilot) session in the second pane.
    /// If already split, only the direction is updated.
    func splitPane(copilot: Bool = false, direction: SplitDirection = .horizontal) {
        splitDirection = direction
        guard splitTab == nil else { return }
        if copilot {
            let copilotCount = tabs.filter(\.launchCopilot).count
            let title = copilotCount == 0 ? "Copilot" : "Copilot \(copilotCount + 1)"
            splitTab = TerminalTab(id: UUID(), title: title, launchCopilot: true, defaultTitle: title)
        } else {
            let shellCount = tabs.filter { !$0.launchCopilot }.count
            let title = shellCount == 0 ? "Shell" : "Shell \(shellCount + 1)"
            splitTab = TerminalTab(id: UUID(), title: title, launchCopilot: false, defaultTitle: title)
        }
    }

    /// Close the split pane, restoring the single-pane layout.
    func closeSplit() {
        if let id = splitTab?.id { waitingForInputTabIDs.remove(id) }
        splitTab = nil
    }

    /// Update the title of the split pane from terminal OSC title sequences.
    func updateSplitTitle(to newTitle: String) {
        guard let tab = splitTab else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle: String
        if trimmed.isEmpty {
            displayTitle = tab.defaultTitle
        } else {
            displayTitle = trimmed.count > 30 ? String(trimmed.prefix(30)) + "…" : trimmed
        }
        if splitTab?.title != displayTitle {
            splitTab?.title = displayTitle
        }
    }

    /// Set the session summary for a tab. The summary is shown as the primary
    /// label in the tab bar in place of the shell process title.
    func setSessionSummary(_ summary: String?, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = summary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        tabs[index].sessionSummary = (trimmed?.isEmpty == false) ? trimmed : nil
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
        splitTab = nil
        waitingForInputTabIDs = []
        agentMode = nil
        agentModel = nil
    }
}
