import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var markdown: UTType {
        UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    }
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown, .plainText] }

    var text: String

    init(text: String = sampleMarkdown) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return .init(regularFileWithContents: data)
    }
}

let sampleMarkdown = """
# Welcome to Markdown Reader

A beautiful, native markdown viewer for macOS.

## Features

### Collapsible Sections
Click any heading to collapse or expand the content beneath it. This works with nested headings too — try clicking the headers above!

### Rich Rendering
- **Bold text** and *italic text*
- `Inline code` and code blocks
- [Links](https://example.com) and images
- Tables, blockquotes, and more

### Elegant Tables

| Feature | Status | Notes |
|---------|--------|-------|
| Headers | Done | Collapsible with smooth animation |
| Tables | Done | Alternating rows, clean borders |
| Code | Done | Syntax-aware styling |
| Lists | Done | Nested support |
| Blockquotes | Done | Styled with accent border |

## Getting Started

> **Tip:** Use `⌘E` to toggle the editor, `⌘⇧[` to collapse all sections, and `⌘⇧]` to expand them.

### Writing Markdown

Open any `.md` file or start typing in the editor panel. The preview updates in real time.

```swift
let greeting = "Hello, Markdown!"
print(greeting)
```

### Sharing

Use the **Share** button in the toolbar to export your document as HTML or share it directly.

---

*Built with SwiftUI and WebKit*
"""
