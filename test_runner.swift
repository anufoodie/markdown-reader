// Standalone test runner. Compile with:
//   swiftc test_runner.swift Sources/ReviewModel.swift Sources/ReviewAnchor.swift \
//     Sources/ReviewPayload.swift -o /tmp/test-bin
// Run:
//   ./test-bin

import Foundation

@main
struct TestRunner {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String,
                       file: String = #file, line: Int = #line) {
        if condition {
            passes += 1
            print("  ✓ \(message)")
        } else {
            failures += 1
            print("  ✗ \(message)  [\(file):\(line)]")
        }
    }

    static func section(_ name: String, _ body: () -> Void) {
        print("\n— \(name) —")
        body()
    }

    static func main() {
        let cwd = FileManager.default.currentDirectoryPath
        let sampleURL = URL(fileURLWithPath: cwd).appendingPathComponent("sample-review.md")
        guard let sampleMD = try? String(contentsOf: sampleURL) else {
            print("✗ Could not read sample-review.md at \(sampleURL.path)")
            exit(1)
        }

        testBlockExtractor(sampleMD: sampleMD)
        testAnchorRoundTrip(sampleMD: sampleMD)
        testPayloadRendering(sampleMD: sampleMD)
        testSidecarCodec(sampleMD: sampleMD)
        testRangeAnchor(sampleMD: sampleMD)

        print("\n======================================")
        print("  \(passes) passed · \(failures) failed")
        print("======================================")
        if failures > 0 { exit(1) }
    }

    static func testBlockExtractor(sampleMD: String) {
        section("BlockExtractor on sample-review.md") {
            let blocks = BlockExtractor.extract(sampleMD)
            expect(blocks.count > 10, "extracts many blocks (\(blocks.count))")
            expect(blocks.first?.kind == .heading, "first block is a heading")
            expect(blocks.first?.headingLevel == 1, "first block is H1")
            expect(blocks.first?.headingText?.contains("Auth Service") == true,
                   "first heading text contains Auth Service")
            expect(blocks[1].kind == .paragraph, "second block is paragraph")
            expect(blocks.contains(where: { $0.kind == .code }), "contains a code block")
            expect(blocks.contains(where: { $0.kind == .list }), "contains a list block")

            if let tokensHeading = blocks.first(where: { $0.headingText == "Tokens" }) {
                expect(tokensHeading.kind == .heading, "Tokens is a heading")
                expect(tokensHeading.headingLevel == 2, "Tokens is H2")
            } else {
                expect(false, "found Tokens heading")
            }

            if let tokenFormat = blocks.first(where: { $0.headingText == "Token format" }) {
                // Stored path includes full ancestry (H1 title → Tokens) for reattach fidelity.
                expect(tokenFormat.path.hasSuffix("> Tokens"),
                       "Token format parent ends with 'Tokens', got '\(tokenFormat.path)'")
            } else {
                expect(false, "found Token format heading")
            }

            if let migration = blocks.first(where: { $0.headingText == "Migration" }) {
                expect(migration.path.hasSuffix("> Storage"),
                       "Migration parent ends with 'Storage', got '\(migration.path)'")
            } else {
                expect(false, "found Migration heading")
            }

            let gidxs = blocks.map { $0.globalIndex }
            expect(gidxs == Array(0..<blocks.count), "globalIndex is 0..<count, monotonic")

            print("    Block summary: \(blocks.count) total")
            let kinds = Dictionary(grouping: blocks, by: { $0.kind }).mapValues { $0.count }
            for (k, v) in kinds.sorted(by: { $0.value > $1.value }) {
                print("      \(k.rawValue): \(v)")
            }
        }
    }

    static func testAnchorRoundTrip(sampleMD: String) {
        section("Anchor compute + reattach") {
            let blocks = BlockExtractor.extract(sampleMD)
            guard let ttlPara = blocks.first(where: {
                $0.kind == .paragraph && $0.content.contains("15 minutes")
            }) else {
                expect(false, "found TTL paragraph in sample")
                return
            }
            let anchor = ReviewAnchor.make(for: ttlPara, allBlocks: blocks)
            expect(anchor.blockPath.hasSuffix("> Tokens"),
                   "anchor path ends with 'Tokens', got '\(anchor.blockPath)'")
            expect(anchor.contentHash == Hash.blockHash(ttlPara.content),
                   "contentHash matches recomputed hash")

            if let (block, status) = AnchorMatcher.reattach(anchor, in: blocks) {
                expect(status == .exact, "reattach against same doc → exact")
                expect(block.content == ttlPara.content,
                       "reattached block content equals original")
            } else {
                expect(false, "reattach against same doc finds a block")
            }

            let modified = sampleMD.replacingOccurrences(
                of: "Tokens expire after 15 minutes.",
                with: "Tokens expire after 15 minutes in general usage. A refresh is needed before expiry."
            )
            let modBlocks = BlockExtractor.extract(modified)
            if let (block, status) = AnchorMatcher.reattach(anchor, in: modBlocks) {
                expect(status == .fuzzy || status == .moved,
                       "reattach on edited paragraph → fuzzy or moved (got \(status))")
                expect(block.path.hasSuffix("> Tokens"), "fuzzy match keeps same subtree")
            } else {
                expect(false, "fuzzy reattach found a match")
            }

            let deleted = sampleMD.replacingOccurrences(
                of: "Tokens expire after 15 minutes. Clients must refresh using the refresh endpoint before expiry.",
                with: ""
            )
            let delBlocks = BlockExtractor.extract(deleted)
            let result = AnchorMatcher.reattach(anchor, in: delBlocks)
            expect(result == nil, "reattach on deleted paragraph → nil (orphan)")
        }
    }

    static func testPayloadRendering(sampleMD: String) {
        section("Payload rendering") {
            let blocks = BlockExtractor.extract(sampleMD)
            guard let ttlPara = blocks.first(where: {
                $0.kind == .paragraph && $0.content.contains("15 minutes")
            }),
            let sessionsHeading = blocks.first(where: { $0.headingText == "Sessions" }) else {
                expect(false, "found fixtures for payload test")
                return
            }

            let a1 = ReviewAnchor.make(for: ttlPara, allBlocks: blocks)
            let a2 = ReviewAnchor.make(for: sessionsHeading, allBlocks: blocks)

            let comments: [ReviewComment] = [
                ReviewComment(
                    anchor: a1,
                    note: "TTL is inconsistent with §5 which says 60 min.",
                    suggest: "Tokens expire after 60 minutes (aligns with refresh TTL).",
                    rationale: "Refresh TTL defines the ceiling for the access TTL.",
                    severity: .blocker
                ),
                ReviewComment(
                    anchor: a2,
                    note: "Unclear: 'persist across restarts' — which restarts?",
                    severity: .question,
                    subtreeScoped: true
                )
            ]
            var sidecar = ReviewSidecar.fresh(docPath: "/tmp/sample.md", docHash: "abc")
            sidecar.comments = comments

            let payload = PayloadRenderer.build(sidecar: sidecar, docHash: "abc",
                                                docPath: "/tmp/sample.md")
            expect(payload.meta.round == 1, "round == 1")
            expect(payload.meta.reviewId.hasPrefix("r_"), "reviewId prefix r_")
            expect(payload.summary.total == 2, "total = 2")
            expect(payload.summary.blockers == 1, "blockers = 1")
            expect(payload.summary.questions == 1, "questions = 1")
            expect(payload.summary.unresolved == 2, "unresolved = 2 (none marked resolved)")

            let md = PayloadRenderer.renderMarkdown(payload)
            expect(md.contains("# Review"), "markdown has title")
            expect(md.contains("Comment 1"), "has Comment 1")
            expect(md.contains("Comment 2"), "has Comment 2")
            expect(md.contains("[blocker]"), "shows blocker tag")
            expect(md.contains("[question]"), "shows question tag")
            expect(md.contains("Suggest:"), "includes Suggest: field")
            expect(md.contains("Why:"), "includes Why: rationale")
            expect(md.contains("(subtree)"), "shows subtree marker")
            expect(md.contains("end-review"), "has end-review marker comment")

            let json = PayloadRenderer.renderJSON(payload)
            expect(json.contains("\"reviewId\""), "JSON has reviewId key")
            expect(json.contains("\"severity\""), "JSON has severity key")
            expect(json.contains("\"blocker\""), "JSON contains blocker severity")

            print("\n  — markdown payload preview —")
            for line in md.components(separatedBy: "\n").prefix(24) {
                print("    \(line)")
            }
        }
    }

    static func testRangeAnchor(sampleMD: String) {
        section("Range anchor (per-word / per-phrase)") {
            let blocks = BlockExtractor.extract(sampleMD)
            guard let ttlPara = blocks.first(where: {
                $0.kind == .paragraph && $0.content.contains("15 minutes")
            }) else {
                expect(false, "found fixture paragraph")
                return
            }
            var anchor = ReviewAnchor.make(for: ttlPara, allBlocks: blocks)
            anchor.range = ReviewRange(text: "15 minutes", offsetInBlock: 15)
            // NB: we deliberately DO NOT overwrite anchor.quote — the block-prefix
            // quote is needed intact as a fuzzy-match signal for block reattach.

            // Reattach against same doc: the range text should resolve
            if let resolved = anchor.resolvedRange(in: ttlPara) {
                expect(resolved.text == "15 minutes", "range text preserved on same-doc reattach")
            } else {
                expect(false, "resolvedRange found range in same doc")
            }

            // Modified doc where the substring survives
            let modified = sampleMD.replacingOccurrences(
                of: "Tokens expire after 15 minutes.",
                with: "Access tokens expire after 15 minutes in practice."
            )
            let modBlocks = BlockExtractor.extract(modified)
            if let (newBlock, _) = AnchorMatcher.reattach(anchor, in: modBlocks),
               let resolved = anchor.resolvedRange(in: newBlock) {
                expect(resolved.text == "15 minutes",
                       "range text '15 minutes' survives edit (got '\(resolved.text)')")
            } else {
                expect(false, "range-preserving reattach on edit")
            }

            // Modified doc where the substring is deleted
            let stripped = sampleMD.replacingOccurrences(
                of: "15 minutes", with: "a while"
            )
            let stripBlocks = BlockExtractor.extract(stripped)
            if let (newBlock, _) = AnchorMatcher.reattach(anchor, in: stripBlocks) {
                let resolved = anchor.resolvedRange(in: newBlock)
                expect(resolved == nil, "range text gone → resolvedRange returns nil (got \(String(describing: resolved)))")
            } else {
                expect(false, "block-level reattach should still succeed")
            }

            // Codable round-trip with range
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(anchor) else {
                expect(false, "encode anchor with range"); return
            }
            let decoder = JSONDecoder()
            guard let decoded = try? decoder.decode(ReviewAnchor.self, from: data) else {
                expect(false, "decode anchor with range"); return
            }
            expect(decoded.range?.text == "15 minutes", "range round-trips through codable")
        }
    }

    static func testSidecarCodec(sampleMD: String) {
        section("Sidecar JSON codec round-trip") {
            let blocks = BlockExtractor.extract(sampleMD)
            guard let first = blocks.first else {
                expect(false, "blocks non-empty")
                return
            }
            let anchor = ReviewAnchor.make(for: first, allBlocks: blocks)
            var sidecar = ReviewSidecar.fresh(docPath: "/tmp/t.md", docHash: "deadbeef")
            sidecar.comments = [
                ReviewComment(anchor: anchor, note: "hi", suggest: nil, severity: nil)
            ]

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(sidecar) else {
                expect(false, "encoding sidecar")
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let decoded = try? decoder.decode(ReviewSidecar.self, from: data) else {
                expect(false, "decoding sidecar")
                return
            }
            expect(decoded.reviewId == sidecar.reviewId, "reviewId preserved")
            expect(decoded.comments.count == 1, "comment count preserved")
            expect(decoded.comments.first?.note == "hi", "comment note preserved")
        }
    }
}
