import SwiftUI

struct ContentView: View {
    @StateObject private var activityModel = ActivityModel()
    @State private var showTaskBanner: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Task completion banner
            if showTaskBanner {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Agent finished task")
                        .font(.subheadline)
                    Spacer()
                    Button {
                        withAnimation {
                            showTaskBanner = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.green.opacity(0.12))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Agent status indicator
            HStack {
                Circle()
                    .fill(activityModel.isAgentActive ? .orange : .green)
                    .frame(width: 8, height: 8)
                Text(activityModel.isAgentActive ? "Agent active…" : "Agent idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.background.secondary)

            // Main content area (terminal placeholder)
            ZStack {
                Color(nsColor: .textBackgroundColor)
                VStack(spacing: 16) {
                    Image(systemName: "terminal")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Copilot Terminal")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Connect to the Copilot CLI to get started.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Debug controls (simulate agent activity)
            #if DEBUG
            HStack(spacing: 12) {
                Button("Simulate Start") {
                    activityModel.startTask()
                }
                .disabled(activityModel.isAgentActive)

                Button("Simulate Finish") {
                    activityModel.finishTask()
                }
                .disabled(!activityModel.isAgentActive)
            }
            .padding(8)
            .background(.background.secondary)
            #endif
        }
        // Wire audio alert and banner to agent active→idle transition
        .onChange(of: activityModel.isAgentActive) { oldValue, newValue in
            if oldValue == true && newValue == false {
                // Agent transitioned from active to idle
                withAnimation {
                    showTaskBanner = true
                }
                AgentNotificationManager.shared.notifyAgentFinished()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

/// Helper to open the Settings window programmatically.
class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private init() {}

    func open() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
