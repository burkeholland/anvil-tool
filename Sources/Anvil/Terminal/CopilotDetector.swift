import Foundation

/// Detects whether the GitHub Copilot CLI (`copilot`) is available on the system.
enum CopilotDetector {

    /// Checks if `copilot` is reachable from the user's login shell.
    /// Runs asynchronously on a background queue; safe to call from any thread.
    /// Returns within 3 seconds even if the shell hangs.
    static func isAvailable() -> Bool {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // Login shell (-l) so the user's PATH is fully configured.
        process.arguments = ["-l", "-c", "command -v copilot > /dev/null 2>&1"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            return false
        }

        if semaphore.wait(timeout: .now() + 3.0) == .timedOut {
            process.terminate()
            return false
        }

        return process.terminationStatus == 0
    }
}
