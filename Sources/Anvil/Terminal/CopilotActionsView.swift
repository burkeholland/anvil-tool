import SwiftUI

/// A popover providing quick access to Copilot CLI slash commands
/// and session controls, sent directly to the terminal.
struct CopilotActionsView: View {
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Copilot Actions", systemImage: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Slash Commands
                    ActionSection(title: "Commands") {
                        ActionRow(icon: "arrow.triangle.2.circlepath", label: "/compact", detail: "Compact conversation history") {
                            sendCommand("/compact")
                        }
                        ActionRow(icon: "doc.text", label: "/diff", detail: "Show current diff") {
                            sendCommand("/diff")
                        }
                        ActionRow(icon: "brain", label: "/model", detail: "Switch AI model") {
                            sendCommand("/model")
                        }
                        ActionRow(icon: "questionmark.circle", label: "/help", detail: "Show available commands") {
                            sendCommand("/help")
                        }
                        ActionRow(icon: "scope", label: "/context", detail: "Show context files") {
                            sendCommand("/context")
                        }
                        ActionRow(icon: "eye", label: "/review", detail: "Review changes") {
                            sendCommand("/review")
                        }
                        ActionRow(icon: "checklist", label: "/tasks", detail: "Show task list") {
                            sendCommand("/tasks")
                        }
                        ActionRow(icon: "clock.arrow.circlepath", label: "/session", detail: "Session information") {
                            sendCommand("/session")
                        }
                        ActionRow(icon: "doc.plaintext", label: "/instructions", detail: "View instructions") {
                            sendCommand("/instructions")
                        }
                    }

                    Divider()
                        .padding(.horizontal, 8)

                    // Controls
                    ActionSection(title: "Controls") {
                        ActionRow(icon: "arrow.left.arrow.right", label: "Cycle Mode", detail: "Interactive → Plan → Autopilot") {
                            // Shift+Tab sends ESC [ Z
                            terminalProxy.sendEscape("[Z")
                            onDismiss()
                        }
                        ActionRow(icon: "rectangle.and.pencil.and.ellipsis", label: "Toggle Reasoning", detail: "Ctrl+T") {
                            terminalProxy.sendControl(0x14) // Ctrl+T
                            onDismiss()
                        }
                        ActionRow(icon: "clear", label: "Clear Screen", detail: "Ctrl+L") {
                            terminalProxy.sendControl(0x0C) // Ctrl+L
                            onDismiss()
                        }
                        ActionRow(icon: "xmark.circle", label: "Cancel", detail: "Esc — cancel current action") {
                            terminalProxy.sendControl(0x1B) // Escape
                            onDismiss()
                        }
                    }

                    Divider()
                        .padding(.horizontal, 8)

                    // Session
                    ActionSection(title: "Session") {
                        ActionRow(icon: "arrow.counterclockwise", label: "Restart Copilot", detail: "Exit and relaunch the CLI") {
                            restartCopilot()
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 420)
    }

    private func sendCommand(_ command: String) {
        terminalProxy.send("\(command)\n")
        onDismiss()
    }

    private func restartCopilot() {
        // Send Ctrl+D to exit the Copilot CLI, then relaunch after a short delay
        terminalProxy.sendControl(0x04) // Ctrl+D
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            terminalProxy.send("copilot\n")
        }
        onDismiss()
    }
}

// MARK: - Subviews

private struct ActionSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 14)
                .padding(.bottom, 2)

            content()
        }
    }
}

private struct ActionRow: View {
    let icon: String
    let label: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
