import Foundation

/// A single prompt marker recorded in the terminal timeline.
/// Stores the prompt text, the time it was sent, and the terminal scroll
/// position at the moment of sending so the view can navigate back to it.
struct PromptMarker: Identifiable {
    let id: UUID
    let text: String
    let date: Date
    /// The terminal buffer's `yDisp` value at the moment this prompt was sent.
    /// Equivalent to `maxScrollback` when the terminal was pinned to the bottom,
    /// which is the normal state when a prompt is dispatched.
    let anchorYDisp: Int
}

/// Session-scoped store for prompt timeline markers.
/// Not persisted — markers are cleared when the project changes.
final class PromptMarkerStore: ObservableObject {
    @Published private(set) var markers: [PromptMarker] = []

    /// Records a new marker at the end of the list.
    /// - Parameters:
    ///   - text: The full prompt text (will be trimmed).
    ///   - anchorYDisp: The terminal's `buffer.yDisp` at the time of sending.
    func addMarker(text: String, anchorYDisp: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        markers.append(PromptMarker(id: UUID(), text: trimmed, date: Date(), anchorYDisp: anchorYDisp))
    }

    /// Removes all markers (called on project switch to start a fresh session).
    func clear() {
        markers = []
    }
}
