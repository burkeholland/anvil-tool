import SwiftUI

/// Tab bar for switching between terminal sessions.
/// Always visible to make terminal tabs discoverable.
struct TerminalTabBar: View {
    @ObservedObject var model: TerminalTabsModel
    var onNewShellTab: () -> Void
    var onNewCopilotTab: () -> Void
    var onSplitHorizontally: () -> Void
    var onSplitVertically: () -> Void
    var onCloseSplit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(model.tabs) { tab in
                        TerminalTabItem(
                            tab: tab,
                            isActive: tab.id == model.activeTabID,
                            isOnly: model.tabs.count == 1,
                            isWaitingForInput: model.waitingForInputTabIDs.contains(tab.id),
                            onSelect: { model.selectTab(tab.id) },
                            onClose: { model.closeTab(tab.id) },
                            onCloseOthers: { model.closeOtherTabs(tab.id) },
                            onCloseToRight: { model.closeTabsToRight(tab.id) }
                        )
                    }
                }
            }

            Spacer()

            // Split pane buttons
            if model.isSplit {
                Button {
                    onCloseSplit()
                } label: {
                    Image(systemName: "rectangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Split")
            } else {
                Menu {
                    Button {
                        onSplitHorizontally()
                    } label: {
                        Label("Split Right", systemImage: "rectangle.split.2x1")
                    }

                    Button {
                        onSplitVertically()
                    } label: {
                        Label("Split Down", systemImage: "rectangle.split.1x2")
                    }
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .help("Split Terminal")
            }

            Menu {
                Button {
                    onNewCopilotTab()
                } label: {
                    Label("New Copilot Tab", systemImage: "sparkle")
                }

                Button {
                    onNewShellTab()
                } label: {
                    Label("New Shell Tab", systemImage: "terminal")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("New Terminal Tab")
            .padding(.trailing, 6)
        }
        .frame(height: 30)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

private struct TerminalTabItem: View {
    let tab: TerminalTab
    let isActive: Bool
    let isOnly: Bool
    let isWaitingForInput: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseToRight: () -> Void
    @State private var isHovering = false
    @State private var isWaitingPulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tab.launchCopilot ? "sparkle" : "terminal")
                .font(.system(size: 10))
                .foregroundStyle(tab.launchCopilot && isActive ? .purple : .secondary)

            Text(tab.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)

            if isWaitingForInput {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isWaitingPulsing ? 1.4 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                        value: isWaitingPulsing
                    )
                    .onAppear { isWaitingPulsing = true }
                    .onDisappear { isWaitingPulsing = false }
            }

            if !isOnly {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isActive ? 1 : 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isActive
                ? Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0))
                : Color.clear
        )
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(tab.launchCopilot ? Color.purple : Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Close") { onClose() }
                .disabled(isOnly)
            Button("Close Other Tabs") { onCloseOthers() }
                .disabled(isOnly)
            Button("Close Tabs to the Right") { onCloseToRight() }
        }
        .help(tab.title != tab.defaultTitle ? "\(tab.defaultTitle): \(tab.title)" : tab.title)
    }
}
