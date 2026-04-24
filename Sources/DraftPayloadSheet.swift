import SwiftUI
import AppKit

struct DraftPayloadSheet: View {
    let initialMarkdown: String
    let jsonPreview: String
    let summaryLine: String
    var onCopyAndFinish: (_ markdown: String) -> Void
    var onCopyKeepOpen: (_ markdown: String) -> Void
    var onCancel: () -> Void

    @State private var markdown: String = ""
    @State private var showJSON: Bool = false
    @State private var didCopy: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            toolbar
            Divider()
            if showJSON {
                jsonView
            } else {
                markdownEditor
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 620)
        .onAppear { markdown = initialMarkdown }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "paperplane.fill")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Draft Review Payload")
                    .font(.system(size: 14, weight: .semibold))
                Text(summaryLine)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $showJSON) {
                Text("Markdown").tag(false)
                Text("JSON").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Spacer()

            if didCopy {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            Text("Edit freely — what you see is what you copy.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Editors

    private var markdownEditor: some View {
        TextEditor(text: $markdown)
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
    }

    private var jsonView: some View {
        ScrollView {
            Text(jsonPreview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(markdown.split(whereSeparator: { $0.isNewline }).count) lines · \(markdown.count) chars")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button(action: {
                copyToClipboard()
                onCopyKeepOpen(markdown)
            }) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy payload to clipboard (keeps sheet open)")

            Button(action: {
                copyToClipboard()
                onCopyAndFinish(markdown)
            }) {
                Text("Copy & Finish")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Copy & mark this round finished (⌘Enter)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(showJSON ? jsonPreview : markdown, forType: .string)
        withAnimation { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { didCopy = false }
        }
    }
}

// MARK: - Hotkey Cheatsheet Overlay

struct HotkeyCheatsheet: View {
    var onDismiss: () -> Void

    struct Entry: Identifiable { let id = UUID(); let key: String; let desc: String }
    struct Group: Identifiable { let id = UUID(); let title: String; let entries: [Entry] }

    private let groups: [Group] = [
        Group(title: "Comment", entries: [
            Entry(key: "c", desc: "Comment on focused block"),
            Entry(key: "s", desc: "Comment + suggestion"),
            Entry(key: "a", desc: "Approve subtree"),
            Entry(key: "r", desc: "Resolve / unresolve selected"),
            Entry(key: "!  ?  .", desc: "Prefix: blocker / question / nitpick")
        ]),
        Group(title: "Navigate", entries: [
            Entry(key: "j  k", desc: "Next / previous comment"),
            Entry(key: "n  N", desc: "Next / previous unresolved"),
            Entry(key: "g  G", desc: "Top / bottom of doc"),
            Entry(key: "↑  ↓", desc: "Move block focus"),
            Entry(key: "/",   desc: "Find in document")
        ]),
        Group(title: "Mode", entries: [
            Entry(key: "⌘⇧R", desc: "Toggle Review Mode"),
            Entry(key: "⌘⇧C", desc: "Toggle Comments drawer"),
            Entry(key: "⌘Enter", desc: "Finish review → payload"),
            Entry(key: "?", desc: "This cheatsheet"),
            Entry(key: "Esc", desc: "Close / cancel")
        ])
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "command")
                        .foregroundColor(.accentColor)
                    Text("Review Mode Hotkeys")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(alignment: .top, spacing: 24) {
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(g.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.bottom, 2)
                            ForEach(g.entries) { e in
                                HStack(spacing: 10) {
                                    Text(e.key)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 64, alignment: .leading)
                                    Text(e.desc)
                                        .font(.system(size: 11))
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                }

                Text("Esc or click outside to close")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(22)
            .frame(width: 680)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
        }
    }
}
