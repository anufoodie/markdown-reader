import SwiftUI
import AppKit

// MARK: - Enums

enum ViewMode: String, CaseIterable {
    case split = "Split"
    case editor = "Editor"
    case preview = "Preview"

    var icon: String {
        switch self {
        case .split: return "rectangle.split.2x1"
        case .editor: return "square.and.pencil"
        case .preview: return "eye"
        }
    }
}

enum MarginWidth: String, CaseIterable {
    case wide = "Wide"
    case mid = "Mid"

    var icon: String {
        switch self {
        case .wide: return "arrow.right.and.line.vertical.and.arrow.left"
        case .mid: return "arrow.left.and.line.vertical.and.arrow.right"
        }
    }

    var maxWidth: String {
        switch self {
        case .wide: return "80%"
        case .mid: return "780px"
        }
    }

    var padding: String {
        switch self {
        case .wide: return "40px 32px 80px"
        case .mid: return "56px 52px 100px"
        }
    }
}

enum AppTheme: String, CaseIterable {
    case system = "Auto"
    case light = "Light"
    case dark = "Dark"
    case sepia = "Sepia"

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        case .sepia: return "book"
        }
    }
}

enum SidebarTab: String, CaseIterable {
    case toc = "Contents"
    case files = "Files"
    case remote = "Remote"
}

// MARK: - File Tab

struct FileTab: Identifiable, Equatable {
    let id = UUID()
    let url: URL?
    let name: String
    var content: String
    var isModified: Bool = false
    var isRemote: Bool = false

    static func == (lhs: FileTab, rhs: FileTab) -> Bool { lhs.id == rhs.id }
}

// MARK: - Content View

struct ContentView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL? = nil

    @State private var viewMode: ViewMode = .preview
    @State private var marginWidth: MarginWidth = .wide
    @State private var theme: AppTheme = .system
    @State private var fontSize: Int = 16
    @State private var showSidebar: Bool = false
    @State private var sidebarTab: SidebarTab = .toc
    @State private var sidebarWidth: CGFloat = 260
    @State private var drawerWidth: CGFloat = 320
    @StateObject private var webViewRef = WebViewRef()
    @StateObject private var fileBrowser = FileBrowserModel()
    @StateObject private var sshBrowser = SSHBrowserModel()
    @StateObject private var reviewStore = ReviewStore()
    @StateObject private var reviewController = ReviewController()

    // Tabs: nil activeTabId means the original document tab is active
    @State private var fileTabs: [FileTab] = []
    @State private var activeTabId: UUID? = nil

    // Find bar
    @State private var showFindBar: Bool = false
    @State private var findText: String = ""
    @State private var findCurrent: Int = 0
    @State private var findTotal: Int = 0
    @FocusState private var findFieldFocused: Bool

    // Quick open
    @State private var showQuickOpen: Bool = false
    @State private var quickOpenText: String = ""

    private var activeContent: String {
        if let tabId = activeTabId, let tab = fileTabs.first(where: { $0.id == tabId }) {
            return tab.content
        }
        return document.text
    }

    private var activeURL: URL? {
        if let tabId = activeTabId, let tab = fileTabs.first(where: { $0.id == tabId }) {
            return tab.url
        }
        return fileURL
    }

    private var activeContentBinding: Binding<String> {
        if let tabId = activeTabId {
            return Binding(
                get: { fileTabs.first(where: { $0.id == tabId })?.content ?? "" },
                set: { newValue in
                    if let idx = fileTabs.firstIndex(where: { $0.id == tabId }) {
                        fileTabs[idx].content = newValue
                        fileTabs[idx].isModified = true
                    }
                }
            )
        }
        return $document.text
    }

    private var documentName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    private var tocEntries: [(level: Int, text: String, index: Int)] {
        MarkdownParser.extractTOC(from: activeContent)
    }

    private var wordCount: Int { MarkdownParser.wordCount(activeContent) }

    private var readingTime: String {
        let mins = max(1, wordCount / 200)
        return mins == 1 ? "1 min" : "\(mins) min"
    }

    private var quickOpenResults: [MarkdownFile] {
        let pool = fileBrowser.files
        if quickOpenText.isEmpty { return Array(pool.prefix(20)) }
        return pool.filter {
            $0.name.localizedCaseInsensitiveContains(quickOpenText) ||
            $0.relativeFolder.localizedCaseInsensitiveContains(quickOpenText)
        }.prefix(20).map { $0 }
    }

    var body: some View {
        ZStack {
            mainContent
            if showQuickOpen { quickOpenPanel }
            if let flash = reviewController.flash { flashToast(flash) }
            if reviewController.showCheatsheet {
                HotkeyCheatsheet {
                    reviewController.showCheatsheet = false
                }
            }
        }
        .sheet(isPresented: $reviewController.showDraftPayload) {
            DraftPayloadSheet(
                initialMarkdown: reviewController.draftPayloadMarkdown,
                jsonPreview: reviewController.draftPayloadJSON,
                summaryLine: reviewController.draftPayloadSummary,
                onCopyAndFinish: { _ in
                    reviewStore.finishCurrentRound()
                    reviewController.showDraftPayload = false
                    reviewController.showFlash("Review finished · payload copied")
                },
                onCopyKeepOpen: { _ in
                    reviewController.showFlash("Copied to clipboard")
                },
                onCancel: {
                    reviewController.showDraftPayload = false
                }
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() } }) {
                    Label("Sidebar", systemImage: "sidebar.left")
                }
                .help("Toggle sidebar (⌘⇧T)")
            }

            ToolbarItemGroup(placement: .principal) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            ToolbarItemGroup(placement: .automatic) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        reviewController.reviewMode.toggle()
                    }
                }) {
                    Label(
                        reviewController.reviewMode ? "Review: On" : "Review",
                        systemImage: reviewController.reviewMode
                            ? "bubble.left.and.bubble.right.fill"
                            : "bubble.left.and.bubble.right"
                    )
                }
                .help("Toggle Review Mode (⌘⇧R)")
                .foregroundColor(reviewController.reviewMode ? .accentColor : .primary)

                Button(action: {
                    marginWidth = marginWidth == .wide ? .mid : .wide
                }) {
                    Label(
                        marginWidth == .wide ? "Focused" : "Wide",
                        systemImage: marginWidth == .wide
                            ? "arrow.left.and.line.vertical.and.arrow.right"
                            : "arrow.right.and.line.vertical.and.arrow.left"
                    )
                }
                .help("Toggle reading width (\(marginWidth.rawValue))")

                Divider()

                Button(action: collapseAll) {
                    Label("Collapse All", systemImage: "chevron.down.square")
                }
                .help("Collapse all (⌘⇧[)")

                Button(action: expandAll) {
                    Label("Expand All", systemImage: "chevron.up.square")
                }
                .help("Expand all (⌘⇧])")

                Divider()

                Menu {
                    ForEach(AppTheme.allCases, id: \.self) { t in
                        Button(action: { theme = t }) {
                            Label(t.rawValue, systemImage: t.icon)
                        }
                    }
                } label: {
                    Label("Theme", systemImage: theme.icon)
                }
                .help("Color theme")

                Button(action: decreaseFontSize) {
                    Label("Smaller", systemImage: "textformat.size.smaller")
                }
                .help("Decrease font (⌘-)")

                Button(action: increaseFontSize) {
                    Label("Larger", systemImage: "textformat.size.larger")
                }
                .help("Increase font (⌘+)")

                Divider()

                Button(action: shareAsHTML) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Export as HTML")
            }
        }
        .background(WindowAccessor { window in
            reviewController.bindWindow(window)
        })
        .onAppear {
            wireReviewController()
            rebindReviewStore()
        }
        .onDisappear {
            reviewController.removeMonitor()
        }
        .onChange(of: activeURL) { _ in rebindReviewStore() }
        .onChange(of: reviewController.reviewMode) { on in
            if on {
                // Re-extract blocks + reattach comments against the current doc
                // state when entering Review Mode. Keystroke-level content drift
                // inside the editor is intentionally ignored until this moment.
                rebindReviewStore()
                reviewController.installMonitorIfNeeded()
                reviewController.showDrawer = true
            } else {
                reviewController.removeMonitor()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleReviewMode)) { _ in
            guard isKeyWindow() else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                reviewController.reviewMode.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleReviewDrawer)) { _ in
            guard isKeyWindow() else { return }
            if reviewController.reviewMode {
                withAnimation { reviewController.showDrawer.toggle() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .finishReview)) { _ in
            guard isKeyWindow() else { return }
            if reviewController.reviewMode { finishReview() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditor)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                switch viewMode {
                case .split: viewMode = .preview
                case .preview: viewMode = .editor
                case .editor: viewMode = .split
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTOC)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInDocument)) { _ in
            guard isKeyWindow() else { return }
            if viewMode == .editor { viewMode = .preview }
            if showFindBar {
                // Already open → focus the field (common case: ⌘F after clicking away)
                findFieldFocused = true
                return
            }
            withAnimation { showFindBar = true }
            // Defer focus until the view is installed in the window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                findFieldFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickOpen)) { _ in
            showQuickOpen.toggle()
            if showQuickOpen { quickOpenText = "" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collapseAll)) { _ in collapseAll() }
        .onReceive(NotificationCenter.default.publisher(for: .expandAll)) { _ in expandAll() }
        .onReceive(NotificationCenter.default.publisher(for: .fontSizeUp)) { _ in increaseFontSize() }
        .onReceive(NotificationCenter.default.publisher(for: .fontSizeDown)) { _ in decreaseFontSize() }
        .onChange(of: fileBrowser.requestedFile) { file in
            guard let file else { return }
            openFileAsTab(url: file.url, name: file.name)
            fileBrowser.requestedFile = nil
        }
        .onChange(of: sshBrowser.requestedPreview) { preview in
            guard let preview else { return }
            openFileAsTab(url: nil, name: preview.name, content: preview.content, isRemote: true)
            sshBrowser.requestedPreview = nil
        }
    }

    // MARK: - Main layout

    private var mainContent: some View {
        VStack(spacing: 0) {
            if !fileTabs.isEmpty { tabBar }
            HStack(spacing: 0) {
                if showSidebar {
                    sidebarPanel.frame(width: sidebarWidth)
                    sidebarDivider
                }
                GeometryReader { geo in mainArea(geo: geo) }
            }
            statusBar
        }
    }

    private var sidebarDivider: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                sidebarWidth = min(500, max(180, sidebarWidth + value.translation.width))
            })
            .overlay(Divider())
    }

    private func mainArea(geo: GeometryProxy) -> some View {
        let drawerVisible = reviewController.reviewMode && reviewController.showDrawer
        let drawerW: CGFloat = drawerVisible ? drawerWidth : 0
        let mainW = max(200, geo.size.width - drawerW - (drawerVisible ? 5 : 0))
        return HStack(spacing: 0) {
            HStack(spacing: 0) {
                if viewMode != .preview {
                    editorPanel.frame(width: viewMode == .split ? mainW / 2 : mainW)
                }
                if viewMode == .split { Divider() }
                if viewMode != .editor {
                    previewArea
                        .frame(width: viewMode == .split ? mainW / 2 : mainW)
                }
            }
            .frame(width: mainW)
            if drawerVisible {
                drawerDivider
                ReviewDrawer(
                    store: reviewStore,
                    controller: reviewController,
                    onEditComment: { c in
                        withAnimation(.easeInOut(duration: 0.18)) {
                            reviewController.pendingAnchor = c.anchor
                            reviewController.pendingAnchorIsHeading = c.anchor.blockKind == .heading
                            reviewController.pendingSuggestFocused = c.suggest != nil
                            reviewController.pendingSeverity = nil
                            reviewController.editingComment = c
                            reviewController.showCommentEditor = true
                        }
                    },
                    onJumpToComment: { c in
                        reviewStore.selectedCommentId = c.id
                        scrollToSelectedComment()
                    },
                    onFinishReview: { finishReview() },
                    onSaveComment: { note, suggest, rationale, severity, subtreeScoped in
                        guard let anchor = reviewController.pendingAnchor else { return }
                        if let existing = reviewController.editingComment {
                            reviewStore.updateComment(existing.id) { c in
                                c.note = note
                                c.suggest = suggest
                                c.rationale = rationale
                                c.severity = severity
                                c.subtreeScoped = subtreeScoped
                            }
                        } else {
                            reviewStore.addComment(
                                anchor: anchor,
                                note: note,
                                suggest: suggest,
                                rationale: rationale,
                                severity: severity,
                                subtreeScoped: subtreeScoped
                            )
                        }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            reviewController.showCommentEditor = false
                            reviewController.pendingAnchor = nil
                            reviewController.editingComment = nil
                            reviewController.pendingSeverity = nil
                        }
                    }
                )
                .frame(width: reviewController.showCommentEditor
                       ? max(drawerWidth, 360) : drawerWidth)
            }
        }
    }

    private var drawerDivider: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                drawerWidth = min(480, max(240, drawerWidth - value.translation.width))
            })
            .overlay(Divider())
    }

    private var previewArea: some View {
        VStack(spacing: 0) {
            MarkdownWebView(
                markdown: activeContent,
                marginWidth: marginWidth,
                theme: theme,
                fontSize: fontSize,
                webViewRef: webViewRef,
                fileURL: activeURL,
                onWikilinkTapped: resolveWikilink,
                onBlockClicked: handleBlockClick,
                reviewMode: reviewController.reviewMode,
                focusedBlockIndex: reviewStore.focusedBlockIndex,
                commentedBlocks: commentedBlockIndices()
            )
            if showFindBar { findBar }
        }
    }

    private func commentedBlockIndices() -> Set<Int> {
        guard let s = reviewStore.sidecar else { return [] }
        let blocks = reviewStore.blocks
        var result: Set<Int> = []
        for c in s.comments {
            if let b = blocks.first(where: {
                $0.path == c.anchor.blockPath
                    && Hash.blockHash($0.content) == c.anchor.contentHash
            }) {
                result.insert(b.globalIndex)
            }
        }
        return result
    }

    private func handleBlockClick(_ payload: BlockClickPayload) {
        guard reviewController.reviewMode else { return }
        reviewStore.focusedBlockIndex = payload.blockId
        guard reviewStore.blocks.indices.contains(payload.blockId) else { return }
        let block = reviewStore.blocks[payload.blockId]
        var anchor = ReviewAnchor.make(for: block, allBlocks: reviewStore.blocks)
        if let text = payload.selectionText, !text.isEmpty {
            // Keep anchor.quote as the block prefix (needed for fuzzy reattach).
            // The selected text lives in anchor.range.text and is shown first in
            // all display paths via effectiveQuote.
            anchor.range = ReviewRange(text: text,
                                        offsetInBlock: payload.selectionOffset ?? 0)
        }
        openCommentEditor(anchor: anchor,
                          isHeading: block.kind == .heading,
                          withSuggest: reviewController.pendingSuggestFocused)
    }

    private func openCommentEditor(anchor: ReviewAnchor,
                                   isHeading: Bool,
                                   withSuggest: Bool) {
        withAnimation(.easeInOut(duration: 0.18)) {
            reviewController.pendingAnchor = anchor
            reviewController.pendingAnchorIsHeading = isHeading
            reviewController.pendingSuggestFocused = withSuggest
            reviewController.editingComment = nil
            reviewController.showDrawer = true
            reviewController.showCommentEditor = true
        }
    }

    private func openCommentEditorForFocusedBlock(withSuggest: Bool) {
        guard let block = reviewStore.focusedBlock else {
            reviewController.showFlash("Click a block to comment on it")
            return
        }
        // Set the intent on the controller; handleBlockClick reads it
        // when the JS callback returns.
        reviewController.pendingSuggestFocused = withSuggest
        // Route through JS so any active text selection becomes the range.
        webViewRef.commentOnCurrentSelection(fallbackBlock: block.globalIndex)
    }

    // MARK: - Subviews

    private var editorPanel: some View {
        TextEditor(text: activeContentBinding)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
    }

    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            Picker("", selection: $sidebarTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            switch sidebarTab {
            case .toc:    tocContent
            case .files:  FileBrowserView(model: fileBrowser)
            case .remote: SSHBrowserView(model: sshBrowser)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private var tocContent: some View {
        Group {
            if tocEntries.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No headings")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(tocEntries.enumerated()), id: \.offset) { _, entry in
                            Button(action: { scrollToHeading(entry.index) }) {
                                Text(entry.text)
                                    .font(.system(size: tocFontSize(entry.level),
                                                  weight: entry.level <= 2 ? .medium : .regular))
                                    .foregroundColor(entry.level == 1 ? .primary : .secondary)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, CGFloat((entry.level - 1) * 12) + 12)
                                    .padding(.trailing, 12)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if reviewController.reviewMode {
                reviewStatusSegments
            } else {
                Text("\(wordCount.formatted()) words")
                Text("·").foregroundColor(.quaternaryLabel)
                Text("\(readingTime) read")
            }
            Spacer()
            Text("\(fontSize)px").monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
    }

    @ViewBuilder
    private var reviewStatusSegments: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundColor(.accentColor)
            Text("Review Mode").foregroundColor(.accentColor).fontWeight(.medium)
            Text("·").foregroundColor(.quaternaryLabel)
            if let s = reviewStore.sidecar {
                Text("round \(s.round)")
                Text("·").foregroundColor(.quaternaryLabel)
                let total = s.comments.count
                let open = reviewStore.unresolvedCount
                Text("\(total - open)/\(total) resolved")
                if reviewStore.orphanCount > 0 {
                    Text("·").foregroundColor(.quaternaryLabel)
                    Text("\(reviewStore.orphanCount) orphan\(reviewStore.orphanCount == 1 ? "" : "s")")
                        .foregroundColor(.orange)
                }
                Text("·").foregroundColor(.quaternaryLabel)
                Text(s.reviewId).font(.system(size: 10, design: .monospaced))
            } else {
                Text("(unsaved file — save to start review)")
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Find Bar

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("Find in document…", text: $findText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($findFieldFocused)
                .onSubmit {
                    webViewRef.findNext { r in findCurrent = r.current; findTotal = r.total }
                }
                .onChange(of: findText) { text in
                    webViewRef.find(text) { r in findCurrent = r.current; findTotal = r.total }
                }
            if !findText.isEmpty {
                if findTotal == 0 {
                    Text("No results")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                } else {
                    Text("\(findCurrent) of \(findTotal)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Button(action: {
                    webViewRef.findPrevious { r in findCurrent = r.current; findTotal = r.total }
                }) {
                    Image(systemName: "chevron.up").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Previous match (⇧Enter)")
                Button(action: {
                    webViewRef.findNext { r in findCurrent = r.current; findTotal = r.total }
                }) {
                    Image(systemName: "chevron.down").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Next match (Enter)")
            }
            Spacer()
            Button(action: dismissFindBar) {
                Image(systemName: "xmark").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
        .onExitCommand { dismissFindBar() }
    }

    private func dismissFindBar() {
        withAnimation { showFindBar = false }
        findText = ""
        findCurrent = 0
        findTotal = 0
        webViewRef.clearFind()
    }

    // MARK: - Quick Open

    private var quickOpenPanel: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 80)
            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    TextField("Open file…", text: $quickOpenText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                    if !quickOpenText.isEmpty {
                        Button(action: { quickOpenText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                if quickOpenResults.isEmpty {
                    Text("No matching files")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(quickOpenResults) { file in
                                Button(action: {
                                    openFileAsTab(url: file.url, name: file.name)
                                    showQuickOpen = false
                                    quickOpenText = ""
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(file.name)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.primary)
                                            if !file.relativeFolder.isEmpty {
                                                Text(file.relativeFolder)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Text(file.modifiedString)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
            .frame(width: 520)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.15))
        .onTapGesture { showQuickOpen = false; quickOpenText = "" }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            documentTabView
            ForEach(fileTabs) { tab in
                fileTabView(tab)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        .overlay(Divider(), alignment: .bottom)
    }

    private var documentTabView: some View {
        let isActive = activeTabId == nil
        return HStack(spacing: 5) {
            Image(systemName: "doc.text")
                .font(.system(size: 9))
                .foregroundColor(isActive ? .accentColor : .secondary)
            Text(documentName)
                .font(.system(size: 11, weight: isActive ? .medium : .regular))
                .foregroundColor(isActive ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .overlay(Rectangle().fill(isActive ? Color.accentColor : .clear).frame(height: 2), alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture { switchToDocumentTab() }
    }

    private func fileTabView(_ tab: FileTab) -> some View {
        let isActive = activeTabId == tab.id
        let tabId = tab.id
        return HStack(spacing: 0) {
            // Label area — switches to this tab
            HStack(spacing: 5) {
                Image(systemName: tab.isRemote ? "server.rack" : "doc.text")
                    .font(.system(size: 9))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                Text(tab.name)
                    .font(.system(size: 11, weight: isActive ? .medium : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)
                    .lineLimit(1)
                if tab.isModified {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 32)
            .contentShape(Rectangle())
            .onTapGesture { switchToTab(tabId) }
            // Close button — separate hit target
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 32)
                .contentShape(Rectangle())
                .onTapGesture { closeTab(tabId) }
        }
        .padding(.trailing, 2)
        .background(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .overlay(Rectangle().fill(isActive ? Color.accentColor : .clear).frame(height: 2), alignment: .bottom)
    }

    // MARK: - Tab Management

    private func openFileAsTab(url: URL?, name: String, content: String? = nil, isRemote: Bool = false) {
        // If this file is already open, switch to it (compare by resolved path)
        if let url {
            let resolvedPath = url.standardizedFileURL.path
            // Also skip if it's the same file as the original document
            if let docPath = fileURL?.standardizedFileURL.path, docPath == resolvedPath {
                switchToDocumentTab()
                return
            }
            if let existing = fileTabs.first(where: { $0.url?.standardizedFileURL.path == resolvedPath }) {
                activeTabId = existing.id
                return
            }
        }

        // Load content from disk if not provided
        let text: String
        if let content {
            text = content
        } else if let url, let loaded = try? String(contentsOf: url, encoding: .utf8) {
            text = loaded
        } else {
            return
        }

        let tab = FileTab(url: url, name: name, content: text, isRemote: isRemote)
        fileTabs.append(tab)
        activeTabId = tab.id
        if viewMode == .editor { viewMode = .split }
    }

    private func switchToDocumentTab() {
        saveCurrentTabIfNeeded()
        activeTabId = nil
    }

    private func switchToTab(_ id: UUID) {
        saveCurrentTabIfNeeded()
        activeTabId = id
    }

    private func closeTab(_ id: UUID) {
        guard let idx = fileTabs.firstIndex(where: { $0.id == id }) else { return }
        // Save if modified
        if fileTabs[idx].isModified, let url = fileTabs[idx].url, !fileTabs[idx].isRemote {
            try? fileTabs[idx].content.write(to: url, atomically: true, encoding: .utf8)
        }
        let wasActive = activeTabId == id
        fileTabs.remove(at: idx)
        if wasActive {
            // Switch to the next tab, previous tab, or document tab
            if !fileTabs.isEmpty {
                let newIdx = min(idx, fileTabs.count - 1)
                activeTabId = fileTabs[newIdx].id
            } else {
                activeTabId = nil
            }
        }
    }

    private func saveCurrentTabIfNeeded() {
        guard let tabId = activeTabId,
              let idx = fileTabs.firstIndex(where: { $0.id == tabId }),
              fileTabs[idx].isModified,
              let url = fileTabs[idx].url,
              !fileTabs[idx].isRemote else { return }
        try? fileTabs[idx].content.write(to: url, atomically: true, encoding: .utf8)
        fileTabs[idx].isModified = false
    }

    // MARK: - Helpers

    private func tocFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 13
        case 2: return 12.5
        default: return 11.5
        }
    }

    private func scrollToHeading(_ index: Int) {
        webViewRef.webView.evaluateJavaScript("scrollToHeading(\(index))")
    }

    private func collapseAll() {
        webViewRef.webView.evaluateJavaScript("collapseAll()")
    }

    private func expandAll() {
        webViewRef.webView.evaluateJavaScript("expandAll()")
    }

    private func increaseFontSize() { fontSize = min(24, fontSize + 1) }
    private func decreaseFontSize() { fontSize = max(10, fontSize - 1) }

    private func resolveWikilink(_ target: String) {
        // 1. Search relative to the current document and active tab
        let searchDirs: [URL] = [
            fileURL?.deletingLastPathComponent(),
            activeURL?.deletingLastPathComponent()
        ].compactMap { $0 }

        let candidates = ["\(target).md", "\(target).markdown", target]
        for dir in searchDirs {
            for candidate in candidates {
                let url = dir.appendingPathComponent(candidate)
                if FileManager.default.fileExists(atPath: url.path) {
                    openFileAsTab(url: url, name: url.lastPathComponent)
                    return
                }
            }
        }

        // 2. Fall back to file browser index
        let norm = target.lowercased()
        if let match = fileBrowser.files.first(where: {
            $0.name.lowercased() == norm + ".md" ||
            $0.name.lowercased() == norm + ".markdown" ||
            $0.name.lowercased() == norm
        }) {
            openFileAsTab(url: match.url, name: match.name)
        }
    }

    // MARK: - Review Mode wiring

    private func isKeyWindow() -> Bool {
        guard let own = reviewController.hostingWindow else {
            // Fallback: if we haven't resolved our window yet, only the first
            // subscriber should act. This is a best-effort heuristic.
            return NSApp.keyWindow != nil
        }
        return own === NSApp.keyWindow
    }

    private func wireReviewController() {
        reviewController.onCommentFocused = { withSuggest in
            openCommentEditorForFocusedBlock(withSuggest: withSuggest)
        }
        reviewController.onApproveSubtree = {
            guard let block = reviewStore.focusedBlock else {
                reviewController.showFlash("Focus a heading to approve its subtree")
                return
            }
            guard block.kind == .heading else {
                reviewController.showFlash("Approve only applies to headings")
                return
            }
            let anchor = ReviewAnchor.make(for: block, allBlocks: reviewStore.blocks)
            reviewStore.approveSubtree(at: anchor)
            reviewController.showFlash("Subtree approved")
        }
        reviewController.onResolveSelected = {
            if let id = reviewStore.selectedCommentId {
                reviewStore.toggleResolved(id)
            } else if let first = reviewStore.orderedComments().first(where: { !$0.resolved }) {
                reviewStore.toggleResolved(first.id)
            } else {
                reviewController.showFlash("No comment to resolve")
            }
        }
        reviewController.onSelectNextComment = { unresolvedOnly in
            reviewStore.selectNextComment(unresolvedOnly: unresolvedOnly)
            scrollToSelectedComment()
        }
        reviewController.onSelectPrevComment = { unresolvedOnly in
            reviewStore.selectPrevComment(unresolvedOnly: unresolvedOnly)
            scrollToSelectedComment()
        }
        reviewController.onJumpTop = {
            webViewRef.webView.evaluateJavaScript("window.scrollTo({top:0,behavior:'smooth'})")
        }
        reviewController.onJumpBottom = {
            webViewRef.webView.evaluateJavaScript("window.scrollTo({top:document.body.scrollHeight,behavior:'smooth'})")
        }
        reviewController.onFinishReview = { finishReview() }
        reviewController.onMoveBlockFocus = { delta in
            let count = reviewStore.blocks.count
            guard count > 0 else { return }
            var next = reviewStore.focusedBlockIndex + delta
            if reviewStore.focusedBlockIndex < 0 { next = (delta > 0 ? 0 : count - 1) }
            next = max(0, min(count - 1, next))
            reviewStore.focusedBlockIndex = next
            webViewRef.focusBlock(next)
        }
    }

    private func rebindReviewStore() {
        reviewStore.bind(docURL: activeURL, content: activeContent)
    }

    private func scrollToSelectedComment() {
        guard let id = reviewStore.selectedCommentId,
              let c = reviewStore.sidecar?.comments.first(where: { $0.id == id }) else { return }
        if let b = reviewStore.blocks.first(where: {
            $0.path == c.anchor.blockPath && Hash.blockHash($0.content) == c.anchor.contentHash
        }) {
            reviewStore.focusedBlockIndex = b.globalIndex
            webViewRef.focusBlock(b.globalIndex)
        }
    }

    private func finishReview() {
        guard let s = reviewStore.sidecar else {
            reviewController.showFlash("Save the file first to finish a review")
            return
        }
        let payload = PayloadRenderer.build(
            sidecar: s,
            docHash: reviewStore.docHash,
            docPath: s.docPath
        )
        reviewController.draftPayloadMarkdown = PayloadRenderer.renderMarkdown(payload)
        reviewController.draftPayloadJSON = PayloadRenderer.renderJSON(payload)
        let total = payload.summary.total
        let open = payload.summary.unresolved
        let round = payload.meta.round
        reviewController.draftPayloadSummary =
            "\(total) comment\(total == 1 ? "" : "s") · \(open) unresolved · round \(round) · \(payload.meta.reviewId)"
        reviewController.showDraftPayload = true
    }

    // MARK: - Flash toast

    private func flashToast(_ msg: String) -> some View {
        VStack {
            Spacer()
            Text(msg)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.75))
                )
                .padding(.bottom, 40)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func shareAsHTML() {
        let html = MarkdownHTMLRenderer.renderFullPage(
            markdown: activeContent, marginWidth: marginWidth, theme: theme, fontSize: fontSize)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export").appendingPathExtension("html")
        try? html.write(to: tempURL, atomically: true, encoding: .utf8)
        guard let window = NSApp.keyWindow else { return }
        let picker = NSSharingServicePicker(items: [tempURL])
        picker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
    }
}

// MARK: - Color extension

extension Color {
    static var quaternaryLabel: Color { Color(nsColor: .quaternaryLabelColor) }
}
