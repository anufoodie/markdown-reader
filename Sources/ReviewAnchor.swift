import Foundation

// MARK: - Block extraction
//
// The extractor MUST emit blocks in the same order and at the same granularity
// as Parser.swift's top-level HTML output, so that the N-th extracted block
// corresponds to the N-th top-level child of `#content` in the rendered DOM.
// This lets the WebView tag blocks with positional DOM ids (`b-<index>`) and
// Swift can map a clicked DOM id back to a DocBlock via `blocks[index]`.

struct DocBlock {
    var kind: BlockKind
    /// Outline path (e.g. "Auth > Tokens"), empty for pre-first-heading blocks.
    var path: String
    /// Ordinal within the immediate section.
    var indexInSection: Int
    /// Raw source text of the block (markdown, not HTML).
    var content: String
    /// For headings: the visible heading text (without hashes).
    var headingText: String?
    /// Heading level if `kind == .heading`.
    var headingLevel: Int?
    /// Global ordinal across whole doc. This is the DOM position.
    var globalIndex: Int
}

enum BlockExtractor {
    static func extract(_ md: String) -> [DocBlock] {
        let lines = md.components(separatedBy: "\n")
        var blocks: [DocBlock] = []
        var pathStack: [(level: Int, text: String)] = []
        var indexInSection = 0
        var globalIndex = 0
        var i = 0

        func currentPath() -> String {
            pathStack.map { $0.text }.joined(separator: " > ")
        }

        func emit(_ kind: BlockKind, content: String,
                  headingText: String? = nil, headingLevel: Int? = nil) {
            let block = DocBlock(
                kind: kind,
                path: currentPath(),
                indexInSection: indexInSection,
                content: content,
                headingText: headingText,
                headingLevel: headingLevel,
                globalIndex: globalIndex
            )
            blocks.append(block)
            indexInSection += 1
            globalIndex += 1
        }

        while i < lines.count {
            let line = lines[i]

            // 1. Fenced code block (must come before other checks)
            if line.hasPrefix("```") {
                var code = line + "\n"
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code += lines[i] + "\n"
                    i += 1
                }
                if i < lines.count { code += lines[i] + "\n"; i += 1 }
                emit(.code, content: code)
                continue
            }

            // 2. Blank line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // 3. Horizontal rule (must come before heading — "---" has no "#")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 3 {
                let ruleChars = trimmed.filter { $0 != " " }
                if ruleChars.count >= 3 && Set(ruleChars).count == 1 {
                    let c = ruleChars.first!
                    if (c == "-" || c == "_") || (c == "*" && !trimmed.hasPrefix("*")) {
                        emit(.horizontalRule, content: line)
                        i += 1
                        continue
                    }
                }
            }

            // 4. ATX Heading
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                if level <= 6 && level < line.count {
                    let idx = line.index(line.startIndex, offsetBy: level)
                    let text = String(line[idx...]).trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: #"\s*#+\s*$"#, with: "", options: .regularExpression)
                    // Pop deeper-or-equal levels off the stack
                    while let top = pathStack.last, top.level >= level {
                        pathStack.removeLast()
                    }
                    // Emit heading first (its path = parent), THEN push onto stack
                    emit(.heading, content: text, headingText: text, headingLevel: level)
                    pathStack.append((level: level, text: text))
                    indexInSection = 0
                    i += 1
                    continue
                }
            }

            // 5. Blockquote
            if line.hasPrefix(">") {
                var bqLines: [String] = []
                while i < lines.count &&
                      (lines[i].hasPrefix(">") ||
                       (!lines[i].trimmingCharacters(in: .whitespaces).isEmpty && !lines[i].hasPrefix("#"))) {
                    bqLines.append(lines[i])
                    i += 1
                    if i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        break
                    }
                }
                emit(.blockquote, content: bqLines.joined(separator: "\n"))
                continue
            }

            // 6. Table
            if line.contains("|") && i + 1 < lines.count && isTableSeparator(lines[i + 1]) {
                var tableLines: [String] = [lines[i], lines[i + 1]]
                i += 2
                while i < lines.count && lines[i].contains("|") &&
                      !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    tableLines.append(lines[i])
                    i += 1
                }
                emit(.table, content: tableLines.joined(separator: "\n"))
                continue
            }

            // 7. Unordered list
            if isUnorderedListItem(line) {
                var listLines: [String] = []
                while i < lines.count && isUnorderedListItem(lines[i]) {
                    listLines.append(lines[i])
                    i += 1
                }
                emit(.list, content: listLines.joined(separator: "\n"))
                continue
            }

            // 8. Ordered list
            if isOrderedListItem(line) {
                var listLines: [String] = []
                while i < lines.count && isOrderedListItem(lines[i]) {
                    listLines.append(lines[i])
                    i += 1
                }
                emit(.list, content: listLines.joined(separator: "\n"))
                continue
            }

            // 9. Paragraph (accumulate until blank/heading/list/code/quote/table)
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
                emit(.paragraph, content: pLines.joined(separator: "\n"))
            }
        }

        return blocks
    }

    // MARK: - Private helpers (duplicated from Parser.swift to keep modules independent)

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

    private static func isUnorderedListItem(_ line: String) -> Bool {
        let t = line.replacingOccurrences(of: "^\\ {0,3}", with: "", options: .regularExpression)
        return t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ")
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .init(charactersIn: " "))
        return t.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
    }
}

// MARK: - Anchor from block

extension ReviewAnchor {
    static func make(for block: DocBlock, allBlocks: [DocBlock]) -> ReviewAnchor {
        let content = block.content
        let hash = Hash.blockHash(content)
        let quote = String(content.prefix(140))
        let before: String = {
            guard block.globalIndex > 0 else { return "" }
            let prev = allBlocks[block.globalIndex - 1].content
            return String(prev.suffix(80))
        }()
        let after: String = {
            let next = block.globalIndex + 1
            guard next < allBlocks.count else { return "" }
            return String(allBlocks[next].content.prefix(80))
        }()
        return ReviewAnchor(
            blockPath: block.path,
            blockIndex: block.indexInSection,
            blockKind: block.kind,
            contentHash: hash,
            quote: quote,
            contextBefore: before,
            contextAfter: after,
            range: nil
        )
    }

    /// Best-effort range reattachment. If the stored range.text can still be
    /// found in the new block content, return a matching range; otherwise nil.
    func resolvedRange(in newBlock: DocBlock) -> ReviewRange? {
        guard let range = self.range else { return nil }
        let haystack = newBlock.content
        // Exact substring match
        if let r = haystack.range(of: range.text) {
            let offset = haystack.distance(from: haystack.startIndex, to: r.lowerBound)
            return ReviewRange(text: range.text, offsetInBlock: offset)
        }
        // Case-insensitive substring
        if let r = haystack.range(of: range.text, options: .caseInsensitive) {
            let offset = haystack.distance(from: haystack.startIndex, to: r.lowerBound)
            let matched = String(haystack[r])
            return ReviewRange(text: matched, offsetInBlock: offset)
        }
        return nil
    }
}

// MARK: - Reattachment

enum AnchorMatcher {
    static func reattach(
        _ old: ReviewAnchor,
        in blocks: [DocBlock]
    ) -> (block: DocBlock, status: ReanchorStatus)? {
        // 1. Exact — same path + kind + contentHash
        if let exact = blocks.first(where: {
            $0.path == old.blockPath
                && $0.kind == old.blockKind
                && Hash.blockHash($0.content) == old.contentHash
        }) {
            return (exact, .exact)
        }

        // 2. Moved — matching contentHash anywhere
        if let moved = blocks.first(where: {
            Hash.blockHash($0.content) == old.contentHash
        }) {
            return (moved, .moved)
        }

        // 3. Fuzzy — same kind, same subtree, token-overlap above threshold
        let subtreeCandidates = blocks.filter { b in
            b.path == old.blockPath
                || b.path.hasPrefix(old.blockPath + " > ")
                || (old.blockPath.isEmpty)
        }
        let oldQuoteTokens = tokens(old.quote)
        if !oldQuoteTokens.isEmpty {
            var best: (block: DocBlock, score: Double)?
            for cand in subtreeCandidates where cand.kind == old.blockKind {
                let candTokens = tokens(String(cand.content.prefix(140)))
                let score = jaccard(oldQuoteTokens, candTokens)
                if score >= 0.6, score > (best?.score ?? 0) {
                    best = (cand, score)
                }
            }
            if let b = best {
                return (b.block, .fuzzy)
            }
        }

        return nil
    }

    private static func tokens(_ s: String) -> Set<String> {
        let normalized = Hash.normalize(s)
        let words = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return Set(words.map(String.init).filter { $0.count >= 3 })
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty && b.isEmpty { return 0 }
        let inter = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(inter) / Double(union)
    }
}
