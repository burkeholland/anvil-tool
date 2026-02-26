import SwiftUI

/// Floating action menu displayed at the top of the file preview when the user
/// has an active text selection. Provides quick actions that compose a contextual
/// prompt from the selected code and insert it into the terminal input.
struct SelectionActionMenu: View {
    /// Called with a human-readable intent string (e.g. "Ask about this") when
    /// the user taps an action button.
    var onAction: (String) -> Void

    var body: some View {
        HStack(spacing: 1) {
            ActionButton(label: "Ask about this", icon: "questionmark.circle", shortcutHint: "⌘⇧E") {
                onAction("Ask about this")
            }
            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)
            ActionButton(label: "Explain this", icon: "lightbulb") {
                onAction("Explain this")
            }
            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)
            ActionButton(label: "Improve this", icon: "wand.and.stars") {
                onAction("Improve this")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
    }
}

// MARK: - Subviews

private struct ActionButton: View {
    let label: String
    let icon: String
    var shortcutHint: String? = nil
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                if let hint = shortcutHint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(isHovered ? Color.accentColor : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
