import Foundation

/// A document symbol extracted from source code.
struct DocumentSymbol: Identifiable {
    let id = UUID()
    let name: String
    let kind: SymbolKind
    /// 1-based line number where the symbol is declared.
    let line: Int
    /// Indentation depth (0 = top-level).
    let depth: Int

    var icon: String {
        switch kind {
        case .function:  return "f.square"
        case .method:    return "m.square"
        case .class_:    return "c.square"
        case .struct_:   return "s.square"
        case .enum_:     return "e.square"
        case .protocol_: return "p.square"
        case .interface: return "chevron.left.forwardslash.chevron.right"
        case .property:  return "p.circle"
        case .constant:  return "k.circle"
        case .type:      return "t.square"
        }
    }

    var iconColor: String {
        switch kind {
        case .function, .method: return "blue"
        case .class_, .struct_:  return "purple"
        case .enum_:             return "orange"
        case .protocol_, .interface: return "green"
        case .property, .constant: return "secondary"
        case .type:              return "teal"
        }
    }
}

enum SymbolKind: String, CaseIterable {
    case function
    case method
    case class_
    case struct_
    case enum_
    case protocol_
    case interface
    case property
    case constant
    case type
}

/// Extracts document symbols from source code using regex patterns per language.
enum SymbolParser {

    /// Parse symbols from the given source code, using the Highlightr language identifier.
    static func parse(source: String, language: String?) -> [DocumentSymbol] {
        guard let lang = language else { return [] }
        let lines = source.components(separatedBy: "\n")
        guard !lines.isEmpty else { return [] }

        let patterns = Self.patterns(for: lang)
        guard !patterns.isEmpty else { return [] }

        var symbols: [DocumentSymbol] = []
        var depthStack: [Int] = [] // indentation levels of open scopes

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            // Note: `#` is a comment in Python/Ruby/bash, but not in C/C++/ObjC where #define is valid.
            let hashIsComment = lang != "c" && lang != "cpp" && lang != "objectivec"
            if trimmed.isEmpty || trimmed.hasPrefix("//")
                || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*")
                || (hashIsComment && trimmed.hasPrefix("#")) { continue }

            let indent = leadingSpaces(line)

            for pattern in patterns {
                guard let match = try? pattern.regex.firstMatch(in: line),
                      let capture = match.output[pattern.nameGroup].substring else { continue }
                let name = String(capture)
                guard !name.isEmpty else { continue }

                // Compute depth from indentation
                let depth = computeDepth(indent: indent, depthStack: &depthStack)

                symbols.append(DocumentSymbol(
                    name: name,
                    kind: pattern.kind,
                    line: lineNumber,
                    depth: depth
                ))
                break // one symbol per line
            }
        }

        return symbols
    }

    // MARK: - Private

    private struct SymbolPattern {
        let regex: Regex<AnyRegexOutput>
        let nameGroup: Int
        let kind: SymbolKind
    }

    private static func computeDepth(indent: Int, depthStack: inout [Int]) -> Int {
        // Pop deeper or equal indentation levels
        while let last = depthStack.last, indent <= last {
            depthStack.removeLast()
        }
        let depth = depthStack.count
        depthStack.append(indent)
        return depth
    }

    private static func leadingSpaces(_ line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 }
            else if ch == "\t" { count += 4 }
            else { break }
        }
        return count
    }

    private static func patterns(for language: String) -> [SymbolPattern] {
        switch language {
        case "swift":
            return swiftPatterns
        case "typescript", "javascript":
            return tsPatterns
        case "python":
            return pythonPatterns
        case "go":
            return goPatterns
        case "rust":
            return rustPatterns
        case "java", "kotlin", "csharp":
            return javaPatterns
        case "c", "cpp", "objectivec":
            return cPatterns
        case "ruby":
            return rubyPatterns
        case "php":
            return phpPatterns
        default:
            return []
        }
    }

    // MARK: - Language Patterns

    private static let swiftPatterns: [SymbolPattern] = buildPatterns([
        (#"(?:public |private |internal |open |fileprivate )?(?:final )?class\s+(\w+)"#, 1, .class_),
        (#"(?:public |private |internal |fileprivate )?struct\s+(\w+)"#, 1, .struct_),
        (#"(?:public |private |internal |fileprivate )?enum\s+(\w+)"#, 1, .enum_),
        (#"(?:public |private |internal |fileprivate )?protocol\s+(\w+)"#, 1, .protocol_),
        (#"(?:public |private |internal |open |fileprivate )?(?:static |class )?(?:override )?func\s+(\w+)"#, 1, .function),
        (#"(?:public |private |internal |open |fileprivate )?(?:static |class )?(?:var|let)\s+(\w+)\s*[=:]"#, 1, .property),
        (#"(?:public |private |internal |fileprivate )?typealias\s+(\w+)"#, 1, .type),
    ])

    private static let tsPatterns: [SymbolPattern] = buildPatterns([
        (#"(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+(\w+)"#, 1, .class_),
        (#"(?:export\s+)?interface\s+(\w+)"#, 1, .interface),
        (#"(?:export\s+)?type\s+(\w+)\s*="#, 1, .type),
        (#"(?:export\s+)?enum\s+(\w+)"#, 1, .enum_),
        (#"(?:export\s+)?(?:async\s+)?function\s+(\w+)"#, 1, .function),
        (#"(?:export\s+)?const\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|[a-zA-Z_]\w*)\s*=>"#, 1, .function),
        (#"^\s+(?:async\s+)?(\w+)\s*\([^)]*\)\s*[:{]"#, 1, .method),
        (#"(?:export\s+)?(?:const|let|var)\s+(\w+)\s*[=:]"#, 1, .property),
    ])

    private static let pythonPatterns: [SymbolPattern] = buildPatterns([
        (#"class\s+(\w+)"#, 1, .class_),
        (#"(?:async\s+)?def\s+(\w+)"#, 1, .function),
        (#"(\w+)\s*:\s*\w+\s*="#, 1, .property),
    ])

    private static let goPatterns: [SymbolPattern] = buildPatterns([
        (#"type\s+(\w+)\s+struct\b"#, 1, .struct_),
        (#"type\s+(\w+)\s+interface\b"#, 1, .interface),
        (#"type\s+(\w+)\s+"#, 1, .type),
        (#"func\s+\(\w+\s+\*?\w+\)\s+(\w+)"#, 1, .method),
        (#"func\s+(\w+)"#, 1, .function),
        (#"(?:var|const)\s+(\w+)\s+"#, 1, .property),
    ])

    private static let rustPatterns: [SymbolPattern] = buildPatterns([
        (#"(?:pub(?:\([^)]+\))?\s+)?struct\s+(\w+)"#, 1, .struct_),
        (#"(?:pub(?:\([^)]+\))?\s+)?enum\s+(\w+)"#, 1, .enum_),
        (#"(?:pub(?:\([^)]+\))?\s+)?trait\s+(\w+)"#, 1, .protocol_),
        (#"(?:pub(?:\([^)]+\))?\s+)?(?:async\s+)?fn\s+(\w+)"#, 1, .function),
        (#"(?:pub(?:\([^)]+\))?\s+)?type\s+(\w+)"#, 1, .type),
        (#"(?:pub(?:\([^)]+\))?\s+)?(?:static|const)\s+(\w+)"#, 1, .constant),
    ])

    private static let javaPatterns: [SymbolPattern] = buildPatterns([
        (#"(?:public |private |protected )?(?:abstract |static |final )*class\s+(\w+)"#, 1, .class_),
        (#"(?:public |private |protected )?interface\s+(\w+)"#, 1, .interface),
        (#"(?:public |private |protected )?enum\s+(\w+)"#, 1, .enum_),
        (#"(?:public |private |protected )?(?:abstract |static |final |synchronized )*\w+(?:<[^>]+>)?\s+(\w+)\s*\("#, 1, .method),
    ])

    private static let cPatterns: [SymbolPattern] = buildPatterns([
        (#"(?:class|struct)\s+(\w+)"#, 1, .struct_),
        (#"enum\s+(\w+)"#, 1, .enum_),
        (#"(?:\w+[\s\*]+)(\w+)\s*\([^)]*\)\s*\{"#, 1, .function),
        (#"typedef\s+.+\s+(\w+)\s*;"#, 1, .type),
        (#"#define\s+(\w+)"#, 1, .constant),
    ])

    private static let rubyPatterns: [SymbolPattern] = buildPatterns([
        (#"class\s+(\w+)"#, 1, .class_),
        (#"module\s+(\w+)"#, 1, .protocol_),
        (#"def\s+(?:self\.)?(\w+[?!]?)"#, 1, .function),
        (#"attr_(?:accessor|reader|writer)\s+:(\w+)"#, 1, .property),
    ])

    private static let phpPatterns: [SymbolPattern] = buildPatterns([
        (#"(?:abstract\s+)?class\s+(\w+)"#, 1, .class_),
        (#"interface\s+(\w+)"#, 1, .interface),
        (#"trait\s+(\w+)"#, 1, .protocol_),
        (#"(?:public |private |protected )?(?:static )?function\s+(\w+)"#, 1, .function),
    ])

    private static func buildPatterns(_ defs: [(String, Int, SymbolKind)]) -> [SymbolPattern] {
        defs.compactMap { (pattern, group, kind) in
            guard let regex = try? Regex(pattern) else { return nil }
            return SymbolPattern(regex: regex, nameGroup: group, kind: kind)
        }
    }
}
