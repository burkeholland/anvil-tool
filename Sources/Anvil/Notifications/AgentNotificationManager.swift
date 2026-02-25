#if os(macOS)
import Foundation
import UserNotifications

/// Manages macOS notifications when the Copilot agent finishes a task.
///
/// **Primary trigger** (Copilot tabs): `isCopilotPromptVisible` from
/// `EmbeddedTerminalView` / `TerminalPromptDetector`. A notification fires
/// immediately when the Copilot prompt becomes visible.
///
/// **Fallback trigger** (non-Copilot tabs): `ActivityFeedModel.isAgentActive`
/// quiescence timer (fires ~10 s after the last file change).
final class AgentNotificationManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AgentNotificationManager()

    // MARK: - Published state

    @Published private(set) var lastNotificationDate: Date?

    // MARK: - Private

    private var notificationsAuthorized = false

    /// Minimum interval between successive notifications to avoid flooding.
    private let minimumNotificationInterval: TimeInterval = 5.0

    private init() {
        requestAuthorization()
    }

    // MARK: - Authorization

    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.notificationsAuthorized = granted
        }
    }

    // MARK: - Primary trigger: Copilot prompt visible

    /// Call this when `EmbeddedTerminalView.isCopilotPromptVisible` transitions
    /// to `true`. Fires a notification immediately (no quiescence delay).
    func handleCopilotPromptAppeared() {
        sendNotification(
            title: "Task Complete",
            body: "Copilot has returned to the input prompt."
        )
    }

    // MARK: - Fallback trigger: file-activity quiescence

    /// Call this when `ActivityFeedModel.isAgentActive` transitions to `false`
    /// for a non-Copilot terminal tab.
    func handleAgentBecameInactive() {
        sendNotification(
            title: "Agent Idle",
            body: "No file activity detected for the past 10 seconds."
        )
    }

    // MARK: - Internal

    private func sendNotification(title: String, body: String) {
        guard notificationsAuthorized else { return }

        // Debounce: don't send if we just sent one recently.
        if let last = lastNotificationDate,
           Date().timeIntervalSince(last) < minimumNotificationInterval {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        lastNotificationDate = Date()
    }
}
#endif
