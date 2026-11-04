import SwiftUI
import UniformTypeIdentifiers

@main
struct SendItApp: App {
    var body: some Scene {
        WindowGroup {
            ServerListView()
        }
    }
}

struct ServerListView: View {
    @ObservedObject private var store = ConfigStore.shared
    @State private var editing: Server?
    @State private var importing = false
    @State private var pickedFiles: PickedFiles?
    @State private var lastPicked: PickedFiles?

    var body: some View {
        NavigationStack {
            List {
                if !store.isShared {
                    Section {
                        Label("App Group 不可用，分享扩展将看不到这里的配置。签名时请确保启用了 App Group。", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                if store.config.servers.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("添加你的 NAS").font(.headline)
                            Text("支持 WebDAV 和 SMB。每个服务器可以添加多个目的目录，之后在任意 App 的分享菜单中选择「发送到 NAS」即可上传。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("添加服务器") { editing = Server() }.buttonStyle(.borderedProminent).padding(.top, 4)
                        }
                        .padding(.vertical, 6)
                    }
                }
                ForEach(store.config.servers) { server in
                    Section {
                        Button { editing = server } label: {
                            HStack {
                                Image(systemName: server.kind == .smb ? "externaldrive.connected.to.line.below" : "globe")
                                    .font(.title3).foregroundStyle(.tint).frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.displayName).font(.headline).foregroundStyle(.primary)
                                    Text(server.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        ForEach(server.destinations) { d in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(d.displayName)
                                    Text("/" + RemotePath.normalize(d.path)).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "folder") }
                        }
                    }
                }
                .onDelete { idx in store.config.servers.remove(atOffsets: idx) }
            }
            .navigationTitle("SendIt")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = Server() } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { importing = true } label: {
                        Label("从「文件」上传…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.config.servers.allSatisfy { $0.destinations.isEmpty })
                }
            }
            .sheet(item: $editing) { server in
                ServerEditView(server: server) { saved in
                    store.upsert(saved)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    let p = PickedFiles(urls: urls)
                    lastPicked = p
                    pickedFiles = p
                }
            }
            .sheet(item: $pickedFiles, onDismiss: { lastPicked?.cleanup(); lastPicked = nil }) { picked in
                SendView(files: picked.local) { _ in pickedFiles = nil }
            }
        }
    }
}

/// Copies security-scoped picks into our temp dir so uploads can read them.
struct PickedFiles: Identifiable {
    let id = UUID()
    let dir: URL
    let local: [URL]

    init(urls: [URL]) {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pick-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [URL] = []
        for u in urls {
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            let dst = dir.appendingPathComponent(u.lastPathComponent)
            if (try? FileManager.default.copyItem(at: u, to: dst)) != nil { out.append(dst) }
        }
        local = out
    }

    func cleanup() { try? FileManager.default.removeItem(at: dir) }
}
