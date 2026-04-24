import SwiftUI
import WebKit

struct FindResult {
    var current: Int = 0
    var total: Int = 0
}

// MARK: - WebViewRef (owns the WKWebView and all content loading)

/// Click payload from the web view. May include a text selection within the block.
struct BlockClickPayload {
    var blockId: Int
    var selectionText: String?
    var selectionOffset: Int?
}

class WebViewRef: ObservableObject {
    let webView: WKWebView
    var onWikilinkTapped: (String) -> Void = { _ in }
    var onBlockClicked: (BlockClickPayload) -> Void = { _ in }
    private let coordinator: WebViewCoordinator
    private var lastMarkdown: String = ""
    private var lastTheme: AppTheme = .system
    private var lastFontSize: Int = 16
    private var lastMarginWidth: MarginWidth = .wide
    private var lastFileURL: URL? = nil
    private var lastReviewMode: Bool = false
    private var lastFocusedBlock: Int = -1
    private var lastCommentedBlocks: Set<Int> = []

    init() {
        let coord = WebViewCoordinator()
        self.coordinator = coord
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.userContentController.add(coord, name: "wikilink")
        config.userContentController.add(coord, name: "blockClick")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        self.webView = wv
        coord.ref = self
    }

    func loadIfNeeded(markdown: String, marginWidth: MarginWidth, theme: AppTheme,
                      fontSize: Int, fileURL: URL?) {
        guard markdown != lastMarkdown || theme != lastTheme ||
              fontSize != lastFontSize || marginWidth != lastMarginWidth ||
              fileURL != lastFileURL else { return }
        lastMarkdown = markdown
        lastTheme = theme
        lastFontSize = fontSize
        lastMarginWidth = marginWidth
        lastFileURL = fileURL
        // Reset review state; will be re-applied after load.
        lastFocusedBlock = -1
        lastCommentedBlocks = []
        let html = MarkdownHTMLRenderer.renderFullPage(
            markdown: markdown, marginWidth: marginWidth, theme: theme, fontSize: fontSize)
        let base = fileURL?.deletingLastPathComponent()
        webView.loadHTMLString(html, baseURL: base)
    }

    // MARK: - Review Mode controls

    func setReviewMode(_ on: Bool) {
        guard on != lastReviewMode else { return }
        lastReviewMode = on
        webView.evaluateJavaScript("setReviewMode(\(on ? "true" : "false"))")
    }

    func focusBlock(_ index: Int, scroll: Bool = true) {
        guard index != lastFocusedBlock else { return }
        lastFocusedBlock = index
        webView.evaluateJavaScript("focusBlock(\(index), \(scroll ? "true" : "false"))")
    }

    /// Trigger "comment on current selection" via JS — posts a blockClick
    /// message with whatever is selected, or falls back to the passed block index.
    func commentOnCurrentSelection(fallbackBlock: Int) {
        webView.evaluateJavaScript("commentOnCurrentSelection(\(fallbackBlock))")
    }

    func setCommentedBlocks(_ blocks: Set<Int>) {
        guard blocks != lastCommentedBlocks else { return }
        lastCommentedBlocks = blocks
        let arr = blocks.sorted().map(String.init).joined(separator: ",")
        webView.evaluateJavaScript("setCommentedBlocks([\(arr)])")
    }

    // MARK: - Find

    private func parseFindResult(_ result: Any?) -> FindResult {
        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = dict["current"] as? Int,
              let total = dict["total"] as? Int else {
            return FindResult()
        }
        return FindResult(current: current, total: total)
    }

    func find(_ text: String, completion: ((FindResult) -> Void)? = nil) {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "'", with: "\\'")
                         .replacingOccurrences(of: "\n", with: "\\n")
        let js = text.isEmpty ? "clearFindHighlights(); JSON.stringify({current:0,total:0})"
                              : "findAndHighlight('\(escaped)')"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            completion?(self?.parseFindResult(result) ?? FindResult())
        }
    }

    func findNext(completion: ((FindResult) -> Void)? = nil) {
        webView.evaluateJavaScript("findNavigate(true)") { [weak self] result, _ in
            completion?(self?.parseFindResult(result) ?? FindResult())
        }
    }

    func findPrevious(completion: ((FindResult) -> Void)? = nil) {
        webView.evaluateJavaScript("findNavigate(false)") { [weak self] result, _ in
            completion?(self?.parseFindResult(result) ?? FindResult())
        }
    }

    func clearFind() {
        webView.evaluateJavaScript("clearFindHighlights()")
    }
}

// MARK: - Wikilink Coordinator

class WebViewCoordinator: NSObject, WKScriptMessageHandler {
    weak var ref: WebViewRef?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "wikilink", let target = message.body as? String {
            DispatchQueue.main.async { [weak self] in self?.ref?.onWikilinkTapped(target) }
        } else if message.name == "blockClick" {
            var payload: BlockClickPayload?
            // New JSON form: {"blockId": N, "text"?: "…", "offset"?: M}
            if let jsonStr = message.body as? String,
               let data = jsonStr.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let idx = (dict["blockId"] as? Int) ?? (dict["blockId"] as? NSNumber)?.intValue {
                let text = dict["text"] as? String
                let offset = (dict["offset"] as? Int) ?? (dict["offset"] as? NSNumber)?.intValue
                payload = BlockClickPayload(blockId: idx,
                                            selectionText: text?.isEmpty == false ? text : nil,
                                            selectionOffset: offset)
            } else if let n = message.body as? Int {
                // Legacy form (shouldn't occur with current JS, kept defensive)
                payload = BlockClickPayload(blockId: n, selectionText: nil, selectionOffset: nil)
            } else if let n = message.body as? NSNumber {
                payload = BlockClickPayload(blockId: n.intValue, selectionText: nil, selectionOffset: nil)
            }
            if let payload {
                DispatchQueue.main.async { [weak self] in
                    self?.ref?.onBlockClicked(payload)
                }
            }
        }
    }
}

// MARK: - MarkdownWebView (thin NSViewRepresentable wrapper)

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let marginWidth: MarginWidth
    let theme: AppTheme
    let fontSize: Int
    let webViewRef: WebViewRef
    var fileURL: URL? = nil
    var onWikilinkTapped: (String) -> Void = { _ in }
    var onBlockClicked: (BlockClickPayload) -> Void = { _ in }
    var reviewMode: Bool = false
    var focusedBlockIndex: Int = -1
    var commentedBlocks: Set<Int> = []

    func makeNSView(context: Context) -> WKWebView {
        webViewRef.onWikilinkTapped = onWikilinkTapped
        webViewRef.onBlockClicked = onBlockClicked
        webViewRef.loadIfNeeded(markdown: markdown, marginWidth: marginWidth,
                                theme: theme, fontSize: fontSize, fileURL: fileURL)
        applyReviewState()
        return webViewRef.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webViewRef.onWikilinkTapped = onWikilinkTapped
        webViewRef.onBlockClicked = onBlockClicked
        webViewRef.loadIfNeeded(markdown: markdown, marginWidth: marginWidth,
                                theme: theme, fontSize: fontSize, fileURL: fileURL)
        applyReviewState()
    }

    private func applyReviewState() {
        // Review-mode calls are no-ops if state hasn't changed.
        webViewRef.setReviewMode(reviewMode)
        webViewRef.setCommentedBlocks(commentedBlocks)
        if reviewMode && focusedBlockIndex >= 0 {
            webViewRef.focusBlock(focusedBlockIndex)
        }
    }
}

struct MarkdownHTMLRenderer {
    static func renderFullPage(
        markdown: String,
        marginWidth: MarginWidth = .mid,
        theme: AppTheme = .system,
        fontSize: Int = 16
    ) -> String {
        let body = MarkdownParser.toHTML(markdown)
        let themeAttr: String
        switch theme {
        case .system: themeAttr = ""
        case .light: themeAttr = " data-theme=\"light\""
        case .dark: themeAttr = " data-theme=\"dark\""
        case .sepia: themeAttr = " data-theme=\"sepia\""
        }
        return """
        <!DOCTYPE html>
        <html\(themeAttr)>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(css)
        body {
            max-width: \(marginWidth.maxWidth);
            padding: \(marginWidth.padding);
            font-size: \(fontSize)px;
        }
        </style>
        </head>
        <body>
        <div id="content">
        \(body)
        </div>
        <script>
        \(js)
        </script>
        </body>
        </html>
        """
    }

    // MARK: - CSS

    static let css = ##"""
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Source+Serif+4:ital,opsz,wght@0,8..60,400;0,8..60,600;0,8..60,700;1,8..60,400&family=JetBrains+Mono:wght@400;500&display=swap');

    /* ── Light theme (default) ── */
    :root {
        --bg: #fafaf9;
        --text: #2c2c2c;
        --text-secondary: #737373;
        --heading: #171717;
        --link: #2563eb;
        --link-hover: #1d4ed8;
        --accent: #6366f1;
        --accent-soft: rgba(99, 102, 241, 0.08);
        --code-bg: #f4f4f5;
        --code-border: #e4e4e7;
        --code-text: #3f3f46;
        --border: #e5e5e5;
        --border-light: #f0f0f0;
        --table-header-bg: #f9fafb;
        --table-stripe: #fafafa;
        --table-hover: rgba(99, 102, 241, 0.04);
        --blockquote-border: #6366f1;
        --blockquote-bg: rgba(99, 102, 241, 0.04);
        --hr-color: #e5e5e5;
        --shadow-sm: 0 1px 2px rgba(0,0,0,0.04);
        --shadow-md: 0 2px 8px rgba(0,0,0,0.06), 0 1px 2px rgba(0,0,0,0.04);
        --indicator: #a3a3a3;
        --indicator-hover: #525252;
        --selection: rgba(99, 102, 241, 0.12);
        --hl-keyword: #d73a49;
        --hl-string: #22863a;
        --hl-comment: #6a737d;
        --hl-number: #005cc5;
        --hl-func: #6f42c1;
        --hl-type: #e36209;
        --hl-attr: #005cc5;
        --check-bg: #e5e5e5;
        --check-done: #6366f1;
    }

    /* ── Dark theme ── */
    @media (prefers-color-scheme: dark) {
        :root:not([data-theme="light"]):not([data-theme="sepia"]) {
            --bg: #141414;
            --text: #d4d4d8;
            --text-secondary: #71717a;
            --heading: #fafafa;
            --link: #818cf8;
            --link-hover: #a5b4fc;
            --accent: #818cf8;
            --accent-soft: rgba(129, 140, 248, 0.1);
            --code-bg: #1e1e22;
            --code-border: #2a2a2e;
            --code-text: #a1a1aa;
            --border: #27272a;
            --border-light: #202024;
            --table-header-bg: #1a1a1e;
            --table-stripe: #18181b;
            --table-hover: rgba(129, 140, 248, 0.06);
            --blockquote-border: #818cf8;
            --blockquote-bg: rgba(129, 140, 248, 0.06);
            --hr-color: #27272a;
            --shadow-sm: 0 1px 2px rgba(0,0,0,0.2);
            --shadow-md: 0 2px 8px rgba(0,0,0,0.3), 0 1px 2px rgba(0,0,0,0.2);
            --indicator: #52525b;
            --indicator-hover: #a1a1aa;
            --selection: rgba(129, 140, 248, 0.15);
            --hl-keyword: #ff7b72;
            --hl-string: #7ee787;
            --hl-comment: #8b949e;
            --hl-number: #79c0ff;
            --hl-func: #d2a8ff;
            --hl-type: #ffa657;
            --hl-attr: #79c0ff;
            --check-bg: #3a3a3c;
            --check-done: #818cf8;
        }
    }

    /* ── Forced dark ── */
    [data-theme="dark"] {
        --bg: #141414;
        --text: #d4d4d8;
        --text-secondary: #71717a;
        --heading: #fafafa;
        --link: #818cf8;
        --link-hover: #a5b4fc;
        --accent: #818cf8;
        --accent-soft: rgba(129, 140, 248, 0.1);
        --code-bg: #1e1e22;
        --code-border: #2a2a2e;
        --code-text: #a1a1aa;
        --border: #27272a;
        --border-light: #202024;
        --table-header-bg: #1a1a1e;
        --table-stripe: #18181b;
        --table-hover: rgba(129, 140, 248, 0.06);
        --blockquote-border: #818cf8;
        --blockquote-bg: rgba(129, 140, 248, 0.06);
        --hr-color: #27272a;
        --shadow-sm: 0 1px 2px rgba(0,0,0,0.2);
        --shadow-md: 0 2px 8px rgba(0,0,0,0.3), 0 1px 2px rgba(0,0,0,0.2);
        --indicator: #52525b;
        --indicator-hover: #a1a1aa;
        --selection: rgba(129, 140, 248, 0.15);
        --hl-keyword: #ff7b72;
        --hl-string: #7ee787;
        --hl-comment: #8b949e;
        --hl-number: #79c0ff;
        --hl-func: #d2a8ff;
        --hl-type: #ffa657;
        --hl-attr: #79c0ff;
        --check-bg: #3a3a3c;
        --check-done: #818cf8;
    }

    /* ── Forced light ── */
    [data-theme="light"] {
        --bg: #fafaf9;
        --text: #2c2c2c;
        --text-secondary: #737373;
        --heading: #171717;
        --link: #2563eb;
        --link-hover: #1d4ed8;
        --accent: #6366f1;
        --code-bg: #f4f4f5;
        --code-border: #e4e4e7;
        --code-text: #3f3f46;
        --border: #e5e5e5;
        --border-light: #f0f0f0;
        --table-header-bg: #f9fafb;
        --table-stripe: #fafafa;
        --table-hover: rgba(99, 102, 241, 0.04);
        --blockquote-border: #6366f1;
        --blockquote-bg: rgba(99, 102, 241, 0.04);
        --hr-color: #e5e5e5;
        --shadow-sm: 0 1px 2px rgba(0,0,0,0.04);
        --shadow-md: 0 2px 8px rgba(0,0,0,0.06), 0 1px 2px rgba(0,0,0,0.04);
        --indicator: #a3a3a3;
        --indicator-hover: #525252;
        --selection: rgba(99, 102, 241, 0.12);
        --hl-keyword: #d73a49;
        --hl-string: #22863a;
        --hl-comment: #6a737d;
        --hl-number: #005cc5;
        --hl-func: #6f42c1;
        --hl-type: #e36209;
        --hl-attr: #005cc5;
        --check-bg: #e5e5e5;
        --check-done: #6366f1;
    }

    /* ── Sepia theme ── */
    [data-theme="sepia"] {
        --bg: #f5eed6;
        --text: #433422;
        --text-secondary: #7a6652;
        --heading: #2c1e10;
        --link: #8b5e3c;
        --link-hover: #6b3f1f;
        --accent: #9e6b4a;
        --accent-soft: rgba(158, 107, 74, 0.1);
        --code-bg: #ede5cc;
        --code-border: #ddd4b8;
        --code-text: #5c4833;
        --border: #d9cfb3;
        --border-light: #e8dfca;
        --table-header-bg: #ede5d0;
        --table-stripe: #f0e8d2;
        --table-hover: rgba(158, 107, 74, 0.06);
        --blockquote-border: #9e6b4a;
        --blockquote-bg: rgba(158, 107, 74, 0.06);
        --hr-color: #d9cfb3;
        --shadow-sm: 0 1px 2px rgba(60,40,10,0.06);
        --shadow-md: 0 2px 8px rgba(60,40,10,0.08), 0 1px 2px rgba(60,40,10,0.04);
        --indicator: #a8977a;
        --indicator-hover: #5c4833;
        --selection: rgba(158, 107, 74, 0.15);
        --hl-keyword: #9e4a1f;
        --hl-string: #5a7a2a;
        --hl-comment: #9e937a;
        --hl-number: #3a6e8c;
        --hl-func: #7b4fa0;
        --hl-type: #b06820;
        --hl-attr: #3a6e8c;
        --check-bg: #ddd4b8;
        --check-done: #9e6b4a;
    }

    /* ── Reset ── */
    * { margin: 0; padding: 0; box-sizing: border-box; }
    ::selection { background: var(--selection); }

    /* ── Body ── */
    body {
        font-family: 'Source Serif 4', Georgia, 'Times New Roman', serif;
        font-size: 16px;
        line-height: 1.8;
        color: var(--text);
        background: var(--bg);
        padding: 56px 52px 100px;
        max-width: 780px;
        margin: 0 auto;
        -webkit-font-smoothing: antialiased;
        text-rendering: optimizeLegibility;
        font-feature-settings: 'kern' 1, 'liga' 1;
    }

    #content > *:first-child { margin-top: 0 !important; }

    /* ── Headings ── */
    h1, h2, h3, h4, h5, h6 {
        font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif;
        color: var(--heading);
        font-weight: 600;
        line-height: 1.25;
        margin-top: 2.4em;
        margin-bottom: 0.65em;
        cursor: pointer;
        position: relative;
        padding-left: 26px;
        letter-spacing: -0.02em;
        transition: color 0.15s ease;
        -webkit-user-select: none;
        user-select: none;
    }

    h1:hover, h2:hover, h3:hover, h4:hover, h5:hover, h6:hover { color: var(--accent); }

    h1 {
        font-size: 2.1em; font-weight: 700; letter-spacing: -0.035em;
        padding-bottom: 0.4em; margin-bottom: 0.8em;
        border-bottom: 2px solid var(--border); margin-top: 0; line-height: 1.2;
    }
    h2 {
        font-size: 1.55em; font-weight: 650; letter-spacing: -0.025em;
        padding-bottom: 0.3em; border-bottom: 1px solid var(--border-light);
    }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1.1em; }
    h5 { font-size: 1em; }
    h6 { font-size: 0.9em; color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.04em; }

    /* ── Collapse indicator ── */
    .collapse-indicator {
        position: absolute; left: 2px; top: 50%; transform: translateY(-50%);
        font-size: 0.5em; color: var(--indicator);
        transition: transform 0.2s cubic-bezier(0.4, 0, 0.2, 1), color 0.15s ease, opacity 0.15s ease;
        width: 16px; text-align: center; line-height: 1; opacity: 0.5;
    }
    h1 .collapse-indicator { top: calc(50% - 0.2em); }
    h1:hover .collapse-indicator, h2:hover .collapse-indicator, h3:hover .collapse-indicator,
    h4:hover .collapse-indicator, h5:hover .collapse-indicator, h6:hover .collapse-indicator {
        color: var(--indicator-hover); opacity: 1;
    }
    .collapsed > .collapse-indicator { transform: translateY(-50%) rotate(-90deg); opacity: 1; }

    /* ── Paragraphs ── */
    p { margin-bottom: 1.25em; line-height: 1.8; }

    /* ── Links ── */
    a {
        color: var(--link); text-decoration: none;
        border-bottom: 1px solid rgba(37, 99, 235, 0.25);
        transition: border-color 0.15s ease, color 0.15s ease; padding-bottom: 0.5px;
    }
    a:hover { color: var(--link-hover); border-bottom-color: var(--link-hover); }

    /* ── Emphasis ── */
    strong { font-weight: 600; color: var(--heading); }
    em { font-style: italic; }

    /* ── Inline code ── */
    code {
        font-family: 'JetBrains Mono', 'SF Mono', Menlo, monospace;
        background: var(--code-bg); color: var(--code-text);
        border: 1px solid var(--code-border); padding: 2px 7px;
        border-radius: 5px; font-size: 0.82em; font-weight: 450;
    }

    /* ── Code blocks ── */
    pre {
        background: var(--code-bg); border: 1px solid var(--code-border);
        padding: 20px 24px; border-radius: 12px; overflow-x: auto;
        margin: 1.6em 0; line-height: 1.6; box-shadow: var(--shadow-sm);
    }
    pre code {
        background: none; border: none; padding: 0; border-radius: 0;
        font-size: 0.82em; font-weight: 400; color: var(--text);
    }

    /* ── Syntax highlighting ── */
    .hl-keyword { color: var(--hl-keyword); font-weight: 500; }
    .hl-string { color: var(--hl-string); }
    .hl-comment { color: var(--hl-comment); font-style: italic; }
    .hl-number { color: var(--hl-number); }
    .hl-func { color: var(--hl-func); }
    .hl-type { color: var(--hl-type); }
    .hl-attr { color: var(--hl-attr); }

    /* ── Blockquotes ── */
    blockquote {
        border-left: 3px solid var(--blockquote-border);
        background: var(--blockquote-bg);
        margin: 1.6em 0; padding: 16px 24px;
        border-radius: 0 10px 10px 0; font-style: italic;
    }
    blockquote strong { font-style: normal; }
    blockquote p:last-child { margin-bottom: 0; }

    /* ── Lists ── */
    ul, ol { margin: 0.6em 0 1.4em; padding-left: 1.6em; }
    li { margin-bottom: 0.4em; line-height: 1.75; padding-left: 0.3em; }
    li::marker { color: var(--accent); font-weight: 500; }
    ol li::marker { font-family: 'Inter', sans-serif; font-size: 0.9em; font-weight: 600; }

    /* ── Task lists ── */
    .task-item { list-style: none; margin-left: -1.3em; display: flex; align-items: baseline; gap: 8px; }
    .checkbox {
        display: inline-block; width: 16px; height: 16px; flex-shrink: 0;
        border: 2px solid var(--check-bg); border-radius: 4px;
        position: relative; top: 2px; transition: all 0.15s ease;
    }
    .checkbox.checked {
        background: var(--check-done); border-color: var(--check-done);
    }
    .checkbox.checked::after {
        content: ''; position: absolute; left: 3px; top: 0px;
        width: 5px; height: 9px;
        border: solid white; border-width: 0 2px 2px 0;
        transform: rotate(45deg);
    }
    .task-item.done { color: var(--text-secondary); text-decoration: line-through; }

    /* ── Tables ── */
    table {
        width: 100%; border-collapse: separate; border-spacing: 0;
        margin: 1.2em 0 1.6em;
        font-family: 'Inter', -apple-system, sans-serif;
        font-size: 0.875em; line-height: 1.5;
        border: 1px solid var(--border); border-radius: 12px;
        overflow: hidden; box-shadow: var(--shadow-md);
    }
    thead { background: var(--table-header-bg); }
    th {
        font-weight: 600; text-align: left; padding: 12px 20px;
        border-bottom: 2px solid var(--border); font-size: 0.85em;
        text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-secondary);
    }
    td { padding: 11px 20px; border-bottom: 1px solid var(--border-light); vertical-align: top; }
    td:first-child { font-weight: 500; color: var(--heading); }
    tr:last-child td { border-bottom: none; }
    tbody tr:nth-child(even) { background: var(--table-stripe); }
    tbody tr { transition: background-color 0.12s ease; }
    tbody tr:hover { background-color: var(--table-hover); }

    /* ── Horizontal rule ── */
    hr { border: none; height: 0; border-top: 1px solid var(--hr-color); margin: 3em auto; max-width: 120px; }

    /* ── Images ── */
    img { max-width: 100%; height: auto; border-radius: 12px; margin: 1.2em 0; box-shadow: var(--shadow-md); }

    /* ── Wikilinks ── */
    a.wikilink { color: var(--accent); border-bottom: 1px dashed var(--accent); }
    a.wikilink:hover { border-bottom-style: solid; }

    /* ── Find highlights ── */
    mark.find-hl {
        background: rgba(250, 204, 21, 0.4);
        color: inherit;
        border-radius: 2px;
        padding: 1px 0;
    }
    mark.find-hl.find-hl-active {
        background: rgba(250, 204, 21, 0.85);
        outline: 2px solid rgba(250, 204, 21, 0.9);
        outline-offset: 1px;
    }

    /* ── Misc ── */
    del { color: var(--text-secondary); text-decoration: line-through; }
    .section-hidden { display: none; }

    /* ── Review Mode ── */
    body.review-mode #content > *[data-block-id] {
        position: relative;
        transition: background 0.12s ease, box-shadow 0.12s ease;
        border-radius: 4px;
    }
    body.review-mode #content > *[data-block-id]:hover {
        background: var(--accent-soft);
        cursor: pointer;
    }
    body.review-mode #content > *[data-block-id]:hover::before {
        content: '+';
        position: absolute;
        left: -28px; top: 4px;
        font-family: 'Inter', sans-serif; font-weight: 500;
        font-size: 0.75em; color: var(--accent);
        width: 20px; height: 20px; line-height: 18px;
        text-align: center;
        border: 1px solid var(--accent);
        border-radius: 50%;
        background: var(--bg);
        opacity: 0.9;
    }
    body.review-mode #content > *[data-block-id].block-focused {
        box-shadow: inset 3px 0 0 var(--accent);
        background: var(--accent-soft);
    }
    body.review-mode #content > *[data-block-id].block-commented::after {
        content: attr(data-comment-count);
        position: absolute;
        right: -32px; top: 4px;
        font-family: 'Inter', sans-serif; font-weight: 600;
        font-size: 0.65em; color: white;
        background: var(--accent);
        min-width: 18px; height: 18px; padding: 0 5px;
        line-height: 18px; text-align: center;
        border-radius: 9px;
        box-shadow: var(--shadow-sm);
    }

    /* ── Scrollbar ── */
    ::-webkit-scrollbar { width: 5px; height: 5px; }
    ::-webkit-scrollbar-track { background: transparent; }
    ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
    ::-webkit-scrollbar-thumb:hover { background: var(--text-secondary); }

    /* ── Print ── */
    @media print {
        body { background: white; color: black; padding: 0; max-width: none; }
        .collapse-indicator { display: none; }
        .section-hidden { display: block !important; }
        h1, h2, h3, h4, h5, h6 { padding-left: 0; cursor: default; }
        table, pre { box-shadow: none; }
    }
    """##

    // MARK: - JavaScript

    static let js = ##"""
    // ── Collapsible sections ──
    //
    // Design: each heading can carry a `.collapsed` class independently.
    // Visibility is a *derived* view of the DOM, recomputed in one linear pass
    // from the current `.collapsed` flags. This keeps nesting correct even
    // after collapse → collapse-parent → expand-parent sequences, where the
    // previous implementation lost track and over-reveal content under a
    // still-collapsed inner heading.
    function setupCollapsible() {
        document.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(function(header) {
            var indicator = document.createElement('span');
            indicator.className = 'collapse-indicator';
            indicator.textContent = '\u{25BC}';
            header.prepend(indicator);
            header.addEventListener('click', function(e) {
                e.preventDefault();
                toggleSection(header);
            });
        });
    }

    function isHeading(el) {
        return el && el.matches && el.matches('h1,h2,h3,h4,h5,h6');
    }

    function setCollapsedIndicator(header, collapsed) {
        var indicator = header.querySelector('.collapse-indicator');
        if (indicator) indicator.textContent = collapsed ? '\u{25B6}' : '\u{25BC}';
    }

    /// Recompute the `section-hidden` class across the whole document from the
    /// current set of `.collapsed` headings. O(n) in top-level-children count.
    function reapplyCollapseVisibility() {
        var content = document.getElementById('content');
        if (!content) return;
        var children = content.children;
        // Stack of heading levels whose sections are currently collapsed.
        // An element is hidden iff the stack is non-empty.
        // Heading rules: a heading at level L ends any stacked level >= L.
        var stack = [];
        for (var i = 0; i < children.length; i++) {
            var el = children[i];
            if (isHeading(el)) {
                var level = parseInt(el.tagName[1]);
                // Pop headings at same-or-deeper level — they are not ancestors.
                while (stack.length && stack[stack.length - 1] >= level) {
                    stack.pop();
                }
                // The heading itself is hidden iff an ancestor is collapsed.
                setHidden(el, stack.length > 0);
                // If THIS heading is collapsed, push its level so descendants hide.
                if (el.classList.contains('collapsed')) {
                    stack.push(level);
                }
            } else {
                // Non-heading: hidden iff any ancestor heading is collapsed.
                setHidden(el, stack.length > 0);
            }
        }
    }

    function setHidden(el, hidden) {
        if (hidden) {
            if (!el.classList.contains('section-hidden')) el.classList.add('section-hidden');
        } else {
            if (el.classList.contains('section-hidden')) el.classList.remove('section-hidden');
        }
    }

    function toggleSection(header) {
        var isCollapsed = header.classList.toggle('collapsed');
        setCollapsedIndicator(header, isCollapsed);
        reapplyCollapseVisibility();
    }

    function collapseAll() {
        document.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(function(h) {
            h.classList.add('collapsed');
            setCollapsedIndicator(h, true);
        });
        reapplyCollapseVisibility();
    }

    function expandAll() {
        document.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(function(h) {
            h.classList.remove('collapsed');
            setCollapsedIndicator(h, false);
        });
        reapplyCollapseVisibility();
    }

    // ── Scroll to heading (for TOC) ──
    function scrollToHeading(index) {
        var headers = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
        if (index < headers.length) {
            var h = headers[index];
            // Expand if collapsed
            if (h.classList.contains('collapsed')) toggleSection(h);
            // Expand any collapsed parents
            var prev = h.previousElementSibling;
            while (prev) {
                if (prev.matches && prev.matches('h1,h2,h3,h4,h5,h6') && prev.classList.contains('collapsed')) {
                    if (parseInt(prev.tagName[1]) < parseInt(h.tagName[1])) {
                        toggleSection(prev);
                    }
                }
                prev = prev.previousElementSibling;
            }
            // Show if hidden
            if (h.classList.contains('section-hidden')) {
                h.classList.remove('section-hidden');
            }
            h.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    // ── Syntax highlighting ──
    var langDefs = {
        swift: {
            kw: 'import|func|var|let|if|else|for|while|return|struct|class|enum|protocol|guard|switch|case|default|self|Self|true|false|nil|try|catch|throw|throws|async|await|some|any|where|in|as|is|init|deinit|extension|typealias|static|private|public|internal|open|override|mutating|final|inout|defer|repeat|break|continue|do|super',
            types: 'String|Int|Double|Float|Bool|Array|Dictionary|Optional|Set|Result|Error|Void|Any|AnyObject'
        },
        python: {
            kw: 'import|from|def|class|if|elif|else|for|while|return|try|except|finally|with|as|in|is|not|and|or|True|False|None|pass|break|continue|yield|lambda|raise|del|global|nonlocal|assert|async|await',
            types: 'int|float|str|bool|list|dict|tuple|set|bytes|type|object'
        },
        javascript: {
            kw: 'import|export|from|function|const|let|var|if|else|for|while|do|return|try|catch|finally|throw|new|delete|typeof|instanceof|in|of|class|extends|super|this|switch|case|default|break|continue|yield|async|await|true|false|null|undefined',
            types: 'Array|Object|String|Number|Boolean|Map|Set|Promise|Symbol|BigInt'
        },
        typescript: {
            kw: 'import|export|from|function|const|let|var|if|else|for|while|do|return|try|catch|finally|throw|new|delete|typeof|instanceof|in|of|class|extends|super|this|switch|case|default|break|continue|yield|async|await|true|false|null|undefined|type|interface|enum|implements|abstract|declare|namespace|module|as|keyof|readonly',
            types: 'Array|Object|String|Number|Boolean|Map|Set|Promise|Symbol|BigInt|void|never|unknown|any'
        },
        go: {
            kw: 'package|import|func|var|const|if|else|for|range|return|switch|case|default|break|continue|go|defer|select|chan|type|struct|interface|map|make|new|append|len|cap|true|false|nil|error',
            types: 'string|int|int8|int16|int32|int64|uint|float32|float64|bool|byte|rune|error|any'
        },
        rust: {
            kw: 'use|fn|let|mut|if|else|for|while|loop|return|match|struct|enum|impl|trait|pub|mod|crate|self|Self|super|true|false|as|in|ref|move|async|await|dyn|where|type|const|static|unsafe|extern',
            types: 'i8|i16|i32|i64|u8|u16|u32|u64|f32|f64|bool|char|str|String|Vec|Option|Result|Box|Rc|Arc'
        },
        java: {
            kw: 'import|package|class|interface|extends|implements|public|private|protected|static|final|abstract|synchronized|volatile|native|transient|return|if|else|for|while|do|switch|case|default|break|continue|try|catch|finally|throw|throws|new|this|super|instanceof|true|false|null|void|enum',
            types: 'int|long|short|byte|float|double|boolean|char|String|Object|Integer|Long|Double|Float|Boolean|List|Map|Set|Array'
        },
        bash: {
            kw: 'if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|exit|echo|export|source|alias|local|read|shift|set|unset|true|false',
            types: ''
        },
        sql: {
            kw: 'SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|INDEX|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AND|OR|NOT|NULL|IS|IN|BETWEEN|LIKE|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|AS|DISTINCT|COUNT|SUM|AVG|MIN|MAX|UNION|ALL|EXISTS|CASE|WHEN|THEN|ELSE|END|PRIMARY|KEY|FOREIGN|REFERENCES|UNIQUE|DEFAULT|CHECK|CONSTRAINT',
            types: 'INT|INTEGER|VARCHAR|TEXT|BOOLEAN|DATE|TIMESTAMP|FLOAT|DECIMAL|BLOB|CHAR|BIGINT'
        },
        css: {
            kw: 'important|inherit|initial|unset|none|auto|block|inline|flex|grid|absolute|relative|fixed|sticky|solid|dotted|dashed|normal|bold|italic|nowrap|hidden|visible|scroll|center|left|right|top|bottom',
            types: ''
        },
        html: {
            kw: '',
            types: ''
        },
        json: {
            kw: 'true|false|null',
            types: ''
        },
        ruby: {
            kw: 'require|include|def|end|class|module|if|elsif|else|unless|while|until|for|do|begin|rescue|ensure|raise|return|yield|block_given|self|super|true|false|nil|and|or|not|in|then|attr_accessor|attr_reader|attr_writer|puts|print|lambda|proc',
            types: 'String|Integer|Float|Array|Hash|Symbol|Regexp|Range|NilClass|TrueClass|FalseClass'
        }
    };

    // Aliases
    langDefs['js'] = langDefs['javascript'];
    langDefs['ts'] = langDefs['typescript'];
    langDefs['sh'] = langDefs['bash'];
    langDefs['shell'] = langDefs['bash'];
    langDefs['zsh'] = langDefs['bash'];
    langDefs['py'] = langDefs['python'];
    langDefs['rb'] = langDefs['ruby'];
    langDefs['rs'] = langDefs['rust'];
    langDefs['c'] = langDefs['java'];
    langDefs['cpp'] = langDefs['java'];
    langDefs['csharp'] = langDefs['java'];
    langDefs['cs'] = langDefs['java'];
    langDefs['jsx'] = langDefs['javascript'];
    langDefs['tsx'] = langDefs['typescript'];

    function highlightCode() {
        document.querySelectorAll('pre code').forEach(function(block) {
            var cls = block.className || '';
            var lang = cls.replace('language-', '').toLowerCase();
            var def = langDefs[lang];
            if (!def) return;

            var text = block.innerHTML;
            var tokens = [];

            // Extract strings and comments first (protect them)
            // Block comments
            text = text.replace(/\/\*[\s\S]*?\*\//g, function(m) {
                tokens.push('<span class="hl-comment">' + m + '</span>');
                return '\x00' + (tokens.length - 1) + '\x00';
            });
            // Line comments (// and #)
            text = text.replace(/(\/\/.*$|#.*$)/gm, function(m) {
                // Don't match # inside HTML entities or shebangs for non-bash
                if (lang !== 'bash' && lang !== 'sh' && lang !== 'shell' && lang !== 'zsh' && lang !== 'py' && lang !== 'python' && lang !== 'ruby' && lang !== 'rb' && m.startsWith('#')) return m;
                tokens.push('<span class="hl-comment">' + m + '</span>');
                return '\x00' + (tokens.length - 1) + '\x00';
            });
            // Strings (double and single quoted)
            text = text.replace(/(&quot;[^&]*?(?:&quot;))|("(?:[^"\\]|\\.)*")|('(?:[^'\\]|\\.)*')/g, function(m) {
                tokens.push('<span class="hl-string">' + m + '</span>');
                return '\x00' + (tokens.length - 1) + '\x00';
            });
            // Template literals
            text = text.replace(/(`(?:[^`\\]|\\.)*`)/g, function(m) {
                tokens.push('<span class="hl-string">' + m + '</span>');
                return '\x00' + (tokens.length - 1) + '\x00';
            });

            // Types
            if (def.types && def.types.length > 0) {
                var typeRe = new RegExp('\\b(' + def.types + ')\\b', 'g');
                text = text.replace(typeRe, '<span class="hl-type">$1</span>');
            }

            // Keywords
            if (def.kw && def.kw.length > 0) {
                var kwFlags = (lang === 'sql') ? 'gi' : 'g';
                var kwRe = new RegExp('\\b(' + def.kw + ')\\b', kwFlags);
                text = text.replace(kwRe, '<span class="hl-keyword">$1</span>');
            }

            // Numbers
            text = text.replace(/\b(\d+\.?\d*(?:e[+-]?\d+)?)\b/gi, '<span class="hl-number">$1</span>');

            // Restore protected tokens
            text = text.replace(/\x00(\d+)\x00/g, function(_, idx) {
                return tokens[parseInt(idx)];
            });

            block.innerHTML = text;
        });
    }

    // ── Find / Highlight ──
    var _findMatches = [];
    var _findCurrent = -1;

    function findAndHighlight(text) {
        clearFindHighlights();
        if (!text) return JSON.stringify({current: 0, total: 0});
        var body = document.getElementById('content');
        var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, null);
        var textNodes = [];
        while (walker.nextNode()) textNodes.push(walker.currentNode);
        var lower = text.toLowerCase();
        textNodes.forEach(function(node) {
            var parent = node.parentNode;
            if (!parent || parent.tagName === 'SCRIPT' || parent.tagName === 'STYLE') return;
            var val = node.nodeValue;
            var idx = val.toLowerCase().indexOf(lower);
            if (idx === -1) return;
            var frag = document.createDocumentFragment();
            var pos = 0;
            while (idx !== -1) {
                if (idx > pos) frag.appendChild(document.createTextNode(val.substring(pos, idx)));
                var mark = document.createElement('mark');
                mark.className = 'find-hl';
                mark.textContent = val.substring(idx, idx + text.length);
                frag.appendChild(mark);
                pos = idx + text.length;
                idx = val.toLowerCase().indexOf(lower, pos);
            }
            if (pos < val.length) frag.appendChild(document.createTextNode(val.substring(pos)));
            parent.replaceChild(frag, node);
        });
        _findMatches = Array.from(document.querySelectorAll('mark.find-hl'));
        _findCurrent = _findMatches.length > 0 ? 0 : -1;
        if (_findCurrent >= 0) {
            _findMatches[0].classList.add('find-hl-active');
            _findMatches[0].scrollIntoView({behavior: 'smooth', block: 'center'});
        }
        return JSON.stringify({current: _findCurrent + 1, total: _findMatches.length});
    }

    function findNavigate(forward) {
        if (_findMatches.length === 0) return JSON.stringify({current: 0, total: 0});
        _findMatches[_findCurrent].classList.remove('find-hl-active');
        if (forward) {
            _findCurrent = (_findCurrent + 1) % _findMatches.length;
        } else {
            _findCurrent = (_findCurrent - 1 + _findMatches.length) % _findMatches.length;
        }
        _findMatches[_findCurrent].classList.add('find-hl-active');
        _findMatches[_findCurrent].scrollIntoView({behavior: 'smooth', block: 'center'});
        return JSON.stringify({current: _findCurrent + 1, total: _findMatches.length});
    }

    function clearFindHighlights() {
        document.querySelectorAll('mark.find-hl').forEach(function(mark) {
            var parent = mark.parentNode;
            parent.replaceChild(document.createTextNode(mark.textContent), mark);
            parent.normalize();
        });
        _findMatches = [];
        _findCurrent = -1;
    }

    // ── Review Mode ──
    var _focusedBlockIndex = -1;
    var _commentedBlocks = {};  // index → count

    function tagBlocksWithIds() {
        var content = document.getElementById('content');
        if (!content) return;
        var children = Array.from(content.children);
        for (var i = 0; i < children.length; i++) {
            children[i].setAttribute('data-block-id', String(i));
        }
    }

    function setReviewMode(on) {
        if (on) {
            document.body.classList.add('review-mode');
        } else {
            document.body.classList.remove('review-mode');
            var f = document.querySelector('#content > .block-focused');
            if (f) f.classList.remove('block-focused');
            _focusedBlockIndex = -1;
        }
    }

    function focusBlock(index, scroll) {
        var content = document.getElementById('content');
        if (!content) return;
        var all = content.querySelectorAll('[data-block-id]');
        all.forEach(function(el) { el.classList.remove('block-focused'); });
        if (index < 0 || index >= all.length) { _focusedBlockIndex = -1; return; }
        var target = all[index];
        target.classList.add('block-focused');
        _focusedBlockIndex = index;
        if (scroll) {
            var rect = target.getBoundingClientRect();
            var inView = rect.top >= 60 && rect.bottom <= window.innerHeight - 40;
            if (!inView) {
                target.scrollIntoView({behavior: 'smooth', block: 'center'});
            }
        }
    }

    function setCommentedBlocks(indexList) {
        var content = document.getElementById('content');
        if (!content) return;
        // Clear
        content.querySelectorAll('.block-commented').forEach(function(el) {
            el.classList.remove('block-commented');
            el.removeAttribute('data-comment-count');
        });
        _commentedBlocks = {};
        // Count occurrences
        for (var i = 0; i < indexList.length; i++) {
            var idx = indexList[i];
            _commentedBlocks[idx] = (_commentedBlocks[idx] || 0) + 1;
        }
        // Apply
        Object.keys(_commentedBlocks).forEach(function(idx) {
            var el = content.querySelector('[data-block-id="' + idx + '"]');
            if (el) {
                el.classList.add('block-commented');
                el.setAttribute('data-comment-count', String(_commentedBlocks[idx]));
            }
        });
    }

    function computeSelectionPayload(blockEl) {
        // Returns {text, offsetInBlock} if there's a non-collapsed selection
        // fully inside blockEl; otherwise null.
        try {
            var sel = window.getSelection();
            if (!sel || sel.isCollapsed || sel.rangeCount === 0) return null;
            var range = sel.getRangeAt(0);
            if (!blockEl.contains(range.commonAncestorContainer) &&
                range.commonAncestorContainer !== blockEl) return null;
            var text = sel.toString();
            if (!text || text.length === 0) return null;
            // Compute offset as: length of text from blockEl.start → range.startContainer+startOffset
            var pre = document.createRange();
            pre.selectNodeContents(blockEl);
            pre.setEnd(range.startContainer, range.startOffset);
            var offset = pre.toString().length;
            return { text: text, offsetInBlock: offset };
        } catch (e) { return null; }
    }

    function postBlockClick(blockId, selection) {
        if (!window.webkit || !window.webkit.messageHandlers ||
            !window.webkit.messageHandlers.blockClick) return;
        var payload;
        if (selection && selection.text) {
            payload = JSON.stringify({
                blockId: blockId,
                text: selection.text,
                offset: selection.offsetInBlock
            });
        } else {
            payload = JSON.stringify({ blockId: blockId });
        }
        window.webkit.messageHandlers.blockClick.postMessage(payload);
    }

    function setupBlockClickHandler() {
        var content = document.getElementById('content');
        if (!content) return;
        content.addEventListener('click', function(e) {
            if (!document.body.classList.contains('review-mode')) return;
            var el = e.target;
            while (el && el !== content) {
                if (el.getAttribute && el.getAttribute('data-block-id') !== null) {
                    var id = parseInt(el.getAttribute('data-block-id'), 10);
                    if (!isNaN(id)) {
                        // If a non-collapsed selection lives inside this block,
                        // treat the click as "comment on selection".
                        var sel = computeSelectionPayload(el);
                        // If selection exists but click didn't happen inside it,
                        // still prefer the selection — reviewer's signal.
                        e.preventDefault();
                        e.stopPropagation();
                        postBlockClick(id, sel);
                        return;
                    }
                }
                el = el.parentNode;
            }
        }, true);
    }

    // Explicit "comment on current selection" — called by Swift on `c` keypress
    // so keyboard-driven flow can anchor on a highlighted range.
    function commentOnCurrentSelection(fallbackBlockIndex) {
        var sel = window.getSelection();
        if (!sel || sel.isCollapsed || sel.rangeCount === 0) {
            // No selection: just open the focused block.
            if (fallbackBlockIndex >= 0) {
                postBlockClick(fallbackBlockIndex, null);
            }
            return;
        }
        // Find the block containing the selection.
        var node = sel.anchorNode;
        while (node && node !== document.body) {
            if (node.getAttribute && node.getAttribute('data-block-id') !== null) {
                var id = parseInt(node.getAttribute('data-block-id'), 10);
                if (!isNaN(id)) {
                    var payload = computeSelectionPayload(node);
                    postBlockClick(id, payload);
                    return;
                }
            }
            node = node.parentNode;
        }
        // Couldn't resolve to a block: fallback.
        if (fallbackBlockIndex >= 0) postBlockClick(fallbackBlockIndex, null);
    }

    // ── Init ──
    setupCollapsible();
    highlightCode();
    tagBlocksWithIds();
    setupBlockClickHandler();
    """##
}
