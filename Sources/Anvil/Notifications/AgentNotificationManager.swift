import Foundation
import AppKit
import Combine
import UserNotifications

/// Sends native macOS notifications when the Copilot CLI finishes work and
/// Anvil is not the frontmost application. Detects completion via:
/// 1. Git commits (immediate notification with commit message)
/// 2. File activity quiescence (notification after a pause in file changes)
final class AgentNotificationManager {
    private var cancellables = Set<AnyCancellable>()
    private var quiescenceTimer: Timer?
    private var pendingChangedFiles: [String] = []
    private var lastNotificationDate = Date.distantPast
    private var lastProcessedCount = 0

    /// Minimum seconds between file-change notifications.
    private let cooldown: TimeInterval = 10
    /// Seconds of silence after file activity before notifying.
    private let quiescenceDelay: TimeInterval = 8

    private static let enabledKey = "notificationsEnabled"

    init() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
    }

    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    // MARK: - Setup

    func connect(to activityModel: ActivityFeedModel) {
        cancellables.removeAll()
        lastProcessedCount = activityModel.events.count

        activityModel.$events
            .receive(on: RunLoop.main)
            .sink { [weak self, weak activityModel] _ in
                guard let self, let model = activityModel else { return }
                self.processNewEvents(model.events)
            }
            .store(in: &cancellables)

        // Clear pending state when the user brings Anvil to the foreground
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.pendingChangedFiles.removeAll()
                self?.quiescenceTimer?.invalidate()
            }
            .store(in: &cancellables)
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    // MARK: - Event Processing

    private func processNewEvents(_ events: [ActivityEvent]) {
        let newCount = events.count
        defer { lastProcessedCount = newCount }

        guard newCount > lastProcessedCount else {
            // Events were cleared or trimmed
            pendingChangedFiles.removeAll()
            quiescenceTimer?.invalidate()
            return
        }

        guard enabled, !NSApp.isActive else {
            pendingChangedFiles.removeAll()
            quiescenceTimer?.invalidate()
            return
        }

        let newEvents = events[lastProcessedCount..<newCount]

        for event in newEvents {
            switch event.kind {
            case .gitCommit(let message, let sha):
                quiescenceTimer?.invalidate()
                pendingChangedFiles.removeAll()
                // Commit notifications bypass cooldown — they're the primary completion signal
                deliver(
                    title: "Copilot committed",
                    body: message,
                    identifier: "commit-\(sha)"
                )

            case .fileCreated, .fileModified, .fileDeleted, .fileRenamed:
                pendingChangedFiles.append(event.fileName)
                resetQuiescenceTimer()
            }
        }
    }

    // MARK: - Quiescence Detection

    private func resetQuiescenceTimer() {
        quiescenceTimer?.invalidate()
        quiescenceTimer = Timer.scheduledTimer(
            withTimeInterval: quiescenceDelay, repeats: false
        ) { [weak self] _ in
            self?.onQuiescence()
        }
    }

    private func onQuiescence() {
        guard !pendingChangedFiles.isEmpty, enabled, !NSApp.isActive else {
            pendingChangedFiles.removeAll()
            return
        }

        let count = pendingChangedFiles.count
        let uniqueNames = Array(Set(pendingChangedFiles))

        let body: String
        if uniqueNames.count <= 3 {
            body = uniqueNames.joined(separator: ", ")
        } else {
            let shown = uniqueNames.prefix(3).joined(separator: ", ")
            body = "\(shown) and \(uniqueNames.count - 3) more"
        }

        pendingChangedFiles.removeAll()
        send(
            title: "\(count) file\(count == 1 ? "" : "s") changed",
            body: body,
            identifier: "quiescence-\(UUID().uuidString)"
        )
    }

    // MARK: - Notification Delivery

    /// Delivers a notification immediately (used for git commits).
    private func deliver(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        lastNotificationDate = Date()
    }

    /// Delivers a notification subject to cooldown (used for file-change summaries).
    private func send(title: String, body: String, identifier: String) {
        guard Date().timeIntervalSince(lastNotificationDate) >= cooldown else { return }
        deliver(title: title, body: body, identifier: identifier)
    }
}
