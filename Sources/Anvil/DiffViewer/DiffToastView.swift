import SwiftUI

// MARK: - Data Model

/// A single diff toast entry shown in the floating overlay stack.
struct DiffToastItem: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    let fileName: String
    let relativePath: String
    let diff: FileDiff?
    let createdAt: Date

    static func == (lhs: DiffToastItem, rhs: DiffToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Controller

/// Manages the stack of active diff toast items.
/// Receives file-change events, fetches the diff asynchronously, and
/// auto-dismisses each toast after `displayDuration` seconds.
final class DiffToastController: ObservableObject {

    @Published private(set) var toasts: [DiffToastItem] = []

    let displayDuration: TimeInterval
    private let maxStack = 5

    private var dismissTasks: [UUID: DispatchWorkItem] = [:]
    private let workQueue = DispatchQueue(label: "dev.anvil.diff-toast", qos: .userInitiated)

    init(displayDuration: TimeInterval = 8) {
        self.displayDuration = displayDuration
    }

    deinit {
        dismissTasks.values.forEach { $0.cancel() }
    }

    /// Call when a file-write event is detected. Fetches the diff on a
    /// background queue and then adds a toast to the visible stack.
    func reportFileChange(_ url: URL, rootURL: URL) {
        workQueue.async { [weak self] in
            guard let self else { return }
            let diff = DiffProvider.diff(for: url, in: rootURL)
            let relPath = Self.relativePath(url, root: rootURL)
            let item = DiffToastItem(
                id: UUID(),
                fileURL: url,
                fileName: url.lastPathComponent,
                relativePath: relPath,
                diff: diff,
                createdAt: Date()
            )
            DispatchQueue.main.async {
                self.enqueue(item)
            }
        }
    }

    // MARK: Dismissal

    func dismiss(id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks.removeValue(forKey: id)
        withAnimation(.easeInOut(duration: 0.25)) {
            toasts.removeAll { $0.id == id }
        }
    }

    func dismissAll() {
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()
        withAnimation(.easeInOut(duration: 0.25)) {
            toasts.removeAll()
        }
    }

    // MARK: - Testing hook

#if DEBUG
    /// For unit-testing only. Enqueues a pre-built item without fetching a diff.
    func _testEnqueue(_ item: DiffToastItem) {
        enqueue(item)
    }
#endif

    // MARK: Private

    private func enqueue(_ item: DiffToastItem) {
        // Replace an existing toast for the same file so the stack stays compact.
        if let idx = toasts.firstIndex(where: { $0.fileURL == item.fileURL }) {
            let oldID = toasts[idx].id
            dismissTasks[oldID]?.cancel()
            dismissTasks.removeValue(forKey: oldID)
            toasts.remove(at: idx)
        }

        // Cap the stack by evicting the oldest entry.
        if toasts.count >= maxStack {
            let removed = toasts.removeFirst()
            dismissTasks[removed.id]?.cancel()
            dismissTasks.removeValue(forKey: removed.id)
        }

        toasts.append(item)
        scheduleDismiss(item.id)
    }

    private func scheduleDismiss(_ id: UUID) {
        let work = DispatchWorkItem { [weak self] in
            self?.dismiss(id: id)
        }
        dismissTasks[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: work)
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let absPath = url.standardizedFileURL.path
        if absPath.hasPrefix(rootPath + "/") {
            return String(absPath.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }
}

// MARK: - Compact diff renderer

/// Renders the first `maxLines` non-header diff lines inside a toast card.
private struct ToastDiffContent: View {
    let diff: FileDiff
    var maxLines: Int = 12

    private var allContentLines: [DiffLine] {
        diff.hunks.flatMap(\.lines).filter { $0.kind != .hunkHeader }
    }

    private var displayLines: [DiffLine] { Array(allContentLines.prefix(maxLines)) }
    private var hasMore: Bool { allContentLines.count > maxLines }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(displayLines) { line in
                HStack(spacing: 0) {
                    Text(linePrefix(line))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(lineColor(line))
                        .frame(width: 10, alignment: .leading)
                        .padding(.leading, 6)
                    Text(line.text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(lineColor(line))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 6)
                }
                .padding(.vertical, 1)
                .background(lineBg(line))
            }
            if hasMore {
                Text("  ⋯ scroll for more")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
            }
        }
    }

    private func linePrefix(_ line: DiffLine) -> String {
        switch line.kind {
        case .addition: return "+"
        case .deletion: return "-"
        default:        return " "
        }
    }

    private func lineColor(_ line: DiffLine) -> Color {
        switch line.kind {
        case .addition: return Color(nsColor: .systemGreen)
        case .deletion: return Color(nsColor: .systemRed)
        default:        return .primary
        }
    }

    private func lineBg(_ line: DiffLine) -> Color {
        switch line.kind {
        case .addition: return Color.green.opacity(0.07)
        case .deletion: return Color.red.opacity(0.07)
        default:        return .clear
        }
    }
}

// MARK: - Single toast card

/// A floating glass card showing the diff for one changed file.
struct DiffToastCard: View {
    let item: DiffToastItem
    let onDismiss: () -> Void
    let onOpenInChanges: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if let diff = item.diff, !diff.hunks.isEmpty {
                Divider().opacity(0.4)
                ScrollView(.vertical, showsIndicators: false) {
                    ToastDiffContent(diff: diff)
                        .padding(.vertical, 4)
                }
                .frame(maxHeight: 140)
            } else {
                Text("Waiting for diff…")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { onOpenInChanges() }
        .onHover { isHovering = $0 }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(item.fileName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            if let diff = item.diff {
                diffStatsBadge(diff)
            }

            Spacer()

            Button {
                onOpenInChanges()
            } label: {
                Text("Open")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Open in Changes panel")

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 5)
    }

    @ViewBuilder
    private func diffStatsBadge(_ diff: FileDiff) -> some View {
        HStack(spacing: 3) {
            if diff.additionCount > 0 {
                Text("+\(diff.additionCount)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.green)
            }
            if diff.deletionCount > 0 {
                Text("-\(diff.deletionCount)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Overlay stack

/// Stacked overlay of diff toasts positioned at the bottom-right of the window.
struct DiffToastOverlay: View {
    @ObservedObject var controller: DiffToastController
    let onOpenInChanges: (DiffToastItem) -> Void

    var body: some View {
        if !controller.toasts.isEmpty {
            VStack(alignment: .trailing, spacing: 8) {
                Spacer()
                ForEach(controller.toasts) { item in
                    DiffToastCard(
                        item: item,
                        onDismiss: { controller.dismiss(id: item.id) },
                        onOpenInChanges: { onOpenInChanges(item) }
                    )
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        )
                    )
                }
            }
            .padding(.bottom, 44)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .animation(
                .spring(response: 0.3, dampingFraction: 0.8),
                value: controller.toasts.map(\.id)
            )
        }
    }
}
