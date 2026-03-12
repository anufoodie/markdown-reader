import SwiftUI
import AppKit

// MARK: - Models

struct PinnedFolder: Identifiable, Codable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let icon: String
    var url: URL { URL(fileURLWithPath: path) }
}

struct MarkdownFile: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let folder: String
    let modified: Date

    var url: URL { URL(fileURLWithPath: path) }

    var relativeFolder: String {
        let parent = (path as NSString).deletingLastPathComponent
        if parent == folder { return "" }
        return String(parent.dropFirst(folder.count + 1))
    }

    var modifiedString: String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: modified, relativeTo: Date())
    }
}

// MARK: - Tree node

class FileTreeNode: Identifiable, ObservableObject {
    let id: String
    let name: String
    let isFolder: Bool
    let path: String
    let file: MarkdownFile?
    @Published var children: [FileTreeNode]
    @Published var isExpanded: Bool

    init(name: String, path: String, isFolder: Bool, file: MarkdownFile? = nil, children: [FileTreeNode] = []) {
        self.id = path
        self.name = name
        self.path = path
        self.isFolder = isFolder
        self.file = file
        self.children = children
        self.isExpanded = false
    }

    var fileCount: Int {
        if !isFolder { return 1 }
        return children.reduce(0) { $0 + $1.fileCount }
    }
}

enum BrowseMode: String, CaseIterable {
    case flat = "List"
    case tree = "Tree"
}

// MARK: - Model

class FileBrowserModel: ObservableObject {
    @Published var pinnedFolders: [PinnedFolder] = []
    @Published var selectedFolder: PinnedFolder?
    @Published var files: [MarkdownFile] = []
    @Published var tree: [FileTreeNode] = []
    @Published var searchText: String = ""
    @Published var browseMode: BrowseMode = .tree
    /// Set when user clicks a file — ContentView observes this to load into preview pane
    @Published var requestedFile: MarkdownFile? = nil

    private let recentKey = "RecentFolders"

    init() {
        loadPinnedFolders()
        if let first = pinnedFolders.first {
            selectFolder(first)
        }
    }

    var filteredFiles: [MarkdownFile] {
        if searchText.isEmpty { return files }
        return files.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.relativeFolder.localizedCaseInsensitiveContains(searchText)
        }
    }

    func loadPinnedFolders() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var folders: [PinnedFolder] = []

        let candidates: [(String, String, String)] = [
            ("Desktop", "\(home)/Desktop", "menubar.dock.rectangle"),
            ("Documents", "\(home)/Documents", "doc.text"),
            ("Projects", "\(home)/Projects", "hammer"),
            ("Downloads", "\(home)/Downloads", "arrow.down.circle"),
        ]

        for (name, path, icon) in candidates {
            if FileManager.default.fileExists(atPath: path) {
                folders.append(PinnedFolder(path: path, name: name, icon: icon))
            }
        }

        if let saved = UserDefaults.standard.data(forKey: recentKey),
           let recent = try? JSONDecoder().decode([PinnedFolder].self, from: saved) {
            for r in recent {
                if !folders.contains(where: { $0.path == r.path }) &&
                   FileManager.default.fileExists(atPath: r.path) {
                    folders.append(r)
                }
            }
        }

        pinnedFolders = folders
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to browse for Markdown files"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let folder = PinnedFolder(path: url.path, name: url.lastPathComponent, icon: "folder")
        if !pinnedFolders.contains(where: { $0.path == folder.path }) {
            pinnedFolders.append(folder)
            saveRecentFolders()
        }
        selectFolder(folder)
    }

    func removeFolder(_ folder: PinnedFolder) {
        pinnedFolders.removeAll { $0.path == folder.path }
        saveRecentFolders()
        if selectedFolder?.path == folder.path {
            selectedFolder = pinnedFolders.first
            if let f = selectedFolder { scanFolder(f) }
        }
    }

    func selectFolder(_ folder: PinnedFolder) {
        selectedFolder = folder
        scanFolder(folder)
    }

    private func scanFolder(_ folder: PinnedFolder) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var found: [MarkdownFile] = []
            let extensions = Set(["md", "markdown", "mdown", "mkd"])
            let skipDirs = Set(["node_modules", ".git", ".svn", "build", "dist", ".next",
                                "__pycache__", "venv", ".venv", "Pods", ".build", ".cache"])

            guard let enumerator = fm.enumerator(
                at: folder.url,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            let maxDepth = 4

            for case let url as URL in enumerator {
                let relPath = url.path.dropFirst(folder.path.count)
                let components = relPath.split(separator: "/")
                if components.count > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }

                if skipDirs.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }

                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }

                let ext = url.pathExtension.lowercased()
                guard extensions.contains(ext) else { continue }

                found.append(MarkdownFile(
                    name: url.lastPathComponent,
                    path: url.path,
                    folder: folder.path,
                    modified: values.contentModificationDate ?? Date.distantPast
                ))
            }

            found.sort { $0.modified > $1.modified }
            let treeNodes = Self.buildTree(from: found, rootPath: folder.path)

            DispatchQueue.main.async {
                self.files = found
                self.tree = treeNodes
            }
        }
    }

    // MARK: - Tree building

    static func buildTree(from files: [MarkdownFile], rootPath: String) -> [FileTreeNode] {
        var dirMap: [String: [MarkdownFile]] = [:]
        for file in files {
            let rel = file.relativeFolder
            dirMap[rel, default: []].append(file)
        }

        return buildNodes(dirMap: dirMap, prefix: "", rootPath: rootPath)
    }

    private static func buildNodes(dirMap: [String: [MarkdownFile]], prefix: String, rootPath: String) -> [FileTreeNode] {
        var nodes: [FileTreeNode] = []

        // Find immediate subdirectories at this prefix level
        var immediateDirs = Set<String>()
        var immediateFiles: [MarkdownFile] = []

        for (dir, files) in dirMap {
            if dir == prefix {
                immediateFiles = files
                continue
            }

            let relToPrefix: String
            if prefix.isEmpty {
                relToPrefix = dir
            } else if dir.hasPrefix(prefix + "/") {
                relToPrefix = String(dir.dropFirst(prefix.count + 1))
            } else {
                continue
            }

            let firstComponent = String(relToPrefix.split(separator: "/").first ?? Substring(relToPrefix))
            immediateDirs.insert(firstComponent)
        }

        // Create folder nodes (sorted alphabetically)
        for dirName in immediateDirs.sorted() {
            let childPrefix = prefix.isEmpty ? dirName : "\(prefix)/\(dirName)"
            let fullPath = "\(rootPath)/\(childPrefix)"
            let children = buildNodes(dirMap: dirMap, prefix: childPrefix, rootPath: rootPath)
            let node = FileTreeNode(name: dirName, path: fullPath, isFolder: true, children: children)
            nodes.append(node)
        }

        // Create file nodes (sorted by modification date)
        let sortedFiles = immediateFiles.sorted { $0.modified > $1.modified }
        for file in sortedFiles {
            nodes.append(FileTreeNode(name: file.name, path: file.path, isFolder: false, file: file))
        }

        return nodes
    }

    private func saveRecentFolders() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaults = Set(["\(home)/Desktop", "\(home)/Documents", "\(home)/Projects", "\(home)/Downloads"])
        let custom = pinnedFolders.filter { !defaults.contains($0.path) }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: recentKey)
        }
    }

    // MARK: - File selection (handled by ContentView)

    func openFile(_ file: MarkdownFile) {
        requestedFile = file
    }

    /// Open a file as a proper new document (File > Open equivalent)
    static func openAsDocument(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
}

// MARK: - File Browser View

struct FileBrowserView: View {
    @ObservedObject var model: FileBrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Folder list (vertical, scrollable)
            folderList

            Divider()

            // Search + view mode
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Filter...", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !model.searchText.isEmpty {
                    Button(action: { model.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 14)

                Picker("", selection: $model.browseMode) {
                    Image(systemName: "list.bullet").tag(BrowseMode.flat)
                    Image(systemName: "folder.fill").tag(BrowseMode.tree)
                }
                .pickerStyle(.segmented)
                .frame(width: 56)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            // File list / tree
            if model.filteredFiles.isEmpty && model.searchText.isEmpty && model.files.isEmpty {
                emptyState
            } else {
                switch model.browseMode {
                case .flat:
                    flatFileList
                case .tree:
                    treeFileList
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(model.files.count) files")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }
    }

    // MARK: - Folder list (vertical, scrollable)

    private var folderList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(model.pinnedFolders) { folder in
                    folderRow(folder)
                }
                addFolderRow
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
        .frame(maxHeight: 180)
    }

    private func folderRow(_ folder: PinnedFolder) -> some View {
        let isSelected = model.selectedFolder?.path == folder.path

        return Button(action: { model.selectFolder(folder) }) {
            HStack(spacing: 8) {
                Image(systemName: folder.icon)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 16)

                Text(folder.name)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if isSelected {
                    Text("\(model.files.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let defaults = Set(["\(home)/Desktop", "\(home)/Documents", "\(home)/Projects", "\(home)/Downloads"])
            if !defaults.contains(folder.path) {
                Button("Remove Folder", role: .destructive) {
                    model.removeFolder(folder)
                }
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
            }
        }
    }

    private var addFolderRow: some View {
        Button(action: { model.addFolder() }) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text("Add Folder...")
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Flat file list

    private var flatFileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.filteredFiles) { file in
                    flatFileRow(file)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func flatFileRow(_ file: MarkdownFile) -> some View {
        Button(action: { model.openFile(file) }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    if !file.relativeFolder.isEmpty {
                        Text(file.relativeFolder)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Text(file.modifiedString)
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        }
    }

    // MARK: - Tree file list

    private var treeFileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.searchText.isEmpty {
                    ForEach(model.tree) { node in
                        TreeNodeView(node: node, depth: 0, model: model)
                    }
                } else {
                    // In search mode, fall back to flat filtered
                    ForEach(model.filteredFiles) { file in
                        flatFileRow(file)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No .md files found")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Tree Node View

struct TreeNodeView: View {
    @ObservedObject var node: FileTreeNode
    let depth: Int
    let model: FileBrowserModel

    var body: some View {
        if node.isFolder {
            folderView
        } else {
            fileView
        }
    }

    private var folderView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    node.isExpanded.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Image(systemName: node.isExpanded ? "folder.fill" : "folder")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor.opacity(0.8))

                    Text(node.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(node.fileCount)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(3)
                }
                .padding(.leading, CGFloat(depth * 16) + 10)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if node.isExpanded {
                ForEach(node.children) { child in
                    TreeNodeView(node: child, depth: depth + 1, model: model)
                }
            }
        }
    }

    private var fileView: some View {
        Button(action: {
            if let file = node.file {
                model.openFile(file)
            }
        }) {
            HStack(spacing: 4) {
                Color.clear.frame(width: 12) // align with chevron space

                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))

                Text(node.name)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let file = node.file {
                    Text(file.modifiedString)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            .padding(.leading, CGFloat(depth * 16) + 10)
            .padding(.trailing, 10)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let file = node.file {
                Button("Open to Edit") {
                    FileBrowserModel.openAsDocument(file.url)
                }
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(file.path, forType: .string)
                }
            }
        }
    }
}
