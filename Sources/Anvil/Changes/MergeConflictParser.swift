import Foundation

/// Resolution choice for a single conflict block.
enum ConflictResolution {
    case unresolved
    case acceptCurrent
    case acceptIncoming
    case acceptBoth
}

/// A single conflict block extracted from a file with merge conflict markers.
struct ConflictBlock: Identifiable {
    let id: UUID
    /// Lines from HEAD (<<<<<<< … =======)
    let currentLines: [String]
    /// Lines from the incoming branch (======= … >>>>>>>)
    let incomingLines: [String]
    /// The label on the <<<<<<< marker (e.g. "HEAD" or a branch name).
    let currentLabel: String
    /// The label on the >>>>>>> marker (the incoming branch/commit name).
    let incomingLabel: String
    /// 0-based index of the line where <<<<<<< appears in the original file.
    let startLine: Int
    /// Resolution chosen by the user.
    var resolution: ConflictResolution = .unresolved

    init(id: UUID = UUID(),
         currentLines: [String],
         incomingLines: [String],
         currentLabel: String,
         incomingLabel: String,
         startLine: Int) {
        self.id = id
        self.currentLines = currentLines
        self.incomingLines = incomingLines
        self.currentLabel = currentLabel
        self.incomingLabel = incomingLabel
        self.startLine = startLine
    }

    /// Lines that result from the chosen resolution.
    var resolvedLines: [String] {
        switch resolution {
        case .unresolved:
            return []
        case .acceptCurrent:
            return currentLines
        case .acceptIncoming:
            return incomingLines
        case .acceptBoth:
            return currentLines + incomingLines
        }
    }
}

/// Parses conflict markers from file content and can produce resolved content.
enum MergeConflictParser {

    /// Parse all conflict blocks from `content`.
    /// Returns an empty array if there are no conflict markers.
    static func parse(content: String) -> [ConflictBlock] {
        let lines = content.components(separatedBy: "\n")
        var blocks: [ConflictBlock] = []

        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("<<<<<<<") {
                let currentLabel = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                let startLine = i
                i += 1

                var currentLines: [String] = []
                while i < lines.count && !lines[i].hasPrefix("=======") && !lines[i].hasPrefix("<<<<<<<") {
                    currentLines.append(lines[i])
                    i += 1
                }
                // skip "=======" separator
                if i < lines.count && lines[i].hasPrefix("=======") {
                    i += 1
                }

                var incomingLines: [String] = []
                while i < lines.count && !lines[i].hasPrefix(">>>>>>>") {
                    incomingLines.append(lines[i])
                    i += 1
                }

                let incomingLabel: String
                if i < lines.count {
                    incomingLabel = String(lines[i].dropFirst(7)).trimmingCharacters(in: .whitespaces)
                    i += 1
                } else {
                    incomingLabel = ""
                }

                blocks.append(ConflictBlock(
                    currentLines: currentLines,
                    incomingLines: incomingLines,
                    currentLabel: currentLabel.isEmpty ? "HEAD" : currentLabel,
                    incomingLabel: incomingLabel.isEmpty ? "Incoming" : incomingLabel,
                    startLine: startLine
                ))
            } else {
                i += 1
            }
        }
        return blocks
    }

    /// Rebuild file content from the original `content` with `blocks` applied.
    /// Blocks must cover only the conflict regions; context lines are preserved.
    static func applyResolutions(to content: String, blocks: [ConflictBlock]) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0
        var blockIndex = 0

        // Sort blocks by startLine for deterministic processing
        let sortedBlocks = blocks.sorted { $0.startLine < $1.startLine }

        while i < lines.count {
            if blockIndex < sortedBlocks.count && i == sortedBlocks[blockIndex].startLine {
                let block = sortedBlocks[blockIndex]
                // Skip all lines belonging to this conflict block
                // (<<<<<<< … =======  … >>>>>>>)
                var j = i
                // skip <<<<<<< line
                j += 1
                // skip current lines
                while j < lines.count && !lines[j].hasPrefix("=======") && !lines[j].hasPrefix("<<<<<<<") {
                    j += 1
                }
                // skip ======= line
                if j < lines.count { j += 1 }
                // skip incoming lines
                while j < lines.count && !lines[j].hasPrefix(">>>>>>>") {
                    j += 1
                }
                // skip >>>>>>> line
                if j < lines.count { j += 1 }

                // Emit resolved content
                result.append(contentsOf: block.resolvedLines)

                i = j
                blockIndex += 1
            } else {
                result.append(lines[i])
                i += 1
            }
        }
        return result.joined(separator: "\n")
    }
}
