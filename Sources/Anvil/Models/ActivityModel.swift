import Foundation
import Combine

/// Tracks whether the Copilot agent is currently active (processing a task).
class ActivityModel: ObservableObject {
    @Published var isAgentActive: Bool = false

    /// Simulates the agent starting a task.
    func startTask() {
        isAgentActive = true
    }

    /// Simulates the agent finishing a task.
    func finishTask() {
        isAgentActive = false
    }
}
