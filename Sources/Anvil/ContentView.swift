#if os(macOS)
import SwiftUI

/// Root view for Anvil. Shows an `EmbeddedTerminalView` in the centre with a
/// task-complete banner that appears when the Copilot CLI returns to its input
/// prompt.
///
/// Banner logic (line ~177):
///   - **Primary**: `isCopilotPromptVisible` from `TerminalPromptDetector`
///     (fires instantly when the Copilot ">" prompt line appears in the buffer).
///   - **Fallback** (non-Copilot tabs): `ActivityFeedModel.isAgentActive`
///     quiescence timer (~10 s after last file change).
struct ContentView: View {

    // MARK: - Environment / Models

    @StateObject private var activityFeedModel = ActivityFeedModel()

    // MARK: - Local state

    @State private var workingDirectory: String = FileManager.default.currentDirectoryPath
    @State private var isCopilotTab: Bool = true

    /// Whether the Copilot prompt is currently visible in the terminal buffer.
    /// Updated by `TerminalPromptDetector` via the `EmbeddedTerminalView` callback.
    @State private var isCopilotPromptVisible: Bool = false

    /// Controls the task-complete banner.
    @State private var showTaskBanner: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            terminalArea

            // Task-complete banner (line ~177 of ContentView)
            if showTaskBanner {
                taskBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        // Start file-activity watching for the fallback heuristic.
        .onAppear {
            activityFeedModel.startWatching(directory: workingDirectory)
        }
        // Fallback: non-Copilot tabs rely on file-activity quiescence.
        .onChange(of: activityFeedModel.isAgentActive) { _, newValue in
            if !isCopilotTab && !newValue {
                AgentNotificationManager.shared.handleAgentBecameInactive()
                showBanner()
            }
        }
        // Primary: Copilot tabs use prompt detection for instant completion.
        .onChange(of: isCopilotPromptVisible) { _, newValue in
            if isCopilotTab && newValue {
                AgentNotificationManager.shared.handleCopilotPromptAppeared()
                showBanner()
            }
        }
    }

    // MARK: - Subviews

    private var terminalArea: some View {
        EmbeddedTerminalView(
            workingDirectory: workingDirectory,
            isCopilotTab: isCopilotTab,
            onPromptVisibilityChanged: { visible in
                isCopilotPromptVisible = visible
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Task-complete banner (~line 177)

    private var taskBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Task complete — Copilot is ready")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button {
                withAnimation { showTaskBanner = false }
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func showBanner() {
        withAnimation {
            showTaskBanner = true
        }
        // Auto-dismiss after 8 seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            withAnimation {
                showTaskBanner = false
            }
        }
    }
}

#Preview {
    ContentView()
}
#endif
