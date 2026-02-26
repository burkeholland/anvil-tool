import SwiftUI

/// Toolbar pill showing session elapsed time, a context fullness bar, and a
/// one-click Compact button when the context appears saturated.
struct SessionHealthView: View {
    @ObservedObject var monitor: SessionHealthMonitor
    var onCompact: () -> Void

    private var fillColor: Color {
        if monitor.contextFillness > 0.8 { return .orange }
        if monitor.contextFillness > 0.5 { return .yellow }
        return Color(nsColor: .systemGreen)
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(monitor.elapsedString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            // Thin context-fullness bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor)
                        .frame(width: max(0, geo.size.width * monitor.contextFillness))
                        .animation(.easeInOut(duration: 0.4), value: monitor.contextFillness)
                }
            }
            .frame(width: 36, height: 5)

            if monitor.isSaturated {
                Button(action: onCompact) {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text("Compact")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Context may be saturated — send /compact to the terminal")
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(monitor.isSaturated
                      ? Color.orange.opacity(0.1)
                      : Color.secondary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    monitor.isSaturated ? Color.orange.opacity(0.45) : Color.clear,
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.3), value: monitor.isSaturated)
        .help("Session: \(monitor.elapsedString) · \(Int(monitor.contextFillness * 100))% context used (\(monitor.turnCount) turns)")
    }
}
