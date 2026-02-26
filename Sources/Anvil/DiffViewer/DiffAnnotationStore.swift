import Foundation

/// A single developer annotation attached to a specific line in a diff.
struct DiffAnnotation: Identifiable, Equatable {
    let id: UUID
    let filePath: String
    let lineNumber: Int
    var comment: String

    init(filePath: String, lineNumber: Int, comment: String) {
        self.id = UUID()
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.comment = comment
    }
}

/// Stores all inline diff annotations for the current review session.
/// Inject as an `@StateObject` at the `BranchDiffView` level and pass annotation
/// callbacks down into `DiffHunkView` / `DiffLineView`.
/// Call `clearAll()` whenever a new diff is loaded so annotations stay in sync.
final class DiffAnnotationStore: ObservableObject {
    @Published private(set) var annotations: [DiffAnnotation] = []

    var isEmpty: Bool { annotations.isEmpty }

    /// Adds a new annotation or replaces an existing one for the same file and line.
    func add(filePath: String, lineNumber: Int, comment: String) {
        let sanitized = sanitize(comment)
        guard !sanitized.isEmpty else { return }
        if let idx = annotations.firstIndex(where: { $0.filePath == filePath && $0.lineNumber == lineNumber }) {
            annotations[idx].comment = sanitized
        } else {
            annotations.append(DiffAnnotation(filePath: filePath, lineNumber: lineNumber, comment: sanitized))
        }
    }

    /// Removes the annotation for the given file and line, if any.
    func remove(filePath: String, lineNumber: Int) {
        annotations.removeAll { $0.filePath == filePath && $0.lineNumber == lineNumber }
    }

    /// Removes all annotations.
    func clearAll() {
        annotations.removeAll()
    }

    /// Returns the comment for the given file and line, or `nil` if none exists.
    func comment(forFile filePath: String, line lineNumber: Int) -> String? {
        annotations.first { $0.filePath == filePath && $0.lineNumber == lineNumber }?.comment
    }

    /// Returns a dictionary mapping line numbers to comments for a specific file.
    func lineAnnotations(forFile filePath: String) -> [Int: String] {
        var result: [Int: String] = [:]
        for ann in annotations where ann.filePath == filePath {
            result[ann.lineNumber] = ann.comment
        }
        return result
    }

    /// Builds a structured prompt with all annotations, sorted by file path and line number,
    /// suitable for sending to the Copilot terminal.
    func buildPrompt() -> String {
        guard !annotations.isEmpty else { return "" }
        let sorted = annotations.sorted {
            if $0.filePath != $1.filePath { return $0.filePath < $1.filePath }
            return $0.lineNumber < $1.lineNumber
        }
        let items = sorted.map { "@\($0.filePath)#L\($0.lineNumber): \($0.comment)" }
        return "Please address the following review annotations:\n\n" + items.joined(separator: "\n") + "\n"
    }

    // MARK: - Private

    /// Strips ASCII and C1 control characters from annotation text to prevent terminal injection.
    private func sanitize(_ text: String) -> String {
        String(text.unicodeScalars.filter {
            $0.value >= 0x20 && $0.value != 0x7F && ($0.value < 0x80 || $0.value > 0x9F)
        }.map { Character($0) })
    }
}
