import SwiftUI

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
