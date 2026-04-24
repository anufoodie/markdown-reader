import Foundation

enum PayloadRenderer {
    // MARK: - Shared build

    static func build(sidecar: ReviewSidecar, docHash: String, docPath: String) -> ReviewPayload {
        let comments = sidecar.comments
        let summary = PayloadSummary(
            total: comments.count,
            blockers: comments.filter { $0.severity == .blocker }.count,
            questions: comments.filter { $0.severity == .question }.count,
            nitpicks: comments.filter { $0.severity == .nitpick }.count,
            approvals: comments.filter { $0.subtreeScoped && $0.resolved }.count,
            unresolved: comments.filter { !$0.resolved }.count
        )
        let docName = (docPath as NSString).lastPathComponent
        let meta = PayloadMeta(
            schemaVersion: 1,
            doc: docName,
            docPath: docPath,
            docHash: docHash,
            reviewId: sidecar.reviewId,
            round: sidecar.round,
            generatedAt: Date()
        )
        // Compute the doc's title H1 (most frequent root path prefix) so we can
        // strip it from displayed paths without losing reattachment fidelity.
        let docTitle = dominantH1Prefix(of: comments.map { $0.anchor.blockPath })
        let pcs = comments.map { c in
            PayloadComment(
                id: c.id,
                anchor: PayloadAnchor(
                    blockPath: displayPath(for: c.anchor, docTitle: docTitle),
                    blockKind: c.anchor.blockKind.rawValue,
                    quote: c.anchor.effectiveQuote
                ),
                severity: c.severity?.label,
                note: c.note,
                suggest: c.suggest,
                rationale: c.rationale,
                resolved: c.resolved,
                subtreeScoped: c.subtreeScoped,
                relatesTo: c.relatesTo.isEmpty ? nil : c.relatesTo
            )
        }
        return ReviewPayload(meta: meta, summary: summary, comments: pcs)
    }

    /// Build a human-readable path for a comment's anchor.
    /// - Strips the doc's title H1 from the prefix (if all paths share one).
    /// - Appends the heading's own text if the comment is on a heading.
    static func displayPath(for anchor: ReviewAnchor, docTitle: String?) -> String {
        var raw = anchor.blockPath
        if let title = docTitle {
            if raw == title { raw = "" }
            else if raw.hasPrefix(title + " > ") { raw = String(raw.dropFirst(title.count + 3)) }
        }
        if anchor.blockKind == .heading {
            // For headings the block quote is the heading text itself.
            // (Don't use effectiveQuote here — a range selection inside a heading
            // would otherwise replace the outline label.)
            let heading = anchor.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { return heading }
            return raw + " > " + heading
        }
        return raw.isEmpty ? "(preamble)" : raw
    }

    /// Find a single H1-title prefix shared by every path, if any.
    static func dominantH1Prefix(of paths: [String]) -> String? {
        let nonEmpty = paths.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return nil }
        // First segment of the first path
        guard let candidate = nonEmpty.first?.components(separatedBy: " > ").first else { return nil }
        let allShare = nonEmpty.allSatisfy {
            $0 == candidate || $0.hasPrefix(candidate + " > ")
        }
        return allShare ? candidate : nil
    }

    // MARK: - JSON

    static func renderJSON(_ payload: ReviewPayload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    // MARK: - Markdown

    static func renderMarkdown(_ payload: ReviewPayload) -> String {
        var out = ""
        out += "# Review — \(payload.meta.doc) (round \(payload.meta.round))\n"
        let parts: [String] = {
            var xs = ["\(payload.summary.total) comment\(payload.summary.total == 1 ? "" : "s")"]
            if payload.summary.blockers > 0 { xs.append("\(payload.summary.blockers) blocker\(payload.summary.blockers == 1 ? "" : "s")") }
            if payload.summary.questions > 0 { xs.append("\(payload.summary.questions) question\(payload.summary.questions == 1 ? "" : "s")") }
            if payload.summary.nitpicks > 0 { xs.append("\(payload.summary.nitpicks) nitpick\(payload.summary.nitpicks == 1 ? "" : "s")") }
            if payload.summary.approvals > 0 { xs.append("\(payload.summary.approvals) approved subtree\(payload.summary.approvals == 1 ? "" : "s")") }
            if payload.summary.unresolved > 0 { xs.append("\(payload.summary.unresolved) unresolved") }
            return xs
        }()
        out += "reviewId: \(payload.meta.reviewId)   docHash: \(String(payload.meta.docHash.prefix(10)))…   \(parts.joined(separator: ", "))\n\n"

        if payload.comments.isEmpty {
            out += "_No comments._\n"
            return out
        }

        for (i, c) in payload.comments.enumerated() {
            let num = i + 1
            var heading = "## Comment \(num) — "
            if let sev = c.severity { heading += "[\(sev)] " }
            heading += c.anchor.blockPath.replacingOccurrences(of: ">", with: "›")
            if c.subtreeScoped { heading += " (subtree)" }
            if c.resolved { heading += " ✓ resolved" }
            out += heading + "\n"

            // Quote block
            let quoted = c.anchor.quote
                .split(separator: "\n")
                .map { "> \($0)" }
                .joined(separator: "\n")
            if !quoted.isEmpty {
                out += quoted + "\n\n"
            }

            // Note
            if !c.note.isEmpty {
                out += "**Note:** \(c.note)\n\n"
            }

            if let sg = c.suggest, !sg.isEmpty {
                out += "**Suggest:** \(sg)\n\n"
            }
            if let r = c.rationale, !r.isEmpty {
                out += "**Why:** \(r)\n\n"
            }
            if let rel = c.relatesTo, !rel.isEmpty {
                out += "**Relates to:** \(rel.joined(separator: ", "))\n\n"
            }

            if i < payload.comments.count - 1 {
                out += "---\n\n"
            }
        }

        // Trailing block, helps the parent agent know where review ends
        out += "\n<!-- end-review reviewId=\(payload.meta.reviewId) round=\(payload.meta.round) -->\n"
        return out
    }
}
