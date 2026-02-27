import SwiftUI

/// A single prompt suggestion chip generated from the current app state.
struct PromptSuggestion: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    /// The fully-formed prompt text that will be sent to the terminal when the chip is tapped.
    let prompt: String
    let accentColor: Color
}

/// A horizontal strip of one-click prompt suggestion chips shown above the terminal input area.
///
/// Chips adapt in real-time to the current app state:
/// - BuildVerifier failures → "Fix the N build errors in [files]"
/// - TestRunner failures   → "Fix the N failing tests"
/// - Many unreviewed files → "Explain what you changed"
/// - Session saturated     → "Compact session"
///
/// Tapping a chip sends the context-aware prompt to the terminal via `onSelectSuggestion`.
/// The bar is hidden entirely when there are no active suggestions.
struct PromptSuggestionBar: View {
    let buildStatus: BuildVerifier.Status
    let buildDiagnostics: [BuildDiagnostic]
    let testStatus: TestRunner.Status
    /// Number of changed files not yet marked as reviewed.
    let unreviewedCount: Int
    /// Total number of changed files in the working tree.
    let totalChangedCount: Int
    /// Number of inline diff annotations in the current review session.
    let annotationCount: Int
    /// The fully-formed prompt for inline review notes.
    let annotationPrompt: String
    /// Whether the Copilot session context appears saturated.
    let isSaturated: Bool
    /// Called with the prompt text when the user taps a chip.
    var onSelectSuggestion: (String) -> Void

    private var chips: [PromptSuggestion] {
        PromptSuggestionBar.makeChips(
            buildStatus: buildStatus,
            buildDiagnostics: buildDiagnostics,
            testStatus: testStatus,
            unreviewedCount: unreviewedCount,
            totalChangedCount: totalChangedCount,
            annotationCount: annotationCount,
            annotationPrompt: annotationPrompt,
            isSaturated: isSaturated
        )
    }

    var body: some View {
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        SuggestionChipButton(chip: chip) {
                            onSelectSuggestion(chip.prompt)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
            .overlay(alignment: .top) { Divider() }
        }
    }

    // MARK: - Static chip generation (unit-testable)

    /// Generates the current set of suggestion chips from app state.
    /// Exposed as `static` so it can be tested without constructing the full view.
    static func makeChips(
        buildStatus: BuildVerifier.Status,
        buildDiagnostics: [BuildDiagnostic],
        testStatus: TestRunner.Status,
        unreviewedCount: Int,
        totalChangedCount: Int,
        annotationCount: Int,
        annotationPrompt: String,
        isSaturated: Bool
    ) -> [PromptSuggestion] {
        var chips: [PromptSuggestion] = []

        // Build failures chip
        if case .failed = buildStatus {
            let errorDiags = buildDiagnostics.filter { $0.severity == .error }
            let uniqueFiles = Array(
                Set(errorDiags.map { ($0.filePath as NSString).lastPathComponent })
            ).sorted().prefix(3)

            let label: String
            let prompt: String
            if errorDiags.count > 0 {
                label = "Fix \(errorDiags.count) build error\(errorDiags.count == 1 ? "" : "s")"
                if uniqueFiles.isEmpty {
                    prompt = "Fix the \(errorDiags.count) build error\(errorDiags.count == 1 ? "" : "s")"
                } else {
                    let fileList = uniqueFiles.joined(separator: ", ")
                    prompt = "Fix the \(errorDiags.count) build error\(errorDiags.count == 1 ? "" : "s") in \(fileList)"
                }
            } else {
                label = "Fix build errors"
                prompt = "Fix the build errors"
            }
            chips.append(PromptSuggestion(icon: "xmark.octagon.fill", label: label, prompt: prompt, accentColor: .red))
        }

        // Test failures chip
        if case .failed(let failedTests, _) = testStatus {
            let n = failedTests.count
            let label = n > 0
                ? "Fix \(n) failing test\(n == 1 ? "" : "s")"
                : "Fix failing tests"
            let prompt: String
            if n == 0 {
                prompt = "Fix the failing tests"
            } else {
                let names = failedTests.prefix(3).joined(separator: ", ")
                let extra = n > 3 ? " and \(n - 3) more" : ""
                prompt = "Fix the \(n) failing test\(n == 1 ? "" : "s"): \(names)\(extra)"
            }
            chips.append(PromptSuggestion(icon: "xmark.circle.fill", label: label, prompt: prompt, accentColor: .red))
        }

        // Unreviewed changes chip (shown when ≥3 files haven't been reviewed)
        if unreviewedCount >= 3 {
            chips.append(PromptSuggestion(
                icon: "doc.text.magnifyingglass",
                label: "Explain changes",
                prompt: "Explain what you changed",
                accentColor: .blue
            ))
        }

        // Annotations chip
        if annotationCount > 0, !annotationPrompt.isEmpty {
            chips.append(PromptSuggestion(
                icon: "bubble.left.fill",
                label: "Address \(annotationCount) review note\(annotationCount == 1 ? "" : "s")",
                prompt: annotationPrompt,
                accentColor: .orange
            ))
        }

        // Compact session chip
        if isSaturated {
            chips.append(PromptSuggestion(
                icon: "arrow.triangle.2.circlepath",
                label: "Compact session",
                prompt: "/compact",
                accentColor: .purple
            ))
        }

        return chips
    }
}

// MARK: - Chip Button

private struct SuggestionChipButton: View {
    let chip: PromptSuggestion
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: chip.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(chip.accentColor)
                Text(chip.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isHovering
                          ? chip.accentColor.opacity(0.15)
                          : chip.accentColor.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .strokeBorder(chip.accentColor.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(chip.prompt)
    }
}
