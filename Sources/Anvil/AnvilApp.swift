import SwiftUI
import UserNotifications

@main
struct AnvilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            ViewCommands()
            FileCommands()
            HelpCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Notification posted when a directory is opened via macOS `open` command or drag-to-dock.
    static let openDirectoryNotification = Notification.Name("dev.anvil.openDirectory")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AgentNotificationManager.requestAuthorization()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                NotificationCenter.default.post(
                    name: Self.openDirectoryNotification,
                    object: nil,
                    userInfo: ["url": url]
                )
                return
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Posted on `NotificationCenter.default` when the user clicks a notification
    /// that is associated with a specific terminal tab.  The `userInfo` dictionary
    /// contains `"tabID"` (a `UUID`).
    static let focusTerminalTabNotification = Notification.Name("dev.anvil.focusTerminalTab")

    /// Bring Anvil to the foreground when the user clicks a notification.
    /// If the notification carries a tab ID, also post `focusTerminalTabNotification`
    /// so ContentView can switch to the relevant terminal tab.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        let userInfo = response.notification.request.content.userInfo
        if let tabIDString = userInfo[AgentNotificationManager.tabIDUserInfoKey] as? String,
           let tabID = UUID(uuidString: tabIDString) {
            NotificationCenter.default.post(
                name: Self.focusTerminalTabNotification,
                object: nil,
                userInfo: ["tabID": tabID]
            )
        }
        completionHandler()
    }

    /// Suppress banners while Anvil is already the frontmost app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(NSApp.isActive ? [] : [.banner, .sound])
    }
}
