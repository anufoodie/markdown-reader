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
    @State private var previewFile: MarkdownFile? = nil
    @State private var previewText: String? = nil
    @State private var webViewRef = WebViewRef()
    @StateObject private var fileBrowser = FileBrowserModel()
    @StateObject private var sshBrowser = SSHBrowserModel()

    // Find bar
    @State private var showFindBar: Bool = false
    @State private var findText: String = ""
    @State private var findMatchFound: Bool = true

    // Quick open
    @State private var showQuickOpen: Bool = false
    @State private var quickOpenText: String = ""

    private var tocEntries: [(level: Int, text: String, index: Int)] {
        MarkdownParser.extractTOC(from: document.text)
    }

    private var wordCount: Int { MarkdownParser.wordCount(document.text) }

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
            if viewMode == .editor { viewMode = .preview }
            withAnimation { showFindBar.toggle() }
            if !showFindBar { webViewRef.find("") }
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
            guard let file else {
                previewFile = nil; previewText = nil; return
            }
            if let content = try? String(contentsOf: file.url, encoding: .utf8) {
                previewFile = file
                previewText = content
                if viewMode == .editor { viewMode = .split }
            }
        }
        .onChange(of: sshBrowser.requestedPreview) { preview in
            guard let preview else { return }
            previewText = preview.content
            let name = preview.name
            previewFile = MarkdownFile(name: name, path: "remote://\(name)",
                                       folder: "", modified: Date())
            if viewMode == .editor { viewMode = .split }
        }
    }

    // MARK: - Main layout

    private var mainContent: some View {
        VStack(spacing: 0) {
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
        HStack(spacing: 0) {
            if viewMode != .preview {
                editorPanel.frame(width: viewMode == .split ? geo.size.width / 2 : geo.size.width)
            }
            if viewMode == .split { Divider() }
            if viewMode != .editor {
                previewArea
                    .frame(width: viewMode == .split ? geo.size.width / 2 : geo.size.width)
            }
        }
    }

    private var previewArea: some View {
        let activeURL: URL? = previewFile?.url ?? fileURL
        return VStack(spacing: 0) {
            if let file = previewFile { previewBanner(file) }
            MarkdownWebView(
                markdown: previewText ?? document.text,
                marginWidth: marginWidth,
                theme: theme,
                fontSize: fontSize,
                webViewRef: webViewRef,
                fileURL: activeURL,
                onWikilinkTapped: resolveWikilink
            )
            if showFindBar { findBar }
        }
    }

    // MARK: - Subviews

    private func previewBanner(_ file: MarkdownFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: file.path.hasPrefix("remote://") ? "server.rack" : "doc.text")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(file.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            if !file.relativeFolder.isEmpty {
                Text("·").foregroundColor(.secondary)
                Text(file.relativeFolder)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            if !file.path.hasPrefix("remote://") {
                Button("Open to Edit") { FileBrowserModel.openAsDocument(file.url) }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
            }
            Button(action: clearPreview) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Return to current document")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }

    private func clearPreview() {
        previewFile = nil
        previewText = nil
        fileBrowser.requestedFile = nil
        sshBrowser.requestedPreview = nil
    }

    private var editorPanel: some View {
        TextEditor(text: $document.text)
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
        HStack(spacing: 16) {
            Text("\(wordCount.formatted()) words")
            Text("·").foregroundColor(.quaternaryLabel)
            Text("\(readingTime) read")
            Spacer()
            Text("\(fontSize)px").monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
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
                .onSubmit { webViewRef.findNext(findText) }
                .onChange(of: findText) { text in
                    webViewRef.find(text) { found in findMatchFound = found }
                }
            if !findText.isEmpty {
                if !findMatchFound {
                    Text("Not found")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                Button(action: { webViewRef.findPrevious(findText) }) {
                    Image(systemName: "chevron.up").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Previous match")
                Button(action: { webViewRef.findNext(findText) }) {
                    Image(systemName: "chevron.down").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Next match")
            }
            Spacer()
            Button(action: dismissFindBar) {
                Image(systemName: "xmark").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Close find bar (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func dismissFindBar() {
        withAnimation { showFindBar = false }
        findText = ""
        webViewRef.find("")
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
                                    fileBrowser.openFile(file)
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

    // MARK: - Helpers

    private func tocFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 13
        case 2: return 12.5
        default: return 11.5
        }
    }

    private func scrollToHeading(_ index: Int) {
        webViewRef.webView?.evaluateJavaScript("scrollToHeading(\(index))")
    }

    private func collapseAll() {
        webViewRef.webView?.evaluateJavaScript("collapseAll()")
    }

    private func expandAll() {
        webViewRef.webView?.evaluateJavaScript("expandAll()")
    }

    private func increaseFontSize() { fontSize = min(24, fontSize + 1) }
    private func decreaseFontSize() { fontSize = max(10, fontSize - 1) }

    private func resolveWikilink(_ target: String) {
        // 1. Search relative to the current document
        let searchDirs: [URL] = [
            fileURL?.deletingLastPathComponent(),
            previewFile.flatMap { URL(fileURLWithPath: $0.path).deletingLastPathComponent() }
        ].compactMap { $0 }

        let candidates = ["\(target).md", "\(target).markdown", target]
        for dir in searchDirs {
            for candidate in candidates {
                let url = dir.appendingPathComponent(candidate)
                if FileManager.default.fileExists(atPath: url.path),
                   let content = try? String(contentsOf: url, encoding: .utf8) {
                    previewFile = MarkdownFile(name: url.lastPathComponent, path: url.path,
                                               folder: dir.path, modified: Date())
                    previewText = content
                    if viewMode == .editor { viewMode = .split }
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
            fileBrowser.openFile(match)
        }
    }

    private func shareAsHTML() {
        let html = MarkdownHTMLRenderer.renderFullPage(
            markdown: document.text, marginWidth: marginWidth, theme: theme, fontSize: fontSize)
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
