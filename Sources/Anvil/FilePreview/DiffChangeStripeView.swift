import SwiftUI
import AppKit

/// A slim vertical stripe rendered alongside the file preview scrollbar.
/// Displays one tick mark per changed line region, positioned proportionally
/// in the document. Green for additions, orange for modifications, red for
/// deletions. Clicking a tick mark scrolls the preview to that line.
struct DiffChangeStripeView: View {
    /// Line number → change kind for the current file.
    let gutterChanges: [Int: GutterChangeKind]
    /// Total number of lines in the document (used to compute vertical position).
    let totalLines: Int
    /// Invoked when the user taps a tick mark. Receives the 1-based line number.
    let onScrollToLine: (Int) -> Void

    /// Width of the stripe in points.
    static let stripWidth: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.white.opacity(0.04)

                ForEach(tickMarks, id: \.line) { tick in
                    StripeTickView(
                        tick: tick,
                        yPosition: tickY(for: tick.line, in: geo.size.height),
                        onTap: { onScrollToLine(tick.line) }
                    )
                }
            }
        }
        .frame(width: Self.stripWidth)
    }

    // MARK: - Private helpers

    /// Collapsed list of tick marks — one per contiguous change region.
    private var tickMarks: [TickMark] {
        guard totalLines > 0 else { return [] }
        var ticks: [TickMark] = []
        let sortedLines = gutterChanges.keys.sorted()
        var i = 0
        while i < sortedLines.count {
            let line = sortedLines[i]
            guard let kind = gutterChanges[line] else { i += 1; continue }
            // Advance through contiguous lines of the same region
            var j = i + 1
            while j < sortedLines.count && sortedLines[j] == sortedLines[j - 1] + 1 {
                j += 1
            }
            // Pick a representative kind for the region (prefer modified > added > deleted)
            var regionKind = kind
            for k in i..<j {
                guard let k2 = gutterChanges[sortedLines[k]] else { continue }
                if k2 == .modified { regionKind = .modified; break }
                if k2 == .added { regionKind = .added }
            }
            ticks.append(TickMark(line: line, kind: regionKind))
            i = j
        }
        return ticks
    }

    private func tickY(for line: Int, in height: CGFloat) -> CGFloat {
        guard totalLines > 1 else { return height / 2 }
        let fraction = CGFloat(line - 1) / CGFloat(totalLines - 1)
        let raw = fraction * height
        return Swift.max(2, Swift.min(height - 2, raw))
    }
}

// MARK: - Data model

private struct TickMark: Hashable {
    let line: Int
    let kind: GutterChangeKind
}

// MARK: - Individual tick

private struct StripeTickView: View {
    let tick: TickMark
    let yPosition: CGFloat
    let onTap: () -> Void

    @State private var isHovering = false

    private var tickColor: Color {
        switch tick.kind {
        case .added:    return Color(red: 0.2, green: 0.75, blue: 0.4)
        case .modified: return Color(red: 1.0, green: 0.65, blue: 0.2)
        case .deleted:  return Color(red: 0.85, green: 0.28, blue: 0.28)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(isHovering ? tickColor : tickColor.opacity(0.75))
            .frame(width: DiffChangeStripeView.stripWidth, height: isHovering ? 4 : 3)
            .position(x: DiffChangeStripeView.stripWidth / 2, y: yPosition)
            .onHover { hovering in
                isHovering = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
            .onTapGesture { onTap() }
            .help("Line \(tick.line): \(tick.kind == .added ? "added" : tick.kind == .modified ? "modified" : "deleted")")
            .animation(.easeOut(duration: 0.1), value: isHovering)
    }
}
