import Foundation
import AppKit
import UserNotifications

/// Manages system notifications and audio alerts for agent task completion.
class AgentNotificationManager: NSObject, ObservableObject {

    static let shared = AgentNotificationManager()

    private override init() {
        super.init()
        requestNotificationPermissions()
    }

    // MARK: - Notification Permissions

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Task Completion

    /// Called when the agent transitions from active to idle.
    func notifyAgentFinished() {
        playCompletionSoundIfEnabled()
        postNotificationIfEnabled()
    }

    // MARK: - Sound

    /// Plays the user-selected system sound if the sound preference is enabled.
    func playCompletionSoundIfEnabled() {
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.playSoundOnAgentFinish) else { return }
        let soundName = UserDefaults.standard.string(forKey: UserDefaultsKeys.agentFinishSoundName)
            ?? AgentSoundOption.glass.rawValue
        NSSound(named: soundName)?.play()
    }

    // MARK: - macOS Notification

    private func postNotificationIfEnabled() {
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.showNotificationOnAgentFinish) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Agent Finished"
        content.body = "The Copilot agent has completed its task."
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
