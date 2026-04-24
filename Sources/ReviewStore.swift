import Foundation
import SwiftUI

final class ReviewStore: ObservableObject {
    @Published private(set) var sidecar: ReviewSidecar?
    @Published private(set) var docHash: String = ""
    @Published private(set) var blocks: [DocBlock] = []
    @Published var focusedBlockIndex: Int = 0
    @Published var selectedCommentId: String? = nil

    /// Called when the active file URL or content changes.
    /// Loads existing sidecar if present, otherwise creates a fresh one.
    /// Re-anchors any existing comments against the new block layout.
    func bind(docURL: URL?, content: String) {
        let hash = Hash.sha256(content)
        let newBlocks = BlockExtractor.extract(content)
        self.blocks = newBlocks
        self.docHash = hash

        guard let url = docURL else {
            // Unsaved document → no sidecar
            self.sidecar = nil
            return
        }

        if let (loaded, origin) = Self.findExisting(docURL: url, docHash: hash) {
            var s = loaded
            s.docPath = url.standardizedFileURL.path  // update if file was moved
            // If doc hash changed & last round is finished, bump round.
            if let last = s.rounds.last, last.docHash != hash {
                if last.finishedAt != nil {
                    let nextRound = (s.rounds.map { $0.round }.max() ?? 0) + 1
                    s.round = nextRound
                    s.rounds.append(
                        ReviewRound(round: nextRound, docHash: hash,
                                    startedAt: Date(), finishedAt: nil,
                                    commentCount: 0, payloadSavedAt: nil)
                    )
                } else {
                    // In-progress round, doc content shifted: just update hash
                    if let idx = s.rounds.firstIndex(where: { $0.round == s.round }) {
                        s.rounds[idx].docHash = hash
                    }
                }
            }
            // Reattach all comments
            var surviving: [ReviewComment] = []
            var orphaned: [ReviewComment] = []
            for c in s.comments {
                if let (block, status) = AnchorMatcher.reattach(c.anchor, in: newBlocks) {
                    var updated = c
                    var newAnchor = ReviewAnchor.make(for: block, allBlocks: newBlocks)
                    // Preserve range if we can still find it in the new block.
                    if let resolvedRange = c.anchor.resolvedRange(in: block) {
                        newAnchor.range = resolvedRange
                        newAnchor.quote = String(resolvedRange.text.prefix(300))
                    }
                    updated.anchor = newAnchor
                    updated.reanchored = status
                    surviving.append(updated)
                } else {
                    var o = c
                    o.reanchored = .orphan
                    orphaned.append(o)
                }
            }
            s.comments = surviving
            s.orphans = orphaned
            self.sidecar = s
            // Persist to central store if we loaded from legacy (migration-on-read),
            // or if content meaningfully changed (round bump / reattach).
            switch origin {
            case .legacy:
                try? Self.saveCentral(s, docHash: hash)
            case .central:
                if !equalInCentral(s) {
                    try? Self.saveCentral(s, docHash: hash)
                }
            }
        } else {
            // No sidecar anywhere. Build an in-memory fresh one but DO NOT persist
            // until the user actually does something review-related (adds a comment,
            // finishes a round, etc.). Keeps the filesystem clean.
            self.sidecar = ReviewSidecar.fresh(
                docPath: url.standardizedFileURL.path,
                docHash: hash
            )
        }
    }

    /// Compare against what's in central storage to avoid no-op writes.
    private func equalInCentral(_ s: ReviewSidecar) -> Bool {
        let url = Self.centralURL(for: s.reviewId)
        guard let data = try? Data(contentsOf: url) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let existing = try? decoder.decode(ReviewSidecar.self, from: data) else {
            return false
        }
        return existing.reviewId == s.reviewId
            && existing.round == s.round
            && existing.rounds == s.rounds
            && existing.comments == s.comments
            && existing.orphans == s.orphans
    }

    // MARK: - Mutations

    func addComment(
        anchor: ReviewAnchor,
        note: String,
        suggest: String? = nil,
        rationale: String? = nil,
        severity: Severity? = nil,
        subtreeScoped: Bool = false
    ) {
        guard var s = sidecar else { return }
        let c = ReviewComment(
            anchor: anchor,
            note: note,
            suggest: suggest,
            rationale: rationale,
            severity: severity,
            subtreeScoped: subtreeScoped
        )
        s.comments.append(c)
        incrementRoundCount(&s)
        sidecar = s
        selectedCommentId = c.id
        persist()
    }

    func updateComment(_ id: String, mutator: (inout ReviewComment) -> Void) {
        guard var s = sidecar, let idx = s.comments.firstIndex(where: { $0.id == id }) else { return }
        mutator(&s.comments[idx])
        sidecar = s
        persist()
    }

    func toggleResolved(_ id: String) {
        updateComment(id) { $0.resolved.toggle() }
    }

    func deleteComment(_ id: String) {
        guard var s = sidecar else { return }
        s.comments.removeAll { $0.id == id }
        s.orphans.removeAll { $0.id == id }
        sidecar = s
        if selectedCommentId == id { selectedCommentId = nil }
        persist()
    }

    func approveSubtree(at anchor: ReviewAnchor) {
        addComment(anchor: anchor, note: "Approved — leave subtree as-is on next round.",
                   severity: nil, subtreeScoped: true)
        // Auto-resolve immediately; it's a positive signal, not a pending ask.
        if let last = sidecar?.comments.last {
            toggleResolved(last.id)
        }
    }

    func finishCurrentRound() {
        guard var s = sidecar else { return }
        if let idx = s.rounds.firstIndex(where: { $0.round == s.round }) {
            s.rounds[idx].finishedAt = Date()
            s.rounds[idx].commentCount = s.comments.count
            s.rounds[idx].payloadSavedAt = Date()
        }
        sidecar = s
        persist()
    }

    // MARK: - Derived

    var unresolvedCount: Int { sidecar?.comments.filter { !$0.resolved }.count ?? 0 }
    var orphanCount: Int { sidecar?.orphans.count ?? 0 }

    func orderedComments() -> [ReviewComment] {
        guard let s = sidecar else { return [] }
        // Stable order: by block globalIndex, then by createdAt.
        let indexByBlock = blockIndexByAnchor()
        return s.comments.sorted { a, b in
            let ai = indexByBlock[a.id] ?? Int.max
            let bi = indexByBlock[b.id] ?? Int.max
            if ai != bi { return ai < bi }
            return a.createdAt < b.createdAt
        }
    }

    private func blockIndexByAnchor() -> [String: Int] {
        guard let s = sidecar else { return [:] }
        var result: [String: Int] = [:]
        for c in s.comments {
            if let b = blocks.first(where: {
                $0.path == c.anchor.blockPath
                    && Hash.blockHash($0.content) == c.anchor.contentHash
            }) {
                result[c.id] = b.globalIndex
            } else if let b = blocks.first(where: { $0.path == c.anchor.blockPath }) {
                result[c.id] = b.globalIndex
            }
        }
        return result
    }

    // MARK: - Focus helpers

    func focusBlock(domId: String) {
        if let idx = blocks.firstIndex(where: { blockDomId($0) == domId }) {
            focusedBlockIndex = idx
        }
    }

    func moveFocus(by delta: Int) {
        guard !blocks.isEmpty else { return }
        let next = max(0, min(blocks.count - 1, focusedBlockIndex + delta))
        focusedBlockIndex = next
    }

    var focusedBlock: DocBlock? {
        guard blocks.indices.contains(focusedBlockIndex) else { return nil }
        return blocks[focusedBlockIndex]
    }

    func blockDomId(_ b: DocBlock) -> String {
        let hash = Hash.blockHash(b.content)
        let short = String(hash.prefix(10))
        return "b-\(short)-\(b.globalIndex)"
    }

    func domIdFor(comment: ReviewComment) -> String? {
        guard let b = blocks.first(where: {
            $0.path == comment.anchor.blockPath
                && Hash.blockHash($0.content) == comment.anchor.contentHash
        }) else { return nil }
        return blockDomId(b)
    }

    // MARK: - Next/prev comment navigation

    func selectNextComment(unresolvedOnly: Bool = false) {
        guard let s = sidecar else { return }
        let pool = unresolvedOnly ? s.comments.filter { !$0.resolved } : s.comments
        guard !pool.isEmpty else { return }
        let ordered = orderedComments().filter { c in pool.contains(where: { $0.id == c.id }) }
        guard !ordered.isEmpty else { return }
        if let current = selectedCommentId,
           let idx = ordered.firstIndex(where: { $0.id == current }) {
            let next = (idx + 1) % ordered.count
            selectedCommentId = ordered[next].id
        } else {
            selectedCommentId = ordered.first?.id
        }
    }

    func selectPrevComment(unresolvedOnly: Bool = false) {
        guard let s = sidecar else { return }
        let pool = unresolvedOnly ? s.comments.filter { !$0.resolved } : s.comments
        guard !pool.isEmpty else { return }
        let ordered = orderedComments().filter { c in pool.contains(where: { $0.id == c.id }) }
        guard !ordered.isEmpty else { return }
        if let current = selectedCommentId,
           let idx = ordered.firstIndex(where: { $0.id == current }) {
            let prev = (idx - 1 + ordered.count) % ordered.count
            selectedCommentId = ordered[prev].id
        } else {
            selectedCommentId = ordered.last?.id
        }
    }

    // MARK: - Private — state bookkeeping

    private func incrementRoundCount(_ s: inout ReviewSidecar) {
        if let idx = s.rounds.firstIndex(where: { $0.round == s.round }) {
            s.rounds[idx].commentCount = s.comments.count
        }
    }

    private func persist() {
        guard let s = sidecar else { return }
        try? Self.saveCentral(s, docHash: docHash)
    }

    // MARK: - I/O

    /// Legacy in-tree sidecar path (foo.md.review.json). Read only, for back-compat.
    static func legacySidecarURL(for docURL: URL) -> URL {
        let name = docURL.lastPathComponent + ".review.json"
        return docURL.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Root of centralized review storage.
    /// ~/Library/Application Support/Markdown Reader/reviews/
    static func reviewsRoot() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()
                   + "/Library/Application Support")
        let dir = base.appendingPathComponent("Markdown Reader/reviews",
                                              isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func centralURL(for reviewId: String) -> URL {
        reviewsRoot().appendingPathComponent("\(reviewId).json")
    }

    static func indexURL() -> URL {
        reviewsRoot().appendingPathComponent("_index.json")
    }

    /// Index mapping docPath (absolute) and docHash (sha256 hex) → reviewId.
    struct ReviewIndex: Codable {
        var byPath: [String: String] = [:]
        var byHash: [String: String] = [:]
    }

    static func loadIndex() -> ReviewIndex {
        guard let data = try? Data(contentsOf: indexURL()) else { return ReviewIndex() }
        return (try? JSONDecoder().decode(ReviewIndex.self, from: data)) ?? ReviewIndex()
    }

    static func saveIndex(_ idx: ReviewIndex) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(idx) else { return }
        try? data.write(to: indexURL(), options: .atomic)
    }

    /// Look up the existing reviewId for this doc, if any, and return its sidecar.
    /// Search order: central-by-path → central-by-hash → legacy sidecar next to doc.
    static func findExisting(docURL: URL, docHash: String) -> (ReviewSidecar, origin: SidecarOrigin)? {
        let path = docURL.standardizedFileURL.path
        let idx = loadIndex()

        if let rid = idx.byPath[path],
           let s = try? load(from: centralURL(for: rid)) {
            return (s, .central)
        }
        if let rid = idx.byHash[docHash],
           let s = try? load(from: centralURL(for: rid)) {
            return (s, .central)
        }
        let legacy = legacySidecarURL(for: docURL)
        if FileManager.default.fileExists(atPath: legacy.path),
           let s = try? load(from: legacy) {
            return (s, .legacy(legacy))
        }
        return nil
    }

    enum SidecarOrigin {
        case central
        case legacy(URL)
    }

    static func load(from url: URL) throws -> ReviewSidecar {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ReviewSidecar.self, from: data)
    }

    /// Persist a sidecar to central storage and update the index.
    static func saveCentral(_ sidecar: ReviewSidecar, docHash: String) throws {
        let url = centralURL(for: sidecar.reviewId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sidecar)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmp, to: url)

        var idx = loadIndex()
        idx.byPath[sidecar.docPath] = sidecar.reviewId
        idx.byHash[docHash] = sidecar.reviewId
        saveIndex(idx)
    }
}
