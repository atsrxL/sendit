import SwiftUI

struct ServerEditView: View {
    @State var server: Server
    let onSave: (Server) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var portText = ""
    @State private var testState: TestState = .idle
    @State private var editingDestination: Destination?
    @State private var shares: [String] = []

    enum TestState: Equatable { case idle, running, ok, failed(String) }

    init(server: Server, onSave: @escaping (Server) -> Void) {
        _server = State(initialValue: server)
        _portText = State(initialValue: server.port.map(String.init) ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称（可选）", text: $server.name)
                    Picker("协议", selection: $server.kind) {
                        ForEach(ServerKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if server.kind == .webdav {
                    Section {
                        TextField("http://nas.local:5005/dav", text: $server.url)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("信任自签名证书", isOn: $server.allowUntrustedCertificate)
                    } header: { Text("WebDAV 地址") } footer: {
                        Text("填写 WebDAV 根地址（含端口与路径），目的目录相对于此地址。")
                    }
                } else {
                    Section("SMB") {
                        TextField("主机，例如 192.168.1.10", text: $server.host)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("端口（默认 445）", text: $portText).keyboardType(.numberPad)
                        HStack {
                            TextField("共享名称，例如 home", text: $server.share)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Menu {
                                if shares.isEmpty { Text("点击「测试连接」以获取共享列表") }
                                ForEach(shares, id: \.self) { s in Button(s) { server.share = s } }
                            } label: { Image(systemName: "chevron.down.circle") }
                        }
                        TextField("域（可选）", text: $server.domain)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }

                Section("账号") {
                    TextField("用户名", text: $server.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密码", text: $server.password)
                }

                Section {
                    Button { Task { await test() } } label: {
                        HStack {
                            Text("测试连接")
                            Spacer()
                            switch testState {
                            case .idle: EmptyView()
                            case .running: ProgressView()
                            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            }
                        }
                    }
                    .disabled(testState == .running)
                    if case .failed(let msg) = testState {
                        Text(msg).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                }

                Section {
                    ForEach(server.destinations) { d in
                        Button { editingDestination = d } label: {
                            VStack(alignment: .leading) {
                                Text(d.displayName).foregroundStyle(.primary)
                                Text("/" + RemotePath.normalize(d.path)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { server.destinations.remove(atOffsets: $0) }
                    .onMove { server.destinations.move(fromOffsets: $0, toOffset: $1) }
                    Button { editingDestination = Destination(name: "", path: "") } label: {
                        Label("添加目的目录", systemImage: "folder.badge.plus")
                    }
                } header: { Text("目的目录") } footer: {
                    Text("可添加多个目录，分享时直接选择要发送到哪一个。目录不存在时会自动创建。")
                }
            }
            .navigationTitle(server.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        applyPort()
                        onSave(server)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(item: $editingDestination) { d in
                DestinationEditView(server: currentServer, destination: d) { saved in
                    if let i = server.destinations.firstIndex(where: { $0.id == saved.id }) {
                        server.destinations[i] = saved
                    } else {
                        server.destinations.append(saved)
                    }
                }
            }
        }
    }

    private var currentServer: Server {
        var s = server
        s.port = Int(portText)
        return s
    }

    private var isValid: Bool {
        switch server.kind {
        case .webdav: return !server.url.trimmingCharacters(in: .whitespaces).isEmpty
        case .smb: return !server.host.trimmingCharacters(in: .whitespaces).isEmpty && !server.share.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func applyPort() {
        server.port = Int(portText.trimmingCharacters(in: .whitespaces))
    }

    private func test() async {
        applyPort()
        testState = .running
        do {
            let client = try RemoteClientFactory.make(for: server)
            if let smb = client as? SMBClient {
                shares = (try? await smb.shares()) ?? []
            }
            try await client.connect()
            _ = try await client.list("")
            await client.disconnect()
            testState = .ok
        } catch {
            testState = .failed(error.localizedDescription)
        }
    }
}

struct DestinationEditView: View {
    let server: Server
    @State var destination: Destination
    let onSave: (Destination) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var browsing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("显示名称（可选）", text: $destination.name)
                    HStack {
                        Text("/").foregroundStyle(.secondary)
                        TextField("路径，例如 Photos/iPhone", text: $destination.path)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } footer: {
                    Text(server.kind == .smb ? "相对于共享「\(server.share)」的路径，留空为共享根目录。" : "相对于 WebDAV 地址的路径，留空为根目录。")
                }
                Section {
                    Button { browsing = true } label: { Label("浏览服务器…", systemImage: "folder") }
                }
            }
            .navigationTitle("目的目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        destination.path = RemotePath.normalize(destination.path)
                        onSave(destination)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $browsing) {
                NavigationStack {
                    FolderBrowserView(server: server, path: RemotePath.normalize(destination.path)) { picked in
                        destination.path = picked
                        browsing = false
                    }
                }
            }
        }
    }
}
