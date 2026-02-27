import SwiftUI

/// Sidebar panel that lists past Copilot sessions and lets the user resume one
/// or start a fresh session.
struct SessionListView: View {
    @ObservedObject var model: SessionListModel
    /// IDs of sessions that are currently open in a terminal tab (highlighted).
    var activeSessionIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            Button(action: { model.openNewSession() }) {
                Label("New Session", systemImage: "plus.circle")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 7)
            }
            .buttonStyle(SessionNewButtonStyle())
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)

            Divider()

            sessionContent
        }
        .onAppear { model.refresh() }
    }

    // MARK: - Sub-views

    private var headerBar: some View {
        HStack {
            Text("Sessions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: { model.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .rotationEffect(model.isLoading ? .degrees(360) : .zero)
                    .animation(model.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: model.isLoading)
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading)
            .help("Refresh sessions")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    @ViewBuilder
    private var sessionContent: some View {
        if model.isLoading && model.sessions.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let errorMsg = model.errorMessage, model.sessions.isEmpty {
            VStack(spacing: Spacing.md) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)
                Button("Retry") { model.refresh() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if model.sessions.isEmpty {
            VStack(spacing: Spacing.md) {
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("No sessions found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Start a new Copilot session to see it here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.sessions) { session in
                        SessionRowView(
                            session: session,
                            isActive: activeSessionIDs.contains(session.id),
                            onTap: { model.openSession(session) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct SessionRowView: View {
    let session: CopilotSession
    let isActive: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(isActive ? Color.accentColor : .primary)
                        .lineLimit(1)
                    if let date = session.date {
                        Text(date, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if isActive {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(isHovering || isActive ? Color.primary.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Button style

private struct SessionNewButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.accentColor)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(isHovering || configuration.isPressed ? 0.15 : 0.08))
            )
            .onHover { isHovering = $0 }
    }
}
