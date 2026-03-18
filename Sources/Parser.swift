import Foundation

struct MarkdownParser {
    static func toHTML(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var html = ""
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code = ""
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    if !code.isEmpty { code += "\n" }
                    code += escapeHTML(lines[i])
                    i += 1
                }
                let langAttr = lang.isEmpty ? "" : " class=\"language-\(lang)\""
                html += "<pre><code\(langAttr)>\(code)</code></pre>\n"
                i += 1
                continue
            }

            // Blank line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Horizontal rule
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 3 {
                let ruleChars = trimmed.filter { $0 != " " }
                if ruleChars.count >= 3 && Set(ruleChars).count == 1 {
                    let c = ruleChars.first!
                    if (c == "-" || c == "_") || (c == "*" && !trimmed.hasPrefix("*") ) {
                        html += "<hr>\n"
                        i += 1
                        continue
                    }
                }
            }

            // ATX Headers
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                if level <= 6 && level < line.count {
                    let idx = line.index(line.startIndex, offsetBy: level)
                    let text = String(line[idx...]).trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: #"\s*#+\s*$"#, with: "", options: .regularExpression)
                    html += "<h\(level)>\(inlineFormat(text))</h\(level)>\n"
                    i += 1
                    continue
                }
            }

            // Blockquote
            if line.hasPrefix(">") {
                var bqLines: [String] = []
                while i < lines.count && (lines[i].hasPrefix(">") || (!lines[i].trimmingCharacters(in: .whitespaces).isEmpty && !lines[i].hasPrefix("#"))) {
                    var l = lines[i]
                    if l.hasPrefix(">") {
                        l = String(l.dropFirst())
                        if l.hasPrefix(" ") { l = String(l.dropFirst()) }
                    }
                    bqLines.append(l)
                    i += 1
                    if i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        break
                    }
                }
                let inner = MarkdownParser.toHTML(bqLines.joined(separator: "\n"))
                html += "<blockquote>\(inner)</blockquote>\n"
                continue
            }

            // Table
            if line.contains("|") && i + 1 < lines.count && isTableSeparator(lines[i + 1]) {
                html += parseTable(lines: lines, from: &i)
                continue
            }

            // Unordered list
            if isUnorderedListItem(line) {
                html += parseList(lines: lines, from: &i, ordered: false)
                continue
            }

            // Ordered list
            if isOrderedListItem(line) {
                html += parseList(lines: lines, from: &i, ordered: true)
                continue
            }

            // Paragraph
            var pLines: [String] = []
            while i < lines.count &&
                  !lines[i].trimmingCharacters(in: .whitespaces).isEmpty &&
                  !lines[i].hasPrefix("#") &&
                  !lines[i].hasPrefix("```") &&
                  !lines[i].hasPrefix(">") &&
                  !isUnorderedListItem(lines[i]) &&
                  !isOrderedListItem(lines[i]) &&
                  !isTableStart(lines, at: i) {
                pLines.append(lines[i])
                i += 1
            }
            if !pLines.isEmpty {
                html += "<p>\(inlineFormat(pLines.joined(separator: "\n")))</p>\n"
            }
        }

        return html
    }

    // MARK: - Table parsing

    private static func isTableStart(_ lines: [String], at i: Int) -> Bool {
        guard i < lines.count && lines[i].contains("|") else { return false }
        if i + 1 < lines.count && isTableSeparator(lines[i + 1]) { return true }
        return false
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard stripped.contains("|") && stripped.contains("-") else { return false }
        let cells = stripped.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        return cells.allSatisfy { $0.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " } }
    }

    private static func parseTableRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s = String(s.dropFirst()) }
        if s.hasSuffix("|") { s = String(s.dropLast()) }
        return s.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseTable(lines: [String], from i: inout Int) -> String {
        let headers = parseTableRow(lines[i])
        i += 2
        var rows: [[String]] = []
        while i < lines.count && lines[i].contains("|") && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
            rows.append(parseTableRow(lines[i]))
            i += 1
        }

        var html = "<table>\n<thead>\n<tr>\n"
        for h in headers {
            html += "<th>\(inlineFormat(h))</th>\n"
        }
        html += "</tr>\n</thead>\n<tbody>\n"
        for row in rows {
            html += "<tr>\n"
            for cell in row {
                html += "<td>\(inlineFormat(cell))</td>\n"
            }
            html += "</tr>\n"
        }
        html += "</tbody>\n</table>\n"
        return html
    }

    // MARK: - List parsing

    private static func isUnorderedListItem(_ line: String) -> Bool {
        let t = line.replacingOccurrences(of: "^\\ {0,3}", with: "", options: .regularExpression)
        return t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ")
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .init(charactersIn: " "))
        return t.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
    }

    private static func stripListMarker(_ line: String, ordered: Bool) -> String {
        if ordered {
            if let range = line.range(of: #"^\s*\d+\.\s"#, options: .regularExpression) {
                return String(line[range.upperBound...])
            }
        } else {
            if let range = line.range(of: #"^\s{0,3}[-*+]\s"#, options: .regularExpression) {
                return String(line[range.upperBound...])
            }
        }
        return line
    }

    private static func parseList(lines: [String], from i: inout Int, ordered: Bool) -> String {
        let tag = ordered ? "ol" : "ul"
        var html = "<\(tag)>\n"
        let check = ordered ? isOrderedListItem : isUnorderedListItem

        while i < lines.count && check(lines[i]) {
            let content = stripListMarker(lines[i], ordered: ordered)

            // Task list items
            if content.hasPrefix("[ ] ") {
                html += "<li class=\"task-item\"><span class=\"checkbox\"></span>\(inlineFormat(String(content.dropFirst(4))))</li>\n"
            } else if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
                html += "<li class=\"task-item done\"><span class=\"checkbox checked\"></span>\(inlineFormat(String(content.dropFirst(4))))</li>\n"
            } else {
                html += "<li>\(inlineFormat(content))</li>\n"
            }
            i += 1
        }
        html += "</\(tag)>\n"
        return html
    }

    // MARK: - Inline formatting

    static func inlineFormat(_ text: String) -> String {
        var s = text

        // Wikilinks [[page|display]] with optional display text
        s = s.replacingOccurrences(
            of: #"\[\[([^\]|]+)\|([^\]]+)\]\]"#,
            with: "<a href=\"#\" onclick=\"window.webkit.messageHandlers.wikilink.postMessage('$1');return false;\" class=\"wikilink\">$2</a>",
            options: .regularExpression
        )
        // Wikilinks [[page]]
        s = s.replacingOccurrences(
            of: #"\[\[([^\]|]+)\]\]"#,
            with: "<a href=\"#\" onclick=\"window.webkit.messageHandlers.wikilink.postMessage('$1');return false;\" class=\"wikilink\">$1</a>",
            options: .regularExpression
        )

        // Images
        s = s.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(([^)]+)\)"#,
            with: "<img src=\"$2\" alt=\"$1\" style=\"max-width:100%;border-radius:8px;\">",
            options: .regularExpression
        )

        // Links
        s = s.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )

        // Bold + Italic
        s = s.replacingOccurrences(
            of: #"\*\*\*(.+?)\*\*\*"#,
            with: "<strong><em>$1</em></strong>",
            options: .regularExpression
        )

        // Bold
        s = s.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"__(.+?)__"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Italic
        s = s.replacingOccurrences(
            of: #"(?<!\w)\*(.+?)\*(?!\w)"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"(?<!\w)_(.+?)_(?!\w)"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Strikethrough
        s = s.replacingOccurrences(
            of: #"~~(.+?)~~"#,
            with: "<del>$1</del>",
            options: .regularExpression
        )

        // Inline code
        s = s.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "<code>$1</code>",
            options: .regularExpression
        )

        // Line breaks
        s = s.replacingOccurrences(of: "  \n", with: "<br>")

        return s
    }

    // MARK: - TOC extraction

    static func extractTOC(from markdown: String) -> [(level: Int, text: String, index: Int)] {
        var entries: [(level: Int, text: String, index: Int)] = []
        var index = 0
        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                if level <= 6 && level < line.count {
                    let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: #"\s*#+\s*$"#, with: "", options: .regularExpression)
                        .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
                        .replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
                        .replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
                    entries.append((level: level, text: text, index: index))
                    index += 1
                }
            }
        }
        return entries
    }

    // MARK: - Helpers

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
