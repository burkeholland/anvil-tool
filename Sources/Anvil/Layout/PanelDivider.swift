import SwiftUI

/// A draggable divider that sits between two panels and adjusts a binding width.
///
/// Drag horizontally to resize. Double-click to collapse/restore.
struct PanelDivider: View {
    @Binding var width: Double
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let edge: Edge

    /// Width at the start of the current drag gesture.
    @State private var dragStartWidth: Double = 0
    /// Width to restore to after collapsing via double-click.
    @State private var restoreWidth: Double?
    @State private var isDragging = false
    @State private var cursorPushed = false

    /// Which side of the terminal the panel is on — determines drag direction.
    enum Edge {
        case leading  // sidebar: drag right = wider
        case trailing // preview: drag left = wider
    }

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor))
            .frame(width: isDragging ? 3 : 1)
            .padding(.horizontal, isDragging ? 0 : 1)
            .contentShape(Rectangle().inset(by: -3)) // wider hit target
            .onHover { hovering in
                if hovering {
                    if !cursorPushed {
                        NSCursor.resizeLeftRight.push()
                        cursorPushed = true
                    }
                } else {
                    if cursorPushed {
                        NSCursor.pop()
                        cursorPushed = false
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartWidth = width
                        }
                        let delta: CGFloat
                        switch edge {
                        case .leading:
                            delta = value.translation.width
                        case .trailing:
                            delta = -value.translation.width
                        }
                        width = (dragStartWidth + Double(delta)).clamped(to: Double(minWidth)...Double(maxWidth))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onDisappear {
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if width > 0 {
                            restoreWidth = width
                            width = 0
                        } else if let saved = restoreWidth {
                            width = saved
                            restoreWidth = nil
                        } else {
                            width = (minWidth + maxWidth) / 2
                        }
                    }
                }
            )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
