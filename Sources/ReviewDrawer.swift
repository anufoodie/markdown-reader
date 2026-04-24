import SwiftUI

// MARK: - Right-hand Comments Drawer

struct ReviewDrawer: View {
    @ObservedObject var store: ReviewStore
    @ObservedObject var controller: ReviewController
    var onEditComment: (ReviewComment) -> Void
    var onJumpToComment: (ReviewComment) -> Void
    var onFinishReview: () -> Void
    var onSaveComment: (_ note: String, _ suggest: String?, _ rationale: String?,
                        _ severity: Severity?, _ subtreeScoped: Bool) -> Void

    @State private var showResolved: Bool = false

    private var visibleComments: [ReviewComment] {
        let ordered = store.orderedComments()
        return showResolved ? ordered : ordered.filter { !$0.resolved }
    }

    var body: some View {
        if controller.showCommentEditor, let anchor = controller.pendingAnchor {
            editorView(anchor: anchor)
        } else {
            listView
        }
    }

    private func editorView(anchor: ReviewAnchor) -> some View {
        VStack(spacing: 0) {
            CommentEditorPanel(
                anchor: anchor,
                existingComment: controller.editingComment,
                offerSubtreeScope: controller.pendingAnchorIsHeading,
                initialSuggestFocused: controller.pendingSuggestFocused,
                initialSeverity: controller.pendingSeverity,
                onSave: { note, suggest, rationale, severity, subtreeScoped in
                    onSaveComment(note, suggest, rationale, severity, subtreeScoped)
                },
                onCancel: {
                    controller.showCommentEditor = false
                    controller.pendingAnchor = nil
                    controller.editingComment = nil
                    controller.pendingSeverity = nil
                }
            )
        }
        .frame(minWidth: 280, idealWidth: 360, maxWidth: 480)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var listView: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if visibleComments.isEmpty && store.orphanCount == 0 {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if store.orphanCount > 0 {
                            orphansSection
                            Divider().padding(.vertical, 4)
                        }
                        ForEach(Array(visibleComments.enumerated()), id: \.element.id) { idx, c in
                            commentCard(index: idx + 1, comment: c)
                                .onTapGesture {
                                    store.selectedCommentId = c.id
                                    onJumpToComment(c)
                                }
                                .background(
                                    store.selectedCommentId == c.id
                                        ? Color.accentColor.opacity(0.10)
                                        : Color.clear
                                )
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("Comments")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            if let s = store.sidecar {
                Text("round \(s.round)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            Button(action: { showResolved.toggle() }) {
                Image(systemName: showResolved ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(showResolved ? "Hide resolved" : "Show resolved")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            summaryChip(
                label: "\(store.sidecar?.comments.count ?? 0) total",
                color: .secondary
            )
            if store.unresolvedCount > 0 {
                summaryChip(label: "\(store.unresolvedCount) open",
                            color: .accentColor)
            }
            Spacer()
            Button(action: onFinishReview) {
                Text("Finish Review")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Finish Review — generate payload (⌘Enter)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func summaryChip(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.12))
            )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No comments yet")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("Click any block, or press `c`")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Comment card

    @ViewBuilder
    private func commentCard(index: Int, comment c: ReviewComment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("\(index).")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundColor(.secondary)
                if let sev = c.severity {
                    severityBadge(sev)
                }
                if c.subtreeScoped {
                    Text("subtree")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.purple.opacity(0.12))
                        .cornerRadius(3)
                }
                Text(c.anchor.blockPath.isEmpty ? "(preamble)" : c.anchor.blockPath)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if c.resolved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
            }
            Text(c.anchor.effectiveQuote)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .italic()
                .lineLimit(2)
                .padding(.leading, 8)
                .overlay(
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2),
                    alignment: .leading
                )
            if !c.note.isEmpty {
                Text(c.note)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(4)
            }
            if let sg = c.suggest, !sg.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text("⤳")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Text(sg)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.08))
                )
            }
            HStack(spacing: 10) {
                Button(action: { onEditComment(c) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Edit")

                Button(action: { store.toggleResolved(c.id) }) {
                    Image(systemName: c.resolved ? "arrow.uturn.backward" : "checkmark")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help(c.resolved ? "Unresolve" : "Resolve (r)")

                Button(action: { store.deleteComment(c.id) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Delete")

                Spacer()

                if let status = c.reanchored, status != .exact {
                    Text(reanchorLabel(status))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func severityBadge(_ sev: Severity) -> some View {
        let color: Color = {
            switch sev {
            case .blocker:  return .red
            case .question: return .blue
            case .nitpick:  return .gray
            }
        }()
        return Text(sev.symbol)
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundColor(.white)
            .frame(width: 14, height: 14)
            .background(Circle().fill(color))
    }

    private func reanchorLabel(_ s: ReanchorStatus) -> String {
        switch s {
        case .exact:  return "exact"
        case .moved:  return "moved"
        case .fuzzy:  return "fuzzy"
        case .orphan: return "orphan"
        }
    }

    // MARK: - Orphans

    private var orphansSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                Text("\(store.orphanCount) orphan\(store.orphanCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 8)
            ForEach(store.sidecar?.orphans ?? []) { c in
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.anchor.blockPath.isEmpty ? "(preamble)" : c.anchor.blockPath)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(c.anchor.effectiveQuote)
                        .font(.system(size: 11))
                        .italic()
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    if !c.note.isEmpty {
                        Text(c.note).font(.system(size: 11)).lineLimit(2)
                    }
                    HStack {
                        Spacer()
                        Button("Dismiss") { store.deleteComment(c.id) }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange.opacity(0.06))
                )
                .padding(.horizontal, 12)
            }
        }
    }
}
