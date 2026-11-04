import SwiftUI

/// Browses directories on a server so the user can pick a destination.
struct FolderBrowserView: View {
    let server: Server
    let path: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [RemoteItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var newFolderName = ""
    @State private var showingNewFolder = false

    var body: some View {
        List {
            if loading {
                HStack { ProgressView(); Text("加载中…").foregroundStyle(.secondary) }
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else if items.filter(\.isDirectory).isEmpty {
                Text("没有子文件夹").foregroundStyle(.secondary)
            }
            ForEach(items.filter(\.isDirectory)) { item in
                NavigationLink {
                    FolderBrowserView(server: server, path: item.path, onPick: onPick)
                } label: {
                    Label(item.name, systemImage: "folder.fill")
                }
            }
        }
        .navigationTitle(path.isEmpty ? "/" : (path.split(separator: "/").last.map(String.init) ?? path))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button { showingNewFolder = true } label: { Image(systemName: "folder.badge.plus") }
                Spacer()
                Button("选择「/\(path)」") { onPick(path) }.buttonStyle(.borderedProminent)
            }
        }
        .alert("新建文件夹", isPresented: $showingNewFolder) {
            TextField("名称", text: $newFolderName)
            Button("取消", role: .cancel) { newFolderName = "" }
            Button("创建") { Task { await createFolder() } }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            let client = try RemoteClientFactory.make(for: server)
            items = try await client.list(path)
            await client.disconnect()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func createFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        newFolderName = ""
        guard !name.isEmpty else { return }
        do {
            let client = try RemoteClientFactory.make(for: server)
            try await client.connect()
            try await client.makeDirectory(RemotePath.join(path, name))
            await client.disconnect()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
