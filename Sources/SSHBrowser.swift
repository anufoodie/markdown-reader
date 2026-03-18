import SwiftUI
import AppKit

// MARK: - Models

struct RemotePreview: Equatable {
    let name: String
    let content: String
}

struct SSHConnection: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var keyPath: String = "~/.ssh/id_rsa"
    var initialPath: String = "~"
}

struct RemoteFile: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let isMarkdown: Bool
}

// MARK: - Model

class SSHBrowserModel: ObservableObject {
    enum Status: Equatable {
        case disconnected, connecting, connected
        case error(String)
    }

    @Published var status: Status = .disconnected
    @Published var editingConnection = SSHConnection()
    @Published var activeConnection: SSHConnection?
    @Published var savedConnections: [SSHConnection] = []
    @Published var files: [RemoteFile] = []
    @Published var currentPath: String = "~"
    @Published var pathStack: [String] = []
    @Published var requestedPreview: RemotePreview? = nil

    private let connectionsKey = "SSHConnections"

    init() {
        loadConnections()
        if let first = savedConnections.first { editingConnection = first }
    }

    // MARK: - Persistence

    func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: connectionsKey),
              let conns = try? JSONDecoder().decode([SSHConnection].self, from: data)
        else { return }
        savedConnections = conns
    }

    private func saveConnection(_ conn: SSHConnection) {
        var conns = savedConnections
        if let idx = conns.firstIndex(where: { $0.id == conn.id }) {
            conns[idx] = conn
        } else {
            conns.insert(conn, at: 0)
        }
        savedConnections = conns
        if let data = try? JSONEncoder().encode(conns) {
            UserDefaults.standard.set(data, forKey: connectionsKey)
        }
    }

    func deleteConnection(at offsets: IndexSet) {
        savedConnections.remove(atOffsets: offsets)
        if let data = try? JSONEncoder().encode(savedConnections) {
            UserDefaults.standard.set(data, forKey: connectionsKey)
        }
    }

    // MARK: - Connection

    func connect() {
        status = .connecting
        let path = editingConnection.initialPath.isEmpty ? "~" : editingConnection.initialPath
        listDirectory(path, connection: editingConnection) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let items):
                self.activeConnection = self.editingConnection
                self.files = items
                self.status = .connected
                self.saveConnection(self.editingConnection)
            case .failure(let err):
                self.status = .error(err.localizedDescription)
            }
        }
    }

    func disconnect() {
        status = .disconnected
        activeConnection = nil
        files = []
        pathStack = []
        currentPath = "~"
    }

    // MARK: - Navigation

    func navigate(to file: RemoteFile) {
        guard file.isDirectory, let conn = activeConnection else { return }
        pathStack.append(currentPath)
        listDirectory(file.path, connection: conn) { [weak self] result in
            if case .success(let items) = result {
                self?.files = items
            }
        }
    }

    func navigateBack() {
        guard let prev = pathStack.popLast(), let conn = activeConnection else { return }
        listDirectory(prev, connection: conn) { [weak self] result in
            if case .success(let items) = result { self?.files = items }
        }
    }

    func openRemoteFile(_ file: RemoteFile) {
        guard let conn = activeConnection else { return }
        downloadFile(file, connection: conn) { [weak self] url in
            guard let url,
                  let content = try? String(contentsOf: url, encoding: .utf8)
            else { return }
            self?.requestedPreview = RemotePreview(name: file.name, content: content)
        }
    }

    // MARK: - SSH / SCP

    private func listDirectory(_ path: String,
                                connection: SSHConnection,
                                completion: @escaping (Result<[RemoteFile], Error>) -> Void) {
        let safeP = path.replacingOccurrences(of: "'", with: "'\\''")
        // cd to path, echo the resolved path, then list one-per-line with trailing / for dirs
        let cmd = "cd '\(safeP)' && pwd && ls -1Ap 2>/dev/null"
        runSSH(command: cmd, connection: connection) { output, error in
            if let error, output?.isEmpty ?? true {
                completion(.failure(error))
                return
            }
            let lines = (output ?? "")
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard let basePath = lines.first else {
                completion(.success([])); return
            }

            let mdExts = Set(["md", "markdown", "mdown", "mkd"])
            var items: [RemoteFile] = []
            for name in lines.dropFirst() {
                guard name != "./" else { continue }
                let isDir = name.hasSuffix("/")
                let cleanName = isDir ? String(name.dropLast()) : name
                guard cleanName != "." && cleanName != ".." else { continue }
                let filePath = basePath + "/" + cleanName
                let ext = (cleanName as NSString).pathExtension.lowercased()
                items.append(RemoteFile(
                    name: cleanName, path: filePath,
                    isDirectory: isDir, isMarkdown: mdExts.contains(ext)
                ))
            }
            items.sort { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            DispatchQueue.main.async { self.currentPath = basePath }
            completion(.success(items))
        }
    }

    private func downloadFile(_ file: RemoteFile,
                               connection: SSHConnection,
                               completion: @escaping (URL?) -> Void) {
        let expandedKey = (connection.keyPath as NSString).expandingTildeInPath
        let ext = (file.name as NSString).pathExtension
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "md" : ext)

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
            var args = ["-o", "BatchMode=yes",
                        "-o", "StrictHostKeyChecking=accept-new",
                        "-P", String(connection.port)]
            if !expandedKey.isEmpty { args += ["-i", expandedKey] }
            args += ["\(connection.username)@\(connection.host):\(file.path)", tmp.path]
            process.arguments = args
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    completion(process.terminationStatus == 0 ? tmp : nil)
                }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private func runSSH(command: String,
                        connection: SSHConnection,
                        completion: @escaping (String?, Error?) -> Void) {
        let expandedKey = (connection.keyPath as NSString).expandingTildeInPath
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            var args = ["-o", "BatchMode=yes",
                        "-o", "StrictHostKeyChecking=accept-new",
                        "-o", "ConnectTimeout=10",
                        "-p", String(connection.port)]
            if !expandedKey.isEmpty { args += ["-i", expandedKey] }
            args += ["\(connection.username)@\(connection.host)", command]
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)
                let err: Error? = process.terminationStatus != 0
                    ? NSError(domain: "SSH", code: Int(process.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: "SSH exited \(process.terminationStatus)"])
                    : nil
                DispatchQueue.main.async { completion(output, err) }
            } catch {
                DispatchQueue.main.async { completion(nil, error) }
            }
        }
    }
}

// MARK: - SSH Browser View

struct SSHBrowserView: View {
    @ObservedObject var model: SSHBrowserModel

    var body: some View {
        switch model.status {
        case .disconnected:
            connectionForm
        case .connecting:
            connectingView
        case .connected:
            fileBrowserView
        case .error(let msg):
            errorView(msg)
        }
    }

    // MARK: Connection form

    private var connectionForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !model.savedConnections.isEmpty {
                    Text("RECENT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    ForEach(model.savedConnections) { conn in
                        Button(action: {
                            model.editingConnection = conn
                            model.connect()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(conn.name.isEmpty ? conn.host : conn.name)
                                        .font(.system(size: 12, weight: .medium))
                                    Text("\(conn.username)@\(conn.host):\(conn.initialPath)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit") { model.editingConnection = conn }
                            Divider()
                            Button("Delete", role: .destructive) {
                                if let idx = model.savedConnections.firstIndex(where: { $0.id == conn.id }) {
                                    model.deleteConnection(at: IndexSet([idx]))
                                }
                            }
                        }
                    }
                    Divider().padding(.vertical, 6)
                }

                // New connection form
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEW CONNECTION")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))

                    formField("Name (optional)", text: $model.editingConnection.name)
                    formField("Host", text: $model.editingConnection.host)
                    formField("Username", text: $model.editingConnection.username)
                    HStack {
                        Text("Port")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .trailing)
                        TextField("22", value: $model.editingConnection.port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                    formField("SSH Key", text: $model.editingConnection.keyPath)
                    formField("Initial Path", text: $model.editingConnection.initialPath)

                    Button(action: { model.connect() }) {
                        Text("Connect")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.editingConnection.host.isEmpty || model.editingConnection.username.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private func formField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }

    // MARK: Connecting

    private var connectingView: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("Connecting…")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button("Cancel") { model.disconnect() }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: File browser

    private var fileBrowserView: some View {
        VStack(spacing: 0) {
            // Path bar
            HStack(spacing: 6) {
                if !model.pathStack.isEmpty {
                    Button(action: { model.navigateBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                Image(systemName: "server.rack")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(model.currentPath)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button(action: { model.disconnect() }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Disconnect")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if model.files.isEmpty {
                Spacer()
                Text("Empty directory")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.files) { file in
                            remoteFileRow(file)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func remoteFileRow(_ file: RemoteFile) -> some View {
        Button(action: {
            if file.isDirectory {
                model.navigate(to: file)
            } else if file.isMarkdown {
                model.openRemoteFile(file)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: file.isDirectory ? "folder" : (file.isMarkdown ? "doc.text" : "doc"))
                    .font(.system(size: 10))
                    .foregroundColor(file.isDirectory ? .accentColor.opacity(0.8) : .secondary.opacity(0.7))
                    .frame(width: 14)
                Text(file.name)
                    .font(.system(size: 12, weight: file.isDirectory ? .medium : .regular))
                    .foregroundColor(file.isMarkdown || file.isDirectory ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if file.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity((!file.isDirectory && !file.isMarkdown) ? 0.5 : 1.0)
    }

    // MARK: Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Connection failed")
                .font(.system(size: 12, weight: .medium))
            Text(message)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button("Try Again") { model.status = .disconnected }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
