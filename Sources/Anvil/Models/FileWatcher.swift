import Foundation
import CoreServices

/// Watches a directory tree for file system changes using FSEvents.
/// Debounces rapid changes to avoid excessive refreshes during builds.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private let onChange: () -> Void

    init(directory: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        startWatching(directory)
    }

    deinit {
        stop()
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func startWatching(_ directory: URL) {
        let pathsToWatch = [directory.path] as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)

        stream = FSEventStreamCreate(
            nil,
            { (_, info, _, _, _, _) in
                guard let info = info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.scheduleNotification()
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        )

        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    private func scheduleNotification() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
}
