import Foundation

/// Generates a brief one-line description of what changed in a diff
/// by analysing added/removed lines for function and type declarations and import modifications.
enum DiffChangeDescriber {

    /// Maximum character length for a generated description.
    static let maxDescriptionLength = 80

    /// Returns a brief description (≤`maxDescriptionLength` chars) of what changed, or `nil`
    /// if no meaningful description can be extracted (e.g. config files or unknown languages).
    static func describe(diff: FileDiff, fileExtension: String) -> String? {
        let ext = fileExtension.lowercased()
        var addedLines: [String] = []
        var deletedLines: [String] = []
        var importChanges = false

        for hunk in diff.hunks {
            for line in hunk.lines {
                guard line.kind == .addition || line.kind == .deletion else { continue }
                let trimmed = line.text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                if isImportLine(trimmed, ext: ext) {
                    importChanges = true
                } else if line.kind == .addition {
                    addedLines.append(line.text)
                } else {
                    deletedLines.append(line.text)
                }
            }
        }

        let language = inferLanguage(ext: ext)
        let addedSymbols   = language.isEmpty ? [] : SymbolParser.parse(source: addedLines.joined(separator: "\n"),   language: language)
        let deletedSymbols = language.isEmpty ? [] : SymbolParser.parse(source: deletedLines.joined(separator: "\n"), language: language)

        let funcKinds: Set<SymbolKind> = [.function, .method]
        let typeKinds: Set<SymbolKind> = [.class_, .struct_, .enum_, .protocol_, .interface, .type]

        let addedFuncNames   = Set(addedSymbols.filter   { funcKinds.contains($0.kind) }.map(\.name))
        let deletedFuncNames = Set(deletedSymbols.filter { funcKinds.contains($0.kind) }.map(\.name))
        let addedTypeNames   = Set(addedSymbols.filter   { typeKinds.contains($0.kind) }.map(\.name))
        let deletedTypeNames = Set(deletedSymbols.filter { typeKinds.contains($0.kind) }.map(\.name))

        // Symbols present in both added and deleted lines were modified (not purely added/removed).
        let modifiedFuncs      = addedFuncNames.intersection(deletedFuncNames).sorted()
        let purelyAddedFuncs   = addedFuncNames.subtracting(deletedFuncNames).sorted()
        let purelyRemovedFuncs = deletedFuncNames.subtracting(addedFuncNames).sorted()

        let modifiedTypes      = addedTypeNames.intersection(deletedTypeNames).sorted()
        let purelyAddedTypes   = addedTypeNames.subtracting(deletedTypeNames).sorted()
        let purelyRemovedTypes = deletedTypeNames.subtracting(addedTypeNames).sorted()

        var parts: [String] = []

        if !purelyAddedTypes.isEmpty   { parts.append("Added \(formatNames(purelyAddedTypes))") }
        if !purelyRemovedTypes.isEmpty { parts.append("Removed \(formatNames(purelyRemovedTypes))") }
        if !modifiedTypes.isEmpty      { parts.append("Updated \(formatNames(modifiedTypes))") }

        if !purelyAddedFuncs.isEmpty   { parts.append("Added \(formatNames(purelyAddedFuncs, suffix: "()"))") }
        if !purelyRemovedFuncs.isEmpty { parts.append("Removed \(formatNames(purelyRemovedFuncs, suffix: "()"))") }
        if !modifiedFuncs.isEmpty      { parts.append("Updated \(formatNames(modifiedFuncs, suffix: "()"))") }

        if importChanges {
            parts.isEmpty ? parts.append("Updated imports") : parts.append("updated imports")
        }

        guard !parts.isEmpty else { return nil }

        let description = parts.joined(separator: "; ")
        return description.count <= maxDescriptionLength ? description : String(description.prefix(maxDescriptionLength - 1)) + "…"
    }

    // MARK: - Private helpers

    private static func inferLanguage(ext: String) -> String {
        switch ext {
        case "swift":                    return "swift"
        case "ts", "tsx":                return "typescript"
        case "js", "jsx", "mjs":         return "javascript"
        case "py":                       return "python"
        case "go":                       return "go"
        case "rs":                       return "rust"
        case "java":                     return "java"
        case "kt":                       return "kotlin"
        case "cs":                       return "csharp"
        case "rb":                       return "ruby"
        case "php":                      return "php"
        case "c", "h":                   return "c"
        case "cpp", "cc", "cxx", "hpp":  return "cpp"
        case "m", "mm":                  return "objectivec"
        default:                         return ""
        }
    }

    private static func isImportLine(_ trimmed: String, ext: String) -> Bool {
        switch ext {
        case "swift":
            return trimmed.hasPrefix("import ")
        case "ts", "tsx", "js", "jsx", "mjs":
            return trimmed.hasPrefix("import ") || (trimmed.hasPrefix("const ") && trimmed.contains("require("))
        case "py":
            return trimmed.hasPrefix("import ") || trimmed.hasPrefix("from ")
        case "go":
            return trimmed.hasPrefix("import ")
        case "rs":
            return trimmed.hasPrefix("use ") || trimmed.hasPrefix("extern crate ")
        default:
            return trimmed.hasPrefix("import ")
        }
    }

    /// Returns up to two names joined by ", ", optionally appending `suffix` to each.
    private static func formatNames(_ names: [String], suffix: String = "") -> String {
        Array(names.prefix(2)).map { $0 + suffix }.joined(separator: ", ")
    }
}
