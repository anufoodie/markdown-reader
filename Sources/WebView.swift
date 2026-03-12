import SwiftUI
import WebKit

class WebViewRef: ObservableObject {
    var webView: WKWebView?
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let marginWidth: MarginWidth
    let theme: AppTheme
    let fontSize: Int
    let webViewRef: WebViewRef

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webViewRef.webView = webView
        loadContent(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadContent(webView)
    }

    private func loadContent(_ webView: WKWebView) {
        let html = MarkdownHTMLRenderer.renderFullPage(
            markdown: markdown,
            marginWidth: marginWidth,
            theme: theme,
            fontSize: fontSize
        )
        webView.loadHTMLString(html, baseURL: nil)
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

    /* ── Misc ── */
    del { color: var(--text-secondary); text-decoration: line-through; }
    .section-hidden { display: none; }

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

    function toggleSection(header) {
        var level = parseInt(header.tagName[1]);
        var isCollapsed = header.classList.toggle('collapsed');
        var indicator = header.querySelector('.collapse-indicator');
        if (indicator) indicator.textContent = isCollapsed ? '\u{25B6}' : '\u{25BC}';
        var next = header.nextElementSibling;
        while (next) {
            if (next.matches && next.matches('h1,h2,h3,h4,h5,h6')) {
                if (parseInt(next.tagName[1]) <= level) break;
            }
            if (isCollapsed) {
                next.classList.add('section-hidden');
            } else {
                if (!isParentCollapsed(next, level)) {
                    next.classList.remove('section-hidden');
                    if (next.matches && next.matches('h1,h2,h3,h4,h5,h6') && next.classList.contains('collapsed')) {
                        var innerLevel = parseInt(next.tagName[1]);
                        var innerNext = next.nextElementSibling;
                        while (innerNext) {
                            if (innerNext.matches && innerNext.matches('h1,h2,h3,h4,h5,h6')) {
                                if (parseInt(innerNext.tagName[1]) <= innerLevel) break;
                            }
                            innerNext.classList.add('section-hidden');
                            innerNext = innerNext.nextElementSibling;
                        }
                    }
                }
            }
            next = next.nextElementSibling;
        }
    }

    function isParentCollapsed(element, aboveLevel) {
        var prev = element.previousElementSibling;
        while (prev) {
            if (prev.matches && prev.matches('h1,h2,h3,h4,h5,h6')) {
                var prevLevel = parseInt(prev.tagName[1]);
                if (prevLevel < aboveLevel && prev.classList.contains('collapsed')) return true;
            }
            prev = prev.previousElementSibling;
        }
        return false;
    }

    function collapseAll() {
        document.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(function(h) {
            if (!h.classList.contains('collapsed')) toggleSection(h);
        });
    }

    function expandAll() {
        document.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(function(h) {
            if (h.classList.contains('collapsed')) {
                h.classList.remove('collapsed');
                var ind = h.querySelector('.collapse-indicator');
                if (ind) ind.textContent = '\u{25BC}';
            }
        });
        document.querySelectorAll('.section-hidden').forEach(function(el) {
            el.classList.remove('section-hidden');
        });
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

    // ── Init ──
    setupCollapsible();
    highlightCode();
    """##
}
