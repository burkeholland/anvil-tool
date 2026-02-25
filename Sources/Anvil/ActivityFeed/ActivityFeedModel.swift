#if os(macOS)
import Foundation
import Combine

/// Tracks agent activity based on file-system changes (inotify / FSEvents).
///
/// `isAgentActive` becomes `true` when any file change is observed in the
/// working directory, and reverts to `false` after `quiescenceInterval` seconds
/// with no new changes.
///
/// This heuristic is used as a **fallback** for non-Copilot terminal tabs.
/// For Copilot tabs, `EmbeddedTerminalView.isCopilotPromptVisible` is the
/// primary signal for task completion.
final class ActivityFeedModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isAgentActive: Bool = false

    // MARK: - Configuration

    /// How long after the last file change before the agent is considered idle.
    let quiescenceInterval: TimeInterval

    // MARK: - Private

    private var workingDirectory: String?
    private var fileSystemSource: DispatchSourceFileSystemObject?
    private var quiescenceTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.anvil.ActivityFeedModel", qos: .utility)
    private var directoryFD: Int32 = -1

    // MARK: - Init / deinit

    init(quiescenceInterval: TimeInterval = 10.0) {
        self.quiescenceInterval = quiescenceInterval
    }

    deinit {
        stopWatching()
    }

    // MARK: - Public API

    func startWatching(directory: String) {
        stopWatching()
        workingDirectory = directory

        directoryFD = open(directory, O_EVTONLY)
        guard directoryFD >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFD,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleFileChange()
        }
        source.setCancelHandler { [weak self] in
            guard let self = self, self.directoryFD >= 0 else { return }
            close(self.directoryFD)
            self.directoryFD = -1
        }
        source.resume()
        fileSystemSource = source
    }

    func stopWatching() {
        quiescenceTimer?.cancel()
        quiescenceTimer = nil
        fileSystemSource?.cancel()
        fileSystemSource = nil
    }

    // MARK: - Internal handling

    private func handleFileChange() {
        DispatchQueue.main.async { [weak self] in
            self?.isAgentActive = true
        }
        scheduleQuiescenceTimer()
    }

    private func scheduleQuiescenceTimer() {
        quiescenceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + quiescenceInterval)
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.isAgentActive = false
            }
        }
        timer.resume()
        quiescenceTimer = timer
    }
}
#endif
