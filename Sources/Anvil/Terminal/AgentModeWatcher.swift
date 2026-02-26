import Foundation
import SwiftTerm

/// Possible Copilot CLI agent modes.
enum AgentMode: String, CaseIterable {
    case interactive = "interactive"
    case plan        = "plan"
    case autopilot   = "autopilot"

    /// The display label shown in the toolbar pill.
    var displayName: String {
        switch self {
        case .interactive: return "Interactive"
        case .plan:        return "Plan"
        case .autopilot:   return "Autopilot"
        }
    }

    /// The terminal command sent to activate this mode.
    var activateCommand: String {
        switch self {
        case .interactive: return "/agent interactive\n"
        case .plan:        return "/agent plan\n"
        case .autopilot:   return "/agent autopilot\n"
        }
    }

    /// Returns the next mode in the cycling order (wraps around).
    var next: AgentMode {
        let all = AgentMode.allCases
        guard let idx = all.firstIndex(of: self) else { return .interactive }
        return all[(idx + 1) % all.count]
    }
}

/// Scans terminal output rows to detect the current Copilot CLI agent mode
/// and active model name.
///
/// Detection heuristic: on every `rangeChanged` that touches the bottom rows
/// of the viewport, scan for known Copilot CLI prompt patterns and status
/// lines that include mode or model information.
final class AgentModeWatcher {
    /// Called on the main queue whenever the detected mode changes.
    var onModeChanged: ((AgentMode?) -> Void)?
    /// Called on the main queue whenever the detected model name changes.
    var onModelChanged: ((String?) -> Void)?

    /// The most recently detected agent mode.
    private(set) var currentMode: AgentMode?
    /// The most recently detected model name.
    private(set) var currentModel: String?

    /// Number of rows from the bottom of the viewport to scan.
    private static let scanWindowRows = 8

    // MARK: - Public interface

    /// Re-evaluates mode/model state when terminal output is updated.
    func processTerminalRange(in view: LocalProcessTerminalView, startY: Int, endY: Int) {
        let terminal = view.getTerminal()
        let lastRow = terminal.rows - 1
        guard endY >= max(0, lastRow - (Self.scanWindowRows - 1)) else { return }

        let scanStart = max(0, lastRow - (Self.scanWindowRows - 1))
        for row in scanStart...lastRow {
            guard let bufferLine = terminal.getLine(row: row) else { continue }
            let text = bufferLine.translateToString(trimRight: true)
            guard !text.isEmpty else { continue }

            if let mode = detectMode(in: text), mode != currentMode {
                currentMode = mode
                let value = mode
                DispatchQueue.main.async { [weak self] in self?.onModeChanged?(value) }
            }
            if let model = detectModel(in: text), model != currentModel {
                currentModel = model
                let value = model
                DispatchQueue.main.async { [weak self] in self?.onModelChanged?(value) }
            }
        }
    }

    // MARK: - Pattern helpers (internal for testability)

    /// Returns an `AgentMode` when `text` contains a recognised Copilot CLI
    /// mode indicator, or `nil` otherwise.
    func detectMode(in text: String) -> AgentMode? {
        let lower = text.lowercased()
        // Prompt-style markers: "(interactive)", "[plan]", etc.
        if lower.contains("(interactive)") || lower.contains("[interactive]") { return .interactive }
        if lower.contains("(ask)") || lower.contains("[ask]") { return .interactive }
        if lower.contains("(plan)") || lower.contains("[plan]") { return .plan }
        if lower.contains("(autopilot)") || lower.contains("[autopilot]") { return .autopilot }
        if lower.contains("(agent)") || lower.contains("[agent]") { return .autopilot }
        // Status lines: "mode: plan", "mode: interactive", etc.
        if lower.contains("mode: interactive") || lower.contains("mode:interactive") { return .interactive }
        if lower.contains("mode: ask") || lower.contains("mode:ask") { return .interactive }
        if lower.contains("mode: plan") || lower.contains("mode:plan") { return .plan }
        if lower.contains("mode: autopilot") || lower.contains("mode:autopilot") { return .autopilot }
        if lower.contains("mode: agent") || lower.contains("mode:agent") { return .autopilot }
        // Transition lines: "switched to plan mode"
        if lower.contains("switched to interactive") { return .interactive }
        if lower.contains("switched to ask") { return .interactive }
        if lower.contains("switched to plan") { return .plan }
        if lower.contains("switched to autopilot") { return .autopilot }
        if lower.contains("switched to agent") { return .autopilot }
        return nil
    }

    /// Extracts the model name when `text` contains a recognised Copilot CLI
    /// model indicator, or returns `nil` otherwise.
    func detectModel(in text: String) -> String? {
        let lower = text.lowercased()
        // Try longest prefixes first so "using model: " beats "model: "
        for prefix in ["using model: ", "using model:", "model: ", "model:"] {
            if let range = lower.range(of: prefix) {
                let rest = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let token = rest.components(separatedBy: .whitespaces).first ?? ""
                let model = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;)>"))
                if !model.isEmpty { return model }
            }
        }
        return nil
    }
}
