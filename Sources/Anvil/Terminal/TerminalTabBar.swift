import SwiftUI

/// Tab bar for switching between terminal sessions.
struct TerminalTabBar: View {
    @ObservedObject var model: TerminalTabsModel
    var onNewTab: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(model.tabs) { tab in
                        TerminalTabItem(
                            tab: tab,
                            isActive: tab.id == model.activeTabID,
                            isOnly: model.tabs.count == 1,
                            onSelect: { model.selectTab(tab.id) },
                            onClose: { model.closeTab(tab.id) }
                        )
                    }
                }
            }

            Spacer()

            Button {
                onNewTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Terminal Tab (⌘T)")
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
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tab.launchCopilot ? "sparkle" : "terminal")
                .font(.system(size: 10))
                .foregroundStyle(tab.launchCopilot && isActive ? .purple : .secondary)

            Text(tab.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)

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
    }
}
