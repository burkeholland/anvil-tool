import Foundation
import AppKit

/// Represents an external code editor that can be launched from Anvil.
struct ExternalEditor: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String

    /// Opens a file (optionally at a line number) in this editor.
    func open(_ url: URL, line: Int? = nil) {
        switch id {
        case "vscode", "cursor", "zed", "sublime":
            let cliName: String
            switch id {
            case "vscode":  cliName = "code"
            case "cursor":  cliName = "cursor"
            case "zed":     cliName = "zed"
            case "sublime": cliName = "subl"
            default:        cliName = id
            }
            if !launchCLI(cliName, url: url, line: line) {
                // CLI not on PATH — fall back to opening via bundle
                launchBundle(url)
            }
        default:
            NSWorkspace.shared.open(url)
        }
    }

    /// Attempts to open via CLI tool. Returns false if the tool isn't available.
    @discardableResult
    private func launchCLI(_ command: String, url: URL, line: Int?) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        if let line = line {
            process.arguments = [command, "--goto", "\(url.path):\(line)"]
        } else {
            process.arguments = [command, url.path]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    /// Opens the file via the app bundle as a fallback.
    private func launchBundle(_ url: URL) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Detects installed editors and manages the user's preference.
enum ExternalEditorManager {

    static let knownEditors: [ExternalEditor] = [
        ExternalEditor(id: "vscode", name: "Visual Studio Code", bundleID: "com.microsoft.VSCode"),
        ExternalEditor(id: "cursor", name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
        ExternalEditor(id: "zed", name: "Zed", bundleID: "dev.zed.Zed"),
        ExternalEditor(id: "sublime", name: "Sublime Text", bundleID: "com.sublimetext.4"),
    ]

    /// Returns editors that are currently installed on this machine.
    static var installedEditors: [ExternalEditor] {
        knownEditors.filter { editor in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleID) != nil
        }
    }

    /// The user's preferred editor, falling back to the first installed editor or system default.
    static var preferred: ExternalEditor? {
        let preferredID = UserDefaults.standard.string(forKey: "preferredEditorID") ?? ""
        let installed = installedEditors
        return installed.first(where: { $0.id == preferredID }) ?? installed.first
    }

    /// Opens a file in the preferred editor.
    static func openFile(_ url: URL, line: Int? = nil) {
        if let editor = preferred {
            editor.open(url, line: line)
        } else {
            // Fallback: open with the system default application
            NSWorkspace.shared.open(url)
        }
    }
}
