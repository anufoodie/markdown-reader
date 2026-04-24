import Foundation
import CryptoKit

// MARK: - Severity

enum Severity: String, Codable, CaseIterable {
    case blocker, question, nitpick

    var symbol: String {
        switch self {
        case .blocker: return "!"
        case .question: return "?"
        case .nitpick: return "."
        }
    }

    var label: String {
        switch self {
        case .blocker: return "blocker"
        case .question: return "question"
        case .nitpick: return "nitpick"
        }
    }

    var icon: String {
        switch self {
        case .blocker: return "exclamationmark.triangle.fill"
        case .question: return "questionmark.circle.fill"
        case .nitpick: return "circle.dotted"
        }
    }
}

// MARK: - Verdict (round ≥ 2)

enum Verdict: String, Codable {
    case addressed, partial, open
}

// MARK: - Block kind

enum BlockKind: String, Codable {
    case heading
    case paragraph
    case list
    case blockquote
    case code
    case table
    case horizontalRule = "hr"
    case unknown
}

// MARK: - Anchor

/// A specific character range inside a block (for per-word/per-line comments).
struct ReviewRange: Codable, Equatable {
    /// The exact text that was selected.
    var text: String
    /// Character offset within the block's visible text (approx, best-effort).
    var offsetInBlock: Int
}

struct ReviewAnchor: Codable, Equatable {
    /// Outline path in `H2 > H3` form, e.g. "Auth > Tokens".
    var blockPath: String
    /// Ordinal index within the immediate heading section (0-based).
    var blockIndex: Int
    var blockKind: BlockKind
    /// sha256 hex of normalized block content.
    var contentHash: String
    /// First ~140 chars of block content, for display + fuzzy fallback.
    var quote: String
    var contextBefore: String
    var contextAfter: String
    /// Optional range inside the block — set when user commented on a selection.
    /// nil means the comment scopes to the whole block.
    var range: ReviewRange?

    /// Stable DOM id used in the rendered HTML.
    /// Form: `b-<hash-short>-<index>`. Collisions across docs are fine (per-doc).
    var domId: String {
        let short = String(contentHash.prefix(10))
        return "b-\(short)-\(blockIndex)"
    }

    /// Text shown to the user and in the payload quote.
    /// If a specific range was selected, prefer that; otherwise fall back to
    /// the first-140-chars block prefix.
    var effectiveQuote: String {
        if let range = range, !range.text.isEmpty {
            return range.text
        }
        return quote
    }
}

// MARK: - Comment

struct ReviewComment: Codable, Identifiable, Equatable {
    var id: String
    var anchor: ReviewAnchor
    var note: String
    var suggest: String?
    var rationale: String?
    var severity: Severity?
    var resolved: Bool
    var verdict: Verdict?
    var relatesTo: [String]
    var createdAt: Date
    var reanchored: ReanchorStatus?

    /// Heading-subtree-scope signal. Set when the anchor is a heading
    /// and user's intent is "this whole subtree".
    var subtreeScoped: Bool

    init(
        id: String = UUID().uuidString,
        anchor: ReviewAnchor,
        note: String,
        suggest: String? = nil,
        rationale: String? = nil,
        severity: Severity? = nil,
        resolved: Bool = false,
        verdict: Verdict? = nil,
        relatesTo: [String] = [],
        createdAt: Date = Date(),
        reanchored: ReanchorStatus? = nil,
        subtreeScoped: Bool = false
    ) {
        self.id = id
        self.anchor = anchor
        self.note = note
        self.suggest = suggest
        self.rationale = rationale
        self.severity = severity
        self.resolved = resolved
        self.verdict = verdict
        self.relatesTo = relatesTo
        self.createdAt = createdAt
        self.reanchored = reanchored
        self.subtreeScoped = subtreeScoped
    }
}

enum ReanchorStatus: String, Codable {
    case exact   // contentHash matched at original path
    case moved   // contentHash matched elsewhere
    case fuzzy   // quote/context overlap
    case orphan  // could not reattach
}

// MARK: - Round

struct ReviewRound: Codable, Equatable {
    var round: Int
    var docHash: String
    var startedAt: Date
    var finishedAt: Date?
    var commentCount: Int
    var payloadSavedAt: Date?
}

// MARK: - Sidecar (persisted review state)

struct ReviewSidecar: Codable {
    var schemaVersion: Int = 1
    var reviewId: String
    var docPath: String
    var round: Int
    var rounds: [ReviewRound]
    var comments: [ReviewComment]
    var orphans: [ReviewComment]

    static func fresh(docPath: String, docHash: String) -> ReviewSidecar {
        ReviewSidecar(
            schemaVersion: 1,
            reviewId: Self.newReviewId(),
            docPath: docPath,
            round: 1,
            rounds: [
                ReviewRound(round: 1, docHash: docHash, startedAt: Date(),
                            finishedAt: nil, commentCount: 0, payloadSavedAt: nil)
            ],
            comments: [],
            orphans: []
        )
    }

    var currentRound: ReviewRound? {
        rounds.first(where: { $0.round == round })
    }

    static func newReviewId() -> String {
        // r_<6 base36 chars>
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let tail = (0..<6).map { _ in chars.randomElement()! }
        return "r_\(String(tail))"
    }
}

// MARK: - Payload

struct PayloadSummary: Codable {
    var total: Int
    var blockers: Int
    var questions: Int
    var nitpicks: Int
    var approvals: Int
    var unresolved: Int
}

struct PayloadMeta: Codable {
    var schemaVersion: Int
    var doc: String
    var docPath: String
    var docHash: String
    var reviewId: String
    var round: Int
    var generatedAt: Date
}

struct PayloadComment: Codable {
    var id: String
    var anchor: PayloadAnchor
    var severity: String?
    var note: String
    var suggest: String?
    var rationale: String?
    var resolved: Bool
    var subtreeScoped: Bool
    var relatesTo: [String]?
}

struct PayloadAnchor: Codable {
    var blockPath: String
    var blockKind: String
    var quote: String
}

struct ReviewPayload: Codable {
    var meta: PayloadMeta
    var summary: PayloadSummary
    var comments: [PayloadComment]
}

// MARK: - Hashing helpers

enum Hash {
    /// Hex sha256 of a string (UTF-8).
    static func sha256(_ s: String) -> String {
        let data = Data(s.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Normalize block content for stable hashing:
    /// lowercase, collapse whitespace runs to single space, trim.
    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let collapsed = lowered.unicodeScalars.reduce(into: "") { acc, scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !acc.hasSuffix(" ") { acc.append(" ") }
            } else {
                acc.unicodeScalars.append(scalar)
            }
        }
        return collapsed.trimmingCharacters(in: .whitespaces)
    }

    static func blockHash(_ s: String) -> String {
        sha256(normalize(s))
    }
}
