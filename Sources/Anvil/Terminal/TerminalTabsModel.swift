import Foundation

/// Represents a single terminal tab session.
struct TerminalTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    let launchCopilot: Bool

    static func == (lhs: TerminalTab, rhs: TerminalTab) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages multiple terminal tabs with one active at a time.
final class TerminalTabsModel: ObservableObject {
    @Published var tabs: [TerminalTab] = []
    @Published var activeTabID: UUID?

    init(autoLaunchCopilot: Bool = true) {
        let first = TerminalTab(
            id: UUID(),
            title: autoLaunchCopilot ? "Copilot" : "Shell",
            launchCopilot: autoLaunchCopilot
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
        let tab = TerminalTab(id: UUID(), title: title, launchCopilot: false)
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

    /// Reset to a single tab (used when switching projects).
    func reset(autoLaunchCopilot: Bool = true) {
        let first = TerminalTab(
            id: UUID(),
            title: autoLaunchCopilot ? "Copilot" : "Shell",
            launchCopilot: autoLaunchCopilot
        )
        tabs = [first]
        activeTabID = first.id
    }
}
