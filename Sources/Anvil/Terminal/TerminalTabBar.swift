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

            // Browser-style + tab at end of tab row
            AddTabButton(
                onNewCopilotTab: onNewCopilotTab,
                onNewShellTab: onNewShellTab
            )

            Spacer()

            // Split / additional options overflow menu
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

                Divider()

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

                if model.isSplit {
                    Button {
                        onCloseSplit()
                    } label: {
                        Label("Close Split", systemImage: "rectangle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("More Options")
            .padding(.trailing, 10)
        }
        .frame(height: 48)
        .background(Color(nsColor: NSColor(red: 0.09, green: 0.08, blue: 0.08, alpha: 1.0)))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

/// Browser-style `+` tab button at the end of the tab row.
/// Single-click creates a new Copilot tab; right-click or long-press shows a
/// menu to choose between a Copilot tab and a Shell tab.
private struct AddTabButton: View {
    var onNewCopilotTab: () -> Void
    var onNewShellTab: () -> Void

    @State private var isHovering = false
    @State private var showMenu = false
    /// Set by the long-press gesture before mouse-up fires the tap handler,
    /// allowing the tap to be suppressed when a long press was detected.
    @State private var didLongPress = false

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isHovering ? .primary.opacity(0.8) : .secondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovering ? Color.primary.opacity(0.07) : Color.clear)
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture {
                if !didLongPress {
                    onNewCopilotTab()
                }
                didLongPress = false
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        didLongPress = true
                        showMenu = true
                    }
            )
            // Reset long-press flag whenever the popover is dismissed so that
            // subsequent single-clicks work correctly even if mouse-up was not
            // delivered after the long press (e.g. release outside the view).
            .onChange(of: showMenu) { isShowing in
                if !isShowing { didLongPress = false }
            }
            .contextMenu {
                newTabMenuItems
            }
            .popover(isPresented: $showMenu, arrowEdge: .top) {
                NewTabPopoverContent(
                    onNewCopilotTab: { onNewCopilotTab(); showMenu = false },
                    onNewShellTab: { onNewShellTab(); showMenu = false }
                )
            }
            .help("New Copilot Tab (right-click or hold for options)")
    }

    /// Items used by the native context menu (right-click).
    @ViewBuilder private var newTabMenuItems: some View {
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
    }
}

/// Content displayed inside the long-press popover for `AddTabButton`.
private struct NewTabPopoverContent: View {
    private let items: [(title: String, icon: String, action: () -> Void)]

    init(onNewCopilotTab: @escaping () -> Void, onNewShellTab: @escaping () -> Void) {
        items = [
            ("New Copilot Tab", "sparkle", onNewCopilotTab),
            ("New Shell Tab", "terminal", onNewShellTab),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.title) { item in
                Button(action: item.action) {
                    Label(item.title, systemImage: item.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 4)
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

    /// The primary label shown in the tab — session summary takes precedence over process title.
    private var displayTitle: String {
        tab.sessionSummary ?? tab.title
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.launchCopilot ? "sparkle" : "terminal")
                .font(.system(size: 11))
                .foregroundStyle(tab.launchCopilot && isActive ? .purple : .secondary)

            Text(displayTitle)
                .font(.system(size: 13, weight: isActive ? .medium : .regular))
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
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isActive
                ? Color.primary.opacity(0.10)
                : (isHovering ? Color.primary.opacity(0.04) : Color.clear)
        )
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(tab.launchCopilot ? Color.purple : Color.accentColor)
                    .frame(height: 3)
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
