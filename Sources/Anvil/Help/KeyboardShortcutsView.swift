import SwiftUI

/// A categorized reference of all keyboard shortcuts — both Anvil's own
/// and the Copilot CLI's — presented as a floating overlay.
struct KeyboardShortcutsView: View {
    var onDismiss: () -> Void

    @State private var searchText = ""
    @State private var collapsedSections: Set<String> = []

    // MARK: - Data model

    private struct ShortcutItem: Identifiable {
        let id = UUID()
        let key: String
        let label: String
    }

    private struct ShortcutSection: Identifiable {
        let id: String
        let title: String
        let shortcuts: [ShortcutItem]
    }

    private let anvilSections: [ShortcutSection] = [
        ShortcutSection(id: "anvil-navigation", title: "Navigation", shortcuts: [
            ShortcutItem(key: "⌘⇧P", label: "Command Palette"),
            ShortcutItem(key: "⌘⇧O", label: "Quick Open File"),
            ShortcutItem(key: "⌘⇧F", label: "Find in Project"),
            ShortcutItem(key: "⌘F", label: "Find in Terminal"),
            ShortcutItem(key: "⌘⇧J", label: "Reveal in File Tree"),
            ShortcutItem(key: "⌘⌃T", label: "Go to Test / Implementation"),
            ShortcutItem(key: "⌘B", label: "Toggle Sidebar"),
            ShortcutItem(key: "⌘\\", label: "Toggle Split Preview"),
        ]),
        ShortcutSection(id: "anvil-sidebar", title: "Sidebar Tabs", shortcuts: [
            ShortcutItem(key: "⌘1", label: "Files"),
            ShortcutItem(key: "⌘2", label: "Changes"),
            ShortcutItem(key: "⌘3", label: "Activity"),
            ShortcutItem(key: "⌘4", label: "Search"),
        ]),
        ShortcutSection(id: "anvil-review", title: "Code Review", shortcuts: [
            ShortcutItem(key: "⌘⇧D", label: "Review All Changes"),
            ShortcutItem(key: "⌃⌘↓", label: "Next Changed File"),
            ShortcutItem(key: "⌃⌘↑", label: "Previous Changed File"),
            ShortcutItem(key: "N", label: "Next Unreviewed File"),
            ShortcutItem(key: "P", label: "Previous Unreviewed File"),
            ShortcutItem(key: "R", label: "Toggle File Reviewed"),
            ShortcutItem(key: "⌘L", label: "Go to Line"),
        ]),
        ShortcutSection(id: "anvil-terminal", title: "Terminal", shortcuts: [
            ShortcutItem(key: "⌘T", label: "New Shell Tab"),
            ShortcutItem(key: "⌘⇧T", label: "New Copilot Tab"),
            ShortcutItem(key: "⌘D", label: "Split Terminal Right"),
            ShortcutItem(key: "⌘⇧D", label: "Split Terminal Down"),
            ShortcutItem(key: "⌘⇧M", label: "Mention File in Terminal"),
            ShortcutItem(key: "⌘Y", label: "Prompt History"),
            ShortcutItem(key: "⌘+", label: "Increase Font Size"),
            ShortcutItem(key: "⌘−", label: "Decrease Font Size"),
            ShortcutItem(key: "⌘0", label: "Reset Font Size"),
            ShortcutItem(key: "⌘ click", label: "Open file path in preview"),
        ]),
        ShortcutSection(id: "anvil-file", title: "File", shortcuts: [
            ShortcutItem(key: "⌘O", label: "Open Directory"),
            ShortcutItem(key: "⌘W", label: "Close Tab"),
            ShortcutItem(key: "⌘⇧W", label: "Close Project"),
            ShortcutItem(key: "⌘⇧R", label: "Refresh"),
        ]),
    ]

    private let copilotSections: [ShortcutSection] = [
        ShortcutSection(id: "copilot-input", title: "Input", shortcuts: [
            ShortcutItem(key: "Enter", label: "Submit prompt"),
            ShortcutItem(key: "⌃S", label: "Run (keep input)"),
            ShortcutItem(key: "⇧↵", label: "New line"),
            ShortcutItem(key: "↑ / ↓", label: "History navigation"),
            ShortcutItem(key: "Esc", label: "Cancel generation"),
        ]),
        ShortcutSection(id: "copilot-modes", title: "Modes", shortcuts: [
            ShortcutItem(key: "⇧⇥", label: "Cycle mode (Ask → Edit → Agent)"),
            ShortcutItem(key: "⌃T", label: "Toggle reasoning traces"),
        ]),
        ShortcutSection(id: "copilot-timeline", title: "Timeline", shortcuts: [
            ShortcutItem(key: "⌃O", label: "Open timeline"),
            ShortcutItem(key: "⌃E", label: "Expand timeline"),
        ]),
        ShortcutSection(id: "copilot-session", title: "Session", shortcuts: [
            ShortcutItem(key: "⌃C", label: "Cancel / Clear / Exit"),
            ShortcutItem(key: "⌃D", label: "Shutdown"),
            ShortcutItem(key: "⌃L", label: "Clear screen"),
        ]),
        ShortcutSection(id: "copilot-slash", title: "Slash Commands", shortcuts: [
            ShortcutItem(key: "/help", label: "Show help"),
            ShortcutItem(key: "/diff", label: "View current diff"),
            ShortcutItem(key: "/compact", label: "Compact context"),
            ShortcutItem(key: "/model", label: "Switch model"),
            ShortcutItem(key: "/review", label: "Code review"),
            ShortcutItem(key: "/context", label: "Manage context"),
        ]),
    ]

    private func filteredSections(_ sections: [ShortcutSection]) -> [ShortcutSection] {
        guard !searchText.isEmpty else { return sections }
        let query = searchText.lowercased()
        return sections.compactMap { section in
            let matches = section.shortcuts.filter {
                $0.label.lowercased().contains(query) || $0.key.lowercased().contains(query)
            }
            return matches.isEmpty ? nil : ShortcutSection(id: section.id, title: section.title, shortcuts: matches)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("Keyboard Shortcuts")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Filter shortcuts…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Two-column layout: Anvil on left, Copilot CLI on right
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 24) {
                    // Left column: Anvil shortcuts
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader("Anvil", icon: "keyboard")
                        shortcutColumn(sections: filteredSections(anvilSections))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // Right column: Copilot CLI shortcuts
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader("Copilot CLI", icon: "apple.terminal")
                        shortcutColumn(sections: filteredSections(copilotSections))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
        }
        .frame(width: 620, height: 560)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }

    // MARK: - Components

    @ViewBuilder
    private func shortcutColumn(sections: [ShortcutSection]) -> some View {
        if sections.isEmpty {
            Text("No results")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    collapsibleShortcutSection(section)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.purple)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.purple)
        }
    }

    @ViewBuilder
    private func collapsibleShortcutSection(_ section: ShortcutSection) -> some View {
        let isCollapsed = collapsedSections.contains(section.id) && searchText.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if collapsedSections.contains(section.id) {
                    collapsedSections.remove(section.id)
                } else {
                    collapsedSections.insert(section.id)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(section.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
            .buttonStyle(.borderless)

            if !isCollapsed {
                ForEach(section.shortcuts) { item in
                    shortcutRow(key: item.key, label: item.label)
                }
            }
        }
    }

    @ViewBuilder
    private func shortcutRow(key: String, label: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}
