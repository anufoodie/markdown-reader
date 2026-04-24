# Markdown Reader — v1 Specification

A native macOS markdown reader with first-class **Review Mode** for commenting on AI-generated long-form markdown and shipping structured feedback back to the parent LLM session.

---

## 1. Vision

Markdown Reader is a review surface for AI-generated long-form markdown. The headline loop:

```
agent writes .md  ──▶  you review with anchored comments  ──▶
         ▲                                                       │
         │                                                       ▼
agent revises  ◀──  parent session ingests structured payload
```

Reading comfort (themes, widths, wikilinks, TOC, SFTP) stays excellent. The differentiated capability is the loop.

---

## 2. Personas

- **Operator-Reviewer** (primary) — drives a coworker/agent/coding-agent session. Reads 2k–50k-word MD specs. Needs to comment fast at the right granularity and ship feedback in one shot.
- **Knowledge Reader** (secondary) — reads long docs (research, notes). Cares about navigation, collapse, wikilinks, themes.
- **Author-Editor** (tertiary) — light edits to own .md files. Existing editor panel.

---

## 3. Modes

| Mode | Default trigger | Writable? | Key entry |
|---|---|---|---|
| Reading | `File ▸ Open` from Finder | no (read-only MD) | current default |
| Editor | `⌘E` toggle (existing) | yes | split / editor view |
| Review | file in `~/review-inbox/`, or `⌘⇧R`, or `--review` CLI | no (MD untouched; comments in sidecar) | this spec |

`⌘⇧R` toggles Review Mode on/off. Entering Review engages the right-hand Comments drawer, block-hover affordances, and the vim-style hotkey layer.

---

## 4. Review Mode — core behaviors

### 4.1 Commentable units

Any block may receive a comment:
- Headings (H1–H6)
- Paragraphs
- List items
- Blockquotes
- Code blocks
- Table rows
- Arbitrary text ranges via selection (post-v1.1)

A **heading comment** implicitly scopes to the whole outline subtree under that heading until the next sibling-or-shallower heading.

### 4.2 Comment structure

Every comment has:

| Field | Required | Notes |
|---|---|---|
| `id` | yes | stable UUID, never reused |
| `anchor` | yes | see §5 |
| `note` | yes | free-form markdown |
| `suggest` | no | proposed replacement text |
| `rationale` | no | short "why?" attached to suggestions |
| `severity` | no | `blocker` / `question` / `nitpick` / unset |
| `resolved` | yes | bool |
| `verdict` | no | on round ≥ 2: `addressed` / `partial` / `open` |
| `relatesTo` | no | list of other comment IDs (cross-linking) |
| `createdAt` | yes | ISO-8601 |

### 4.3 Keyboard vocabulary (Review Mode only)

| Key | Action |
|---|---|
| `c` | Comment on focused block |
| `s` | Comment + suggestion (opens editor with suggestion field focused) |
| `a` | Approve subtree (heading-scoped LGTM, no text) |
| `r` | Resolve / unresolve nearest comment |
| `j` / `k` | Next / previous comment |
| `n` / `N` | Next / previous unresolved |
| `g` / `G` | Top / bottom of doc |
| `!` / `q` / `.` | Prefix-tag a new comment as blocker / question / nitpick |
| `y` / `p` | On round ≥ 2: mark selected comment verdict `addressed` / `partial` |
| `/` | Find in document |
| `?` | Open hotkey cheatsheet |
| `⌘Enter` | Finalize review (generate payload) |
| `Esc` | Cancel comment editor / close cheatsheet / exit Review Mode |
| `⌘⇧R` | Toggle Review Mode |
| `⌘⇧C` | Toggle Comments drawer |

### 4.4 Focus & block cursor

Review Mode introduces a **block cursor** — a subtle left-side rail on the currently focused block. `j`/`k` walk it through top-level blocks. Click also sets focus. `c` always acts on the focused block. The JS in the webview computes focus and keeps it in view.

### 4.5 Read-only guarantee

In Review Mode the `MarkdownDocument.text` binding is not mutated by any review action. Suggestions live as separate fields; the original file is never touched. Exiting Review Mode back to Reading/Editor restores full edit access.

---

## 5. Anchoring

Anchors must survive the agent rewriting surrounding content. Strategy:

```
Anchor := {
  blockPath:   "Auth > Tokens"            // outline path (H1 title stripped on display)
  blockIndex:  3                          // ordinal within section
  blockKind:   "paragraph" | "heading" | "list" | "blockquote" | "code" | "table" | "hr"
  contentHash: sha256(normalized text of block)
  quote:       first 140 chars of block (for block-level reattach fuzzy signal)
  contextBefore: last 80 chars of previous block
  contextAfter:  first 80 chars of next block
  range?:      { text, offsetInBlock }    // present when user selected a phrase/word
}
```

When `range` is set, the comment is about the specific phrase inside the block, not the whole block. Display and payload quote prefer `range.text`; block-level reattach keeps using `quote` as the fuzzy signal, then re-resolves `range.text` within the matched block. If the range text is no longer in the block, the range is dropped and the comment demotes to block-level (with a `reanchored=fuzzy` marker).

### 5.1 Reattachment on doc change

Given an old anchor and a new parsed doc, in order:

1. **Exact** — block at same path/index with matching `contentHash` → attached.
2. **Moved** — unique block anywhere with matching `contentHash` → attached, mark `reanchored=moved`.
3. **Fuzzy** — within the same outline subtree, highest token-overlap match against `quote` above threshold (e.g. Jaccard ≥ 0.6 and shared-prefix ≥ 20 chars) → attached, mark `reanchored=fuzzy`.
4. **Orphan** — no match → surfaced in the drawer under **Orphans** with original quote and outline path for manual re-anchor / dismiss / keep-as-note.

### 5.2 V1 pragmatism

V1 uses the existing hand-rolled parser to compute anchors (heading path + block-kind + normalized-content hash + surrounding context). The parser swap to `swift-markdown` (§12) is planned but not blocking.

---

## 6. Persistence — sidecar

Reviews are stored **centrally** in the user's app-support directory, keyed by `reviewId`:

```
~/Library/Application Support/Markdown Reader/reviews/
    <reviewId>.json
    _index.json           # docPath → reviewId, docHash → reviewId
```

The original `.md` file stays pristine and its directory is never touched. A legacy in-tree sidecar (`foo.md.review.json`) is read as a fallback and migrated to the central store on first load. `.gitignore` suggests ignoring the legacy form.

Sidecar format:

```json
{
  "schemaVersion": 1,
  "reviewId": "r_8f3k2",
  "docPath": "~/specs/auth.md",
  "round": 2,
  "rounds": [
    { "round": 1, "docHash": "9a1e…", "startedAt": "…", "finishedAt": "…",
      "commentCount": 7, "payloadSavedAt": "…" },
    { "round": 2, "docHash": "a1b2c3…", "startedAt": "…", "finishedAt": null,
      "commentCount": 5 }
  ],
  "comments": [ /* §4.2 */ ],
  "orphans":  [ /* comments that failed reattach this round */ ]
}
```

Rules:
- `reviewId` is generated once on first save and persists across rounds.
- `round` increments when the doc's content hash changes **and** a prior round has been `finishedAt`. Re-opening the same content leaves `round` unchanged.
- Sidecar writes are atomic (temp + rename).
- On load, if `schemaVersion` is ahead of the app, we refuse to modify and show a read-only banner.

---

## 7. Payload

### 7.1 JSON (machine-readable, source of truth)

```json
{
  "meta": {
    "schemaVersion": 1,
    "doc": "auth.md",
    "docPath": "/abs/path/to/auth.md",
    "docHash": "a1b2c3…",
    "reviewId": "r_8f3k2",
    "round": 2,
    "generatedAt": "2026-04-21T18:22:00Z"
  },
  "summary": {
    "total": 5, "blockers": 1, "questions": 1, "nitpicks": 2, "approvals": 1
  },
  "comments": [
    {
      "id": "c1",
      "anchor": {
        "blockPath": "Auth > Tokens",
        "blockKind": "paragraph",
        "quote": "Tokens expire after 15 min."
      },
      "severity": "blocker",
      "note": "TTL inconsistent with §5.",
      "suggest": "Tokens expire after 60 min (matches refresh TTL).",
      "rationale": "Section 5 defines refresh TTL as 60 min.",
      "resolved": false
    }
  ]
}
```

### 7.2 Markdown (clipboard-pasteable default)

```markdown
# Review — auth.md (round 2)
reviewId: r_8f3k2   docHash: a1b2c3…   5 comments (1 blocker, 1 question)

## Comment 1 — [blocker] Auth › Tokens
> Tokens expire after 15 min.

**Note:** TTL inconsistent with §5.

**Suggest:** Tokens expire after 60 min (matches refresh TTL).

**Why:** Section 5 defines refresh TTL as 60 min.

---

## Comment 2 — [question] Auth › Sessions
> Sessions persist across restarts.

**Note:** unclear — across app restarts or machine restarts?

…
```

### 7.3 Finalize flow

`⌘Enter` (or `File ▸ Finish Review`) opens a **Draft Payload** sheet:

1. Shows the rendered markdown payload in an editable text view.
2. Meta summary at top (round, counts).
3. Actions: **Copy & Finish**, **Copy (keep open)**, **Cancel**.
4. On Finish: `round` is stamped `finishedAt`, sidecar saved.
5. Optional shell-hook config: if set, runs `cmd "$PAYLOAD_PATH"` after Finish, where `$PAYLOAD_PATH` is a temp file containing the JSON.

---

## 8. UI layout

```
┌──────────────────────────────────────────────────────────────┐
│ toolbar: sidebar | view-mode | width | theme | font | share │
├──────┬──────────────────────────────────────┬───────────────┤
│ TOC  │ Preview (with block cursor)           │ Comments      │
│ Files│ sticky breadcrumb: Doc › Auth › Tokens│               │
│ Rem. │                                        │ 1. [!] §Auth  │
│      │ ## Auth                                │    TTL incon. │
│      │ ### Tokens                             │ 2. [?] §Auth  │
│      │   Tokens expire after 15 min. ◀ focus  │    unclear…   │
│      │   Refresh tokens…                      │ 3. [.] §Store │
│      │                                        │    typo       │
├──────┴──────────────────────────────────────┴───────────────┤
│ status: review · round 2 · 3/5 unresolved · 14m · r_8f3k2   │
└──────────────────────────────────────────────────────────────┘
```

- Left sidebar: existing TOC / Files / Remote tabs.
- Right drawer: new Comments panel. Visible only in Review Mode (toggleable with `⌘⇧C`). Width ~300pt, resizable.
  - The drawer switches between two modes:
    - **List**: ordered comment cards + orphans + Finish Review button.
    - **Editor**: the in-drawer comment editor. Engaged on `c`/`s` or clicking a block. The doc stays visible in the main pane while writing. Drawer auto-widens to ≥360pt.
- Status bar: in Review Mode, shows review state; otherwise existing word-count / reading-time.
- Sticky breadcrumb: top of preview pane, shows current outline path.

---

## 9. CLI & URL scheme

### 9.1 CLI flags

```
markdownreader open <path>               # reading mode
markdownreader open <path> --review      # review mode
markdownreader open <path> --review --session <external-id>
```

Implementation: Info.plist declares a URL scheme `markdownreader://`; a thin shell alias in `/usr/local/bin` turns `markdownreader open …` into the right URL.

### 9.2 URL scheme

```
markdownreader://open?path=/abs/path&mode=review
markdownreader://doc?reviewId=r_8f3k2&comment=c3     # jump to comment
```

---

## 10. Review Inbox

- Default watched folder: `~/review-inbox`
- New or modified `.md` files in the folder auto-open (or foreground if already open) in Review Mode.
- Preferences panel: inbox path, "Auto-open new files", "Watch for modifications".
- `Do Not Disturb while reviewing` (§5.3 of tier-5 notes): new inbox files queue silently during an active review, shown as a badge on the inbox menu item.

---

## 11. Hotkey overlay (`?` in Review Mode)

A semi-modal overlay lists all Review Mode hotkeys grouped by category. Dismissed with `Esc`, `?`, or click-away.

---

## 12. Parser

### 12.1 V1

Keep the existing hand-rolled parser in `Parser.swift`. Extend with:
- Stable block IDs emitted into the HTML (`data-block-id`) via post-processing pass.
- Block-kind classification for anchor fidelity.

### 12.2 V2 (planned)

Swap to `apple/swift-markdown` CommonMark AST. Benefits: robust nested lists, task lists, footnotes, HTML blocks, GFM tables. Migration: the sidecar anchor format is parser-agnostic, so existing reviews keep working; only the parser-internal ID generation changes.

---

## 13. Data flow

```
┌─────────────────┐         ┌──────────────────┐
│ MarkdownDoc     │         │ ReviewStore       │
│ .text (Binding) │◀────────│ .load(url)        │
└─────────────────┘         │ .save()           │
         │                   │ .addComment(…)    │
         ▼                   │ .resolve(id)      │
┌─────────────────┐         │ .finishRound()    │
│ Parser          │────────▶│ .anchor(from:…)   │
│ AST + blocks    │         │ .reattach(old:)   │
└─────────────────┘         └──────────┬────────┘
         │                              │
         ▼                              ▼
┌─────────────────┐           ┌───────────────────┐
│ WebView (HTML)  │◀──────────│ PayloadRenderer   │
│ review-mode CSS │           │ .json(), .md()    │
│ block cursor JS │           └───────────────────┘
└─────────────────┘                     │
         │                              ▼
         ▼                      ┌───────────────┐
┌─────────────────┐             │ Clipboard /   │
│ ContentView     │             │ Shell hook    │
│ hotkeys, drawer │             └───────────────┘
└─────────────────┘
```

---

## 14. Module map (Swift)

| File | Responsibility | v1 status |
|---|---|---|
| `App.swift` | App entry, menu commands | modified |
| `Document.swift` | FileDocument (text only, no review state) | unchanged |
| `Parser.swift` | MD → HTML + TOC + block metadata | extend |
| `WebView.swift` | WKWebView host + JS (collapse, find, review block cursor) | extend |
| `ContentView.swift` | Main layout, toolbar, hotkeys, mode state | modified |
| `FileBrowser.swift` | Files sidebar tab | unchanged |
| `SSHBrowser.swift` | Remote sidebar tab | unchanged |
| `ReviewModel.swift` | Comment, Anchor, Sidecar, Payload types | **new** |
| `ReviewStore.swift` | Sidecar I/O, anchoring, reattachment | **new** |
| `ReviewPayload.swift` | JSON + markdown payload renderers | **new** |
| `ReviewDrawer.swift` | Right-hand Comments drawer SwiftUI | **new** |
| `CommentEditor.swift` | Add/edit comment sheet | **new** |
| `ReviewAnchor.swift` | Anchor compute + fuzzy reattach | **new** |

---

## 15. Phased implementation

### Phase 1 — Review Mode MVP (this release)

1. Data model (`ReviewModel.swift`)
2. Sidecar load/save (`ReviewStore.swift`)
3. Anchor + exact reattach (`ReviewAnchor.swift`)
4. WebView block-tagging + click/hover + block cursor
5. Right drawer + comment editor
6. Hotkeys `c` / `s` / `r` / `j` / `k` / `!?.` / `⌘⇧R` / `⌘⇧C` / `⌘Enter`
7. Payload renderers (JSON + markdown)
8. Draft-payload sheet + Copy & Finish
9. Status bar review state + cheatsheet overlay

### Phase 2 — Loop accelerators

1. Review Inbox (folder watcher via FSEvents)
2. CLI + URL scheme
3. Round N+1 auto-detection on inbox arrival
4. Per-comment verdict (`y`/`p`) on round ≥ 2
5. Diff view vs prior round (side-by-side or inline)
6. TOC diff badges (changed / new / removed)
7. Shell-hook preset on Finish Review
8. Fuzzy reattach + Orphans panel

### Phase 3 — Protocol & automation

1. Per-destination payload presets (Claude Code / Codex / Cowork)
2. Agent-authored open-questions panel (reads `<!-- ask: … -->` in MD)
3. Inbound "review result" absorber
4. Cross-comment linking
5. Snippet expander for recurring critiques
6. AI-assisted comment drafting (opt-in)

### Phase 4 — Nice-to-have

1. swift-markdown parser swap
2. Focus Section mode
3. Full-screen review
4. Mermaid / LaTeX
5. Remote (SFTP) review with local sidecar cache
6. Review Sets (batch multi-file)

---

## 16. Non-goals for v1

- Multi-user real-time collaboration
- Git integration / project-wide refactors
- Cloud sync owned by this app
- General authoring beyond the existing light editor

---

## 17. Open decisions (carry into implementation)

- **Minimap / scroll ruler** — TOC diff badges may be enough; defer minimap.
- **Drag-reorder comments** — default serializes in document order.
- **Redaction** — defer to Phase 3.
- **Sidecar git-commit convention** — document in README; no enforcement.
- **Cheatsheet content** — generate from a single source of truth so menu + overlay stay in sync.

---

## 18. Compatibility

- macOS 13+ (existing).
- Pure SwiftPM-free `swiftc` build (existing). Phase 4 swift-markdown swap will introduce SwiftPM.
- Sidecar format version 1. Forward-incompat changes require `schemaVersion` bump and a migration path.
