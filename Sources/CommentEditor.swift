import SwiftUI

/// In-drawer comment editor panel. Designed for widths of 320–480pt.
/// Replaces the earlier modal sheet — the doc stays visible while writing.
struct CommentEditorPanel: View {
    let anchor: ReviewAnchor
    let existingComment: ReviewComment?
    let offerSubtreeScope: Bool
    var initialSuggestFocused: Bool = false
    var initialSeverity: Severity? = nil

    var onSave: (_ note: String, _ suggest: String?, _ rationale: String?,
                 _ severity: Severity?, _ subtreeScoped: Bool) -> Void
    var onCancel: () -> Void

    @State private var note: String = ""
    @State private var suggest: String = ""
    @State private var rationale: String = ""
    @State private var severity: Severity?
    @State private var subtreeScoped: Bool = false
    @State private var showSuggest: Bool = false
    @FocusState private var noteFocused: Bool
    @FocusState private var suggestFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    anchorPreview
                    severityPicker
                    noteField
                    suggestionField
                }
                .padding(12)
            }
            Divider()
            footer
        }
        .onAppear { hydrate() }
    }

    private func hydrate() {
        if let c = existingComment {
            note = c.note
            suggest = c.suggest ?? ""
            rationale = c.rationale ?? ""
            severity = c.severity
            subtreeScoped = c.subtreeScoped
            showSuggest = c.suggest != nil
        } else {
            if let s = initialSeverity { severity = s }
            if offerSubtreeScope { subtreeScoped = true }
        }
        if initialSuggestFocused {
            showSuggest = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                suggestFocused = true
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                noteFocused = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: existingComment == nil ? "plus.bubble" : "pencil")
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            Text(existingComment == nil ? "New Comment" : "Edit Comment")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Anchor preview

    private var anchorPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(anchor.blockKind.rawValue)
                    .font(.system(size: 9, weight: .semibold).smallCaps())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.12))
                    )
                Text(anchor.blockPath.isEmpty ? "(preamble)" : anchor.blockPath)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            if offerSubtreeScope {
                Toggle(isOn: $subtreeScoped) {
                    Text("Apply to whole subtree")
                        .font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            Text(anchor.effectiveQuote)
                .font(.system(size: 11))
                .italic()
                .foregroundColor(.primary.opacity(0.75))
                .lineLimit(4)
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    Rectangle().fill(Color.accentColor).frame(width: 2),
                    alignment: .leading
                )
        }
    }

    // MARK: - Severity

    private var severityPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Severity")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                severityChip(nil, label: "none", color: .secondary)
                ForEach(Severity.allCases, id: \.self) { sev in
                    severityChip(sev, label: sev.label, color: color(for: sev))
                }
                Spacer()
            }
        }
    }

    private func color(for sev: Severity) -> Color {
        switch sev {
        case .blocker:  return .red
        case .question: return .blue
        case .nitpick:  return .gray
        }
    }

    private func severityChip(_ sev: Severity?, label: String, color: Color) -> some View {
        let selected = severity == sev
        return Button(action: { severity = sev }) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? color : color.opacity(0.12))
                )
                .foregroundColor(selected ? .white : color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Note

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Note")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            TextEditor(text: $note)
                .font(.system(size: 12))
                .focused($noteFocused)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 70, idealHeight: 100)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - Suggest + Why

    @ViewBuilder
    private var suggestionField: some View {
        if showSuggest {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Suggestion")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        withAnimation {
                            showSuggest = false
                            suggest = ""
                            rationale = ""
                        }
                    }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                TextEditor(text: $suggest)
                    .font(.system(size: 12))
                    .focused($suggestFocused)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.accentColor.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                            )
                    )
                Text("Rationale (why?)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                TextField("One sentence on why…", text: $rationale)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }
        } else {
            Button(action: {
                withAnimation { showSuggest = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    suggestFocused = true
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add suggestion")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Text("⌘↵ save · Esc cancel")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Spacer()
            Button("Cancel", action: onCancel)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            Button(action: save) {
                Text(existingComment == nil ? "Add" : "Save")
                    .fontWeight(.semibold)
            }
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return }
        let sg = suggest.trimmingCharacters(in: .whitespacesAndNewlines)
        let rat = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            trimmedNote,
            sg.isEmpty ? nil : sg,
            rat.isEmpty ? nil : rat,
            severity,
            subtreeScoped && offerSubtreeScope
        )
    }
}
