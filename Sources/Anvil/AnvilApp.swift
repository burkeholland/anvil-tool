import SwiftUI

@main
struct AnvilApp: App {
    init() {
        // Register default values so preferences are enabled out of the box.
        UserDefaults.standard.register(defaults: [
            UserDefaultsKeys.playSoundOnAgentFinish: true,
            UserDefaultsKeys.agentFinishSoundName: AgentSoundOption.glass.rawValue,
            UserDefaultsKeys.showNotificationOnAgentFinish: true
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsWindowManager.shared.open()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
