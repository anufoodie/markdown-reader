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
}

// MARK: - Content View

struct ContentView: View {
    @Binding var document: MarkdownDocument
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

    private var tocEntries: [(level: Int, text: String, index: Int)] {
        MarkdownParser.extractTOC(from: document.text)
    }

    private var wordCount: Int {
        MarkdownParser.wordCount(document.text)
    }

    private var readingTime: String {
        let mins = max(1, wordCount / 200)
        return mins == 1 ? "1 min" : "\(mins) min"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Sidebar (TOC or Files) with resizable handle
                if showSidebar {
                    sidebarPanel
                        .frame(width: sidebarWidth)

                    // Drag handle
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 5)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                NSCursor.resizeLeftRight.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let newWidth = sidebarWidth + value.translation.width
                                    sidebarWidth = min(500, max(180, newWidth))
                                }
                        )
                        .overlay(Divider())
                }

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        if viewMode != .preview {
                            editorPanel
                                .frame(width: viewMode == .split ? geo.size.width / 2 : geo.size.width)
                        }
                        if viewMode == .split {
                            Divider()
                        }
                        if viewMode != .editor {
                            VStack(spacing: 0) {
                                if let file = previewFile {
                                    previewBanner(file)
                                }
                                MarkdownWebView(
                                    markdown: previewText ?? document.text,
                                    marginWidth: marginWidth,
                                    theme: theme,
                                    fontSize: fontSize,
                                    webViewRef: webViewRef
                                )
                            }
                            .frame(width: viewMode == .split ? geo.size.width / 2 : geo.size.width)
                        }
                    }
                }
            }

            // Status bar
            statusBar
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
                        systemImage: marginWidth == .wide ? "arrow.left.and.line.vertical.and.arrow.right" : "arrow.right.and.line.vertical.and.arrow.left"
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
        .onChange(of: fileBrowser.requestedFile) { file in
            guard let file else {
                previewFile = nil
                previewText = nil
                return
            }
            if let content = try? String(contentsOf: file.url, encoding: .utf8) {
                previewFile = file
                previewText = content
                // Switch to a mode that shows the preview
                if viewMode == .editor { viewMode = .split }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collapseAll)) { _ in collapseAll() }
        .onReceive(NotificationCenter.default.publisher(for: .expandAll)) { _ in expandAll() }
        .onReceive(NotificationCenter.default.publisher(for: .fontSizeUp)) { _ in increaseFontSize() }
        .onReceive(NotificationCenter.default.publisher(for: .fontSizeDown)) { _ in decreaseFontSize() }
    }

    // MARK: - Subviews

    private func previewBanner(_ file: MarkdownFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(file.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            if !file.relativeFolder.isEmpty {
                Text("·")
                    .foregroundColor(.secondary)
                Text(file.relativeFolder)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Button("Open to Edit") {
                FileBrowserModel.openAsDocument(file.url)
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

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
            // Tab switcher
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

            // Tab content
            switch sidebarTab {
            case .toc:
                tocContent
            case .files:
                FileBrowserView(model: fileBrowser)
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
                                    .font(.system(size: tocFontSize(entry.level), weight: entry.level <= 2 ? .medium : .regular))
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
            Text("·")
                .foregroundColor(.quaternaryLabel)
            Text("\(readingTime) read")
            Spacer()
            Text("\(fontSize)px")
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
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

    private func increaseFontSize() {
        fontSize = min(24, fontSize + 1)
    }

    private func decreaseFontSize() {
        fontSize = max(10, fontSize - 1)
    }

    private func shareAsHTML() {
        let html = MarkdownHTMLRenderer.renderFullPage(markdown: document.text, marginWidth: marginWidth, theme: theme, fontSize: fontSize)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export")
            .appendingPathExtension("html")
        try? html.write(to: tempURL, atomically: true, encoding: .utf8)
        guard let window = NSApp.keyWindow else { return }
        let picker = NSSharingServicePicker(items: [tempURL])
        picker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
    }
}

// MARK: - Color extension for status bar

extension Color {
    static var quaternaryLabel: Color {
        Color(nsColor: .quaternaryLabelColor)
    }
}
