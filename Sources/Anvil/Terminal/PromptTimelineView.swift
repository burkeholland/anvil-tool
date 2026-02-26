import SwiftUI
import AppKit

/// A slim gutter overlay rendered along the right margin of the terminal.
/// Displays one tick mark per prompt sent in the current session, positioned
/// proportionally in the scrollback buffer.  Clicking a marker scrolls the
/// terminal to that prompt's position.
struct PromptTimelineView: View {
    @EnvironmentObject var terminalProxy: TerminalInputProxy
    @ObservedObject var markerStore: PromptMarkerStore

    /// Width of the timeline strip in points.
    static let stripWidth: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Very subtle background so the strip is perceivable but not intrusive
                Color.white.opacity(0.04)

                ForEach(markerStore.markers) { marker in
                    MarkerTickView(
                        marker: marker,
                        yPosition: tickY(for: marker, in: geo.size.height),
                        onTap: { terminalProxy.scrollToMarker(marker) }
                    )
                }
            }
        }
        .frame(width: Self.stripWidth)
    }

    // MARK: - Private helpers

    /// Returns the vertical position (in points from the top) for a marker.
    private func tickY(for marker: PromptMarker, in height: CGFloat) -> CGFloat {
        let max = terminalProxy.estimatedMaxScrollback
        guard max > 0 else { return height - 3 }
        let fraction = CGFloat(marker.anchorYDisp) / CGFloat(max)
        let raw = fraction * height
        return Swift.max(2, Swift.min(height - 2, raw))
    }
}

// MARK: - Tick mark

private struct MarkerTickView: View {
    let marker: PromptMarker
    let yPosition: CGFloat
    let onTap: () -> Void

    private static let maxTooltipSnippetLength = 80

    @State private var isHovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(isHovering ? Color.accentColor : Color(red: 0.4, green: 0.65, blue: 1.0).opacity(0.75))
            .frame(width: PromptTimelineView.stripWidth, height: isHovering ? 4 : 3)
            .position(x: PromptTimelineView.stripWidth / 2, y: yPosition)
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
            .help(markerTooltip)
            .animation(.easeOut(duration: 0.1), value: isHovering)
    }

    private var markerTooltip: String {
        let timeStr = marker.date.formatted(date: .omitted, time: .shortened)
        let snippet = String(marker.text.prefix(Self.maxTooltipSnippetLength))
        return "[\(timeStr)] \(snippet)"
    }
}
