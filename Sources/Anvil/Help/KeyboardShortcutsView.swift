import SwiftUI

/// A categorized reference of all keyboard shortcuts — both Anvil's own
/// and the Copilot CLI's — presented as a floating overlay.
struct KeyboardShortcutsView: View {
    var onDismiss: () -> Void

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

            // Two-column layout: Anvil on left, Copilot CLI on right
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 24) {
                    // Left column: Anvil shortcuts
                    VStack(alignment: .leading, spacing: 16) {
                        shortcutSection("Navigation", shortcuts: [
                            ("⌘⇧P", "Command Palette"),
                            ("⌘⇧O", "Quick Open File"),
                            ("⌘⇧F", "Find in Project"),
                            ("⌘F", "Find in Terminal"),
                            ("⌘B", "Toggle Sidebar"),
                        ])

                        shortcutSection("Sidebar Tabs", shortcuts: [
                            ("⌘1", "Files"),
                            ("⌘2", "Changes"),
                            ("⌘3", "Activity"),
                            ("⌘4", "Search"),
                        ])

                        shortcutSection("Code Review", shortcuts: [
                            ("⌘⇧D", "Review All Changes"),
                            ("⌃⌘↓", "Next Changed File"),
                            ("⌃⌘↑", "Previous Changed File"),
                        ])

                        shortcutSection("Terminal", shortcuts: [
                            ("⌘T", "New Terminal Tab"),
                            ("⌘+", "Increase Font Size"),
                            ("⌘−", "Decrease Font Size"),
                            ("⌘0", "Reset Font Size"),
                        ])

                        shortcutSection("File", shortcuts: [
                            ("⌘O", "Open Directory"),
                            ("⌘W", "Close Tab"),
                            ("⌘⇧W", "Close Project"),
                            ("⌘⇧R", "Refresh"),
                        ])
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // Right column: Copilot CLI shortcuts
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader("Copilot CLI", icon: "apple.terminal")

                        shortcutSection("Input", shortcuts: [
                            ("Enter", "Submit prompt"),
                            ("⌃S", "Run (keep input)"),
                            ("⇧↵", "New line"),
                            ("↑ / ↓", "History navigation"),
                            ("Esc", "Cancel generation"),
                        ])

                        shortcutSection("Modes", shortcuts: [
                            ("⇧⇥", "Cycle mode (Ask → Edit → Agent)"),
                            ("⌃T", "Toggle reasoning traces"),
                        ])

                        shortcutSection("Timeline", shortcuts: [
                            ("⌃O", "Open timeline"),
                            ("⌃E", "Expand timeline"),
                        ])

                        shortcutSection("Session", shortcuts: [
                            ("⌃C", "Cancel / Clear / Exit"),
                            ("⌃D", "Shutdown"),
                            ("⌃L", "Clear screen"),
                        ])

                        shortcutSection("Slash Commands", shortcuts: [
                            ("/help", "Show help"),
                            ("/diff", "View current diff"),
                            ("/compact", "Compact context"),
                            ("/model", "Switch model"),
                            ("/review", "Code review"),
                            ("/context", "Manage context"),
                        ])
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
        }
        .frame(width: 620, height: 520)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }

    // MARK: - Components

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
    private func shortcutSection(_ title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(shortcuts, id: \.0) { key, label in
                shortcutRow(key: key, label: label)
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
