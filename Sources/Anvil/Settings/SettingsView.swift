import SwiftUI
import AppKit

/// The main settings window for Anvil.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            NotificationsSettingsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
        }
        .frame(width: 480)
        .padding()
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Text("General settings coming soon.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

// MARK: - Notifications Settings

struct NotificationsSettingsView: View {
    @AppStorage(UserDefaultsKeys.playSoundOnAgentFinish) private var playSoundOnFinish: Bool = true
    @AppStorage(UserDefaultsKeys.agentFinishSoundName) private var selectedSoundName: String = AgentSoundOption.glass.rawValue
    @AppStorage(UserDefaultsKeys.showNotificationOnAgentFinish) private var showNotificationOnFinish: Bool = true

    var body: some View {
        Form {
            Section("Agent Task Completion") {
                Toggle("Show notification when agent finishes", isOn: $showNotificationOnFinish)

                Toggle("Play sound when agent finishes", isOn: $playSoundOnFinish)

                Picker("Sound", selection: $selectedSoundName) {
                    ForEach(AgentSoundOption.allCases) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .disabled(!playSoundOnFinish)

                Button("Preview Sound") {
                    NSSound(named: selectedSoundName)?.play()
                }
                .disabled(!playSoundOnFinish)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
