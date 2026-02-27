import Foundation
import AppKit
import UserNotifications

/// Sends native macOS notifications when the Copilot CLI finishes work and
/// Anvil is not the frontmost application.
final class AgentNotificationManager {
    private var lastNotificationDate = Date.distantPast

    /// Minimum seconds between notifications.
    private let cooldown: TimeInterval = 10

    private static let enabledKey = "notificationsEnabled"

    init() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
    }

    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    static func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    // MARK: - Task-Complete Notification

    /// Sends a task-complete notification summarising the agent's work.
    func notifyTaskComplete(
        changedFileCount: Int,
        buildStatus: BuildVerifier.Status,
        testStatus: TestRunner.Status
    ) {
        guard enabled, !NSApp.isActive else { return }

        var parts: [String] = []
        if changedFileCount > 0 {
            parts.append("\(changedFileCount) file\(changedFileCount == 1 ? "" : "s") changed")
        }
        switch buildStatus {
        case .passed:
            parts.append("Build passed")
        case .failed:
            parts.append("Build failed")
        default:
            break
        }
        switch testStatus {
        case .passed(let total):
            parts.append(total > 0 ? "Tests passed (\(total))" : "Tests passed")
        case .failed(let failedTests, _):
            parts.append(failedTests.isEmpty ? "Tests failed" : "Tests failed (\(failedTests.count))")
        default:
            break
        }

        let body = parts.isEmpty ? "The Copilot agent has finished." : parts.joined(separator: " · ")
        deliver(
            title: "Agent task complete",
            body: body,
            identifier: "task-complete"
        )
    }

    // MARK: - Waiting-for-Input Notification

    /// Key stored in `UNNotificationContent.userInfo` when a notification is associated
    /// with a specific terminal tab.  The value is the tab's UUID string.
    static let tabIDUserInfoKey = "dev.anvil.tabID"

    /// Sends a notification telling the user that the agent is waiting for their
    /// input in the named terminal tab.
    func notifyWaitingForInput(tabID: UUID, tabTitle: String) {
        guard enabled, !NSApp.isActive else { return }
        deliver(
            title: "Agent needs input",
            body: "Waiting for your response in \"\(tabTitle)\"",
            identifier: "waiting-input-\(tabID.uuidString)",
            tabID: tabID
        )
    }

    // MARK: - Notification Delivery

    private func deliver(title: String, body: String, identifier: String, tabID: UUID? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let tabID {
            content.userInfo = [Self.tabIDUserInfoKey: tabID.uuidString]
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().add(request)
        lastNotificationDate = Date()
    }
}
