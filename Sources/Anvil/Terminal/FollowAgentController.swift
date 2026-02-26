import Foundation

/// An event fired when the follow action triggers after debouncing.
struct FollowEvent: Equatable {
    let id: UUID
    let url: URL
}

/// Manages debounced auto-follow navigation when the agent modifies files.
/// Coalesces rapid file changes into a single follow action after a short
/// quiet period, so the preview pane doesn't thrash during burst writes.
final class FollowAgentController: ObservableObject {

    /// Published follow event. Each fire has a unique id so SwiftUI
    /// `onChange` triggers even when the same URL is followed twice.
    @Published private(set) var followEvent: FollowEvent?

    /// Debounce interval in seconds.
    let debounceInterval: TimeInterval

    private var debounceWorkItem: DispatchWorkItem?

    init(debounceInterval: TimeInterval = 0.5) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        debounceWorkItem?.cancel()
    }

    /// Reports a newly detected file change. The follow action is debounced so
    /// that only the last URL in a burst of changes is acted upon.
    func reportChange(_ url: URL) {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.followEvent = FollowEvent(id: UUID(), url: url)
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    /// Cancels any pending follow action without firing it.
    func cancel() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }
}
