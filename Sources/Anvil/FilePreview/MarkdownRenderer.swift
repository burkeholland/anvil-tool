import Foundation

/// Converts Markdown text to HTML for rendering in a web view.
/// Handles the common subset used in README, AGENTS.md, and documentation files.
enum MarkdownRenderer {

    static func renderToHTML(_ markdown: String, darkMode: Bool = true) -> String {
        let bodyHTML = convertMarkdown(markdown)
        return wrapInDocument(bodyHTML, darkMode: darkMode)
    }

    // MARK: - Markdown → HTML Conversion

    private static func convertMarkdown(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var html: [String] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let langAttr = language.isEmpty ? "" : " class=\"language-\(escapeHTML(language))\""
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(escapeHTML(lines[i]))
                    i += 1
                }
                html.append("<pre><code\(langAttr)>\(codeLines.joined(separator: "\n"))</code></pre>")
                i += 1
                continue
            }

            // Heading
            if let heading = parseHeading(line) {
                html.append(heading)
                i += 1
                continue
            }

            // Horizontal rule
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 3 && trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) {
                let uniqueChars = Set(trimmed)
                if uniqueChars.count == 1 {
                    html.append("<hr>")
                    i += 1
                    continue
                }
            }

            // Blockquote
            if line.hasPrefix(">") || line.hasPrefix("> ") {
                var quoteLines: [String] = []
                while i < lines.count && (lines[i].hasPrefix(">") || lines[i].hasPrefix("> ")) {
                    var content = lines[i]
                    if content.hasPrefix("> ") {
                        content = String(content.dropFirst(2))
                    } else if content.hasPrefix(">") {
                        content = String(content.dropFirst(1))
                    }
                    quoteLines.append(content)
                    i += 1
                }
                let inner = convertMarkdown(quoteLines.joined(separator: "\n"))
                html.append("<blockquote>\(inner)</blockquote>")
                continue
            }

            // Unordered list
            if isUnorderedListItem(line) {
                var listItems: [String] = []
                while i < lines.count && isUnorderedListItem(lines[i]) {
                    let content = stripListMarker(lines[i])
                    listItems.append("<li>\(processInline(content))</li>")
                    i += 1
                }
                html.append("<ul>\(listItems.joined())</ul>")
                continue
            }

            // Ordered list
            if isOrderedListItem(line) {
                var listItems: [String] = []
                while i < lines.count && isOrderedListItem(lines[i]) {
                    let content = stripOrderedListMarker(lines[i])
                    listItems.append("<li>\(processInline(content))</li>")
                    i += 1
                }
                html.append("<ol>\(listItems.joined())</ol>")
                continue
            }

            // Empty line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Paragraph — collect consecutive non-empty lines
            var paraLines: [String] = []
            while i < lines.count {
                let pLine = lines[i]
                let pTrimmed = pLine.trimmingCharacters(in: .whitespaces)
                if pTrimmed.isEmpty || pLine.hasPrefix("```") || pLine.hasPrefix("#")
                    || pLine.hasPrefix(">") || isUnorderedListItem(pLine)
                    || isOrderedListItem(pLine) || isHorizontalRule(pTrimmed) {
                    break
                }
                paraLines.append(pLine)
                i += 1
            }
            if !paraLines.isEmpty {
                html.append("<p>\(processInline(paraLines.joined(separator: "\n")))</p>")
            }
        }

        return html.joined(separator: "\n")
    }

    // MARK: - Block-level Helpers

    private static func parseHeading(_ line: String) -> String? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1 && level <= 6 else { return nil }
        guard line.count > level && line[line.index(line.startIndex, offsetBy: level)] == " " else { return nil }
        let content = String(line.dropFirst(level + 1))
        return "<h\(level)>\(processInline(content))</h\(level)>"
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        let t = line.drop(while: { $0 == " " })
        return t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ")
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        let t = line.drop(while: { $0 == " " })
        guard let dotIndex = t.firstIndex(of: ".") else { return false }
        let num = t[t.startIndex..<dotIndex]
        guard !num.isEmpty && num.allSatisfy(\.isNumber) else { return false }
        let afterDot = t.index(after: dotIndex)
        return afterDot < t.endIndex && t[afterDot] == " "
    }

    private static func stripListMarker(_ line: String) -> String {
        let t = line.drop(while: { $0 == " " })
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
            return String(t.dropFirst(2))
        }
        return String(t)
    }

    private static func stripOrderedListMarker(_ line: String) -> String {
        let t = line.drop(while: { $0 == " " })
        guard let dotIndex = t.firstIndex(of: ".") else { return String(t) }
        let afterDot = t.index(after: dotIndex)
        guard afterDot < t.endIndex && t[afterDot] == " " else { return String(t) }
        return String(t[t.index(after: afterDot)...])
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let chars = Set(trimmed)
        return chars.count == 1 && (chars.contains("-") || chars.contains("*") || chars.contains("_"))
    }

    // MARK: - Inline Processing

    static func processInline(_ text: String) -> String {
        var result = escapeHTML(text)

        // Images: ![alt](src) — only allow safe schemes
        result = result.replacingPattern(
            #"!\[([^\]]*)\]\(([^)]+)\)"#,
            with: "{{IMG:$1:$2}}"
        )
        result = Self.sanitizeImages(result)

        // Links: [text](url) — only allow safe schemes
        result = result.replacingPattern(
            #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "{{LINK:$1:$2}}"
        )
        result = Self.sanitizeLinks(result)

        // Bold + italic: ***text*** or ___text___
        result = result.replacingPattern(
            #"\*\*\*(.+?)\*\*\*"#,
            with: "<strong><em>$1</em></strong>"
        )
        result = result.replacingPattern(
            #"___(.+?)___"#,
            with: "<strong><em>$1</em></strong>"
        )

        // Bold: **text** or __text__
        result = result.replacingPattern(
            #"\*\*(.+?)\*\*"#,
            with: "<strong>$1</strong>"
        )
        result = result.replacingPattern(
            #"__(.+?)__"#,
            with: "<strong>$1</strong>"
        )

        // Italic: *text* or _text_
        result = result.replacingPattern(
            #"(?<!\w)\*([^*\n]+?)\*(?!\w)"#,
            with: "<em>$1</em>"
        )
        result = result.replacingPattern(
            #"(?<!\w)_([^_\n]+?)_(?!\w)"#,
            with: "<em>$1</em>"
        )

        // Strikethrough: ~~text~~
        result = result.replacingPattern(
            #"~~(.+?)~~"#,
            with: "<del>$1</del>"
        )

        // Inline code: `text`
        result = result.replacingPattern(
            #"`([^`]+)`"#,
            with: "<code>$1</code>"
        )

        // Line breaks
        result = result.replacingOccurrences(of: "  \n", with: "<br>")

        return result
    }

    // MARK: - URL Sanitization

    private static let safeSchemes: Set<String> = ["https", "http", "mailto"]

    private static func isSafeURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespaces).lowercased()
        // Relative URLs (paths, anchors) are safe
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("#") || trimmed.hasPrefix("./") || trimmed.hasPrefix("../") {
            return true
        }
        // Check scheme
        if let colonIndex = trimmed.firstIndex(of: ":") {
            let scheme = String(trimmed[trimmed.startIndex..<colonIndex])
            return safeSchemes.contains(scheme)
        }
        // No scheme (bare path/filename) is safe
        return true
    }

    private static func sanitizeLinks(_ text: String) -> String {
        let pattern = #"\{\{LINK:([^:]*):([^}]*)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        // Process in reverse to preserve ranges
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let labelRange = Range(match.range(at: 1), in: result),
                  let urlRange = Range(match.range(at: 2), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let label = String(result[labelRange])
            let url = String(result[urlRange])
            if isSafeURL(url) {
                result.replaceSubrange(fullRange, with: "<a href=\"\(url)\">\(label)</a>")
            } else {
                result.replaceSubrange(fullRange, with: label)
            }
        }
        return result
    }

    private static func sanitizeImages(_ text: String) -> String {
        let pattern = #"\{\{IMG:([^:]*):([^}]*)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let altRange = Range(match.range(at: 1), in: result),
                  let srcRange = Range(match.range(at: 2), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let alt = String(result[altRange])
            let src = String(result[srcRange])
            // Block remote images to prevent tracking/privacy leaks
            let srcLower = src.trimmingCharacters(in: .whitespaces).lowercased()
            if srcLower.hasPrefix("http://") || srcLower.hasPrefix("https://") {
                result.replaceSubrange(fullRange, with: "<span class=\"blocked-img\">🖼 \(alt.isEmpty ? "Image" : alt) <em>(remote image blocked)</em></span>")
            } else if isSafeURL(src) {
                result.replaceSubrange(fullRange, with: "<img src=\"\(src)\" alt=\"\(alt)\" style=\"max-width:100%\">")
            } else {
                result.replaceSubrange(fullRange, with: "<span>\(alt)</span>")
            }
        }
        return result
    }

    // MARK: - HTML Utilities

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - HTML Document Template

    private static func wrapInDocument(_ body: String, darkMode: Bool) -> String {
        let bg = darkMode ? "#1e1e20" : "#ffffff"
        let fg = darkMode ? "#d4d4d4" : "#1e1e1e"
        let codeBg = darkMode ? "#2d2d30" : "#f0f0f0"
        let codeFg = darkMode ? "#ce9178" : "#c7254e"
        let preBg = darkMode ? "#1a1a1c" : "#f6f6f6"
        let linkColor = darkMode ? "#4ec9b0" : "#0366d6"
        let headingColor = darkMode ? "#e0e0e0" : "#24292e"
        let hrColor = darkMode ? "#3e3e42" : "#e1e4e8"
        let quoteBorder = darkMode ? "#4e4e52" : "#dfe2e5"
        let quoteFg = darkMode ? "#9e9e9e" : "#6a737d"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * { box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                font-size: 14px;
                line-height: 1.6;
                color: \(fg);
                background-color: \(bg);
                padding: 16px 24px;
                margin: 0;
                -webkit-font-smoothing: antialiased;
            }
            h1, h2, h3, h4, h5, h6 {
                color: \(headingColor);
                margin-top: 24px;
                margin-bottom: 12px;
                font-weight: 600;
                line-height: 1.25;
            }
            h1 { font-size: 1.8em; padding-bottom: 8px; border-bottom: 1px solid \(hrColor); }
            h2 { font-size: 1.4em; padding-bottom: 6px; border-bottom: 1px solid \(hrColor); }
            h3 { font-size: 1.15em; }
            h4 { font-size: 1em; }
            p { margin: 0 0 12px 0; }
            a { color: \(linkColor); text-decoration: none; }
            a:hover { text-decoration: underline; }
            code {
                font-family: "SF Mono", Menlo, Consolas, monospace;
                font-size: 0.9em;
                background: \(codeBg);
                color: \(codeFg);
                padding: 2px 6px;
                border-radius: 4px;
            }
            pre {
                background: \(preBg);
                border-radius: 6px;
                padding: 14px 16px;
                overflow-x: auto;
                margin: 0 0 16px 0;
            }
            pre code {
                background: none;
                color: \(fg);
                padding: 0;
                font-size: 13px;
                line-height: 1.5;
            }
            blockquote {
                border-left: 3px solid \(quoteBorder);
                color: \(quoteFg);
                padding: 4px 16px;
                margin: 0 0 16px 0;
            }
            blockquote p { margin: 0; }
            ul, ol {
                padding-left: 24px;
                margin: 0 0 12px 0;
            }
            li { margin-bottom: 4px; }
            hr {
                border: none;
                border-top: 1px solid \(hrColor);
                margin: 24px 0;
            }
            img {
                max-width: 100%;
                border-radius: 4px;
            }
            del { opacity: 0.6; }
            strong { font-weight: 600; }
            .blocked-img {
                display: inline-block;
                padding: 4px 8px;
                background: \(codeBg);
                border-radius: 4px;
                font-size: 0.9em;
                opacity: 0.7;
            }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}

// MARK: - Regex Helper

private extension String {
    func replacingPattern(_ pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return self }
        return regex.stringByReplacingMatches(
            in: self,
            range: NSRange(startIndex..., in: self),
            withTemplate: template
        )
    }
}
