import SwiftUI

/// Pick a destination and upload the given local files to it.
/// Used by both the share extension and the in-app file picker.
struct SendView: View {
    let files: [URL]
    var preparing: Bool = false
    var prepareError: String? = nil
    let onClose: (_ success: Bool) -> Void

    @ObservedObject private var store = ConfigStore.shared
    @StateObject private var model = UploadModel()
    @State private var target: (server: Server, destination: Destination)?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("发送到 NAS")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if model.phase == .uploading {
                            Button("停止", role: .destructive) { model.cancel() }
                        } else {
                            Button(model.phase == .done ? "完成" : "取消") { onClose(model.phase == .done) }
                        }
                    }
                }
        }
        .onAppear { store.reload() }
        .onChange(of: model.phase) { phase in
            if phase == .done {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onClose(true) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            picker
        case .uploading, .done:
            progressView
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(.orange)
                Text("上传失败").font(.headline)
                Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).textSelection(.enabled)
                HStack {
                    Button("换个位置") { model.reset() }.buttonStyle(.bordered)
                    if let t = target {
                        Button("重试") { model.start(files: files, server: t.server, destination: t.destination) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var allTargets: [(server: Server, destination: Destination)] {
        store.config.servers.flatMap { s in s.destinations.map { (s, $0) } }
    }

    private var recent: (server: Server, destination: Destination)? {
        guard let id = store.config.lastDestinationID else { return nil }
        return allTargets.first { $0.destination.id == id }
    }

    private var picker: some View {
        List {
            Section {
                if preparing {
                    HStack { ProgressView(); Text("正在读取分享内容…").foregroundStyle(.secondary) }
                } else if let err = prepareError {
                    Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                } else {
                    FileSummary(files: files)
                }
            }

            if !store.isShared {
                Section {
                    Label("App Group 不可用：分享扩展无法读取主程序中的服务器配置。请确认签名时保留了 App Group 权限。", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }

            if allTargets.isEmpty {
                Section {
                    Text("还没有配置目的目录。请打开 SendIt 主程序添加服务器和目录。").foregroundStyle(.secondary)
                }
            }

            if let r = recent {
                Section("最近使用") { row(r.server, r.destination) }
            }

            ForEach(store.config.servers.filter { !$0.destinations.isEmpty }) { server in
                Section {
                    ForEach(server.destinations) { d in row(server, d) }
                } header: {
                    Label(server.displayName, systemImage: server.kind == .smb ? "externaldrive.connected.to.line.below" : "globe")
                }
            }
        }
    }

    private func row(_ server: Server, _ dest: Destination) -> some View {
        Button {
            target = (server, dest)
            model.start(files: files, server: server, destination: dest)
        } label: {
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dest.displayName).foregroundStyle(.primary)
                    Text("\(server.displayName) › /\(RemotePath.normalize(dest.path))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "paperplane").foregroundStyle(.secondary)
            }
        }
        .disabled(files.isEmpty || preparing)
    }

    private var progressView: some View {
        VStack(spacing: 18) {
            if model.phase == .done {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text("已发送 \(model.fileCount) 个文件").font(.headline)
            } else {
                ProgressView(value: model.fraction)
                    .progressViewStyle(.linear)
                Text("\(model.fileIndex)/\(model.fileCount)  \(model.currentFile)")
                    .font(.subheadline).lineLimit(1).truncationMode(.middle)
                Text("\(ByteCountFormatter.string(fromByteCount: model.sentBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if let t = target {
                Text("→ \(t.server.displayName) /\(RemotePath.normalize(t.destination.path))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FileSummary: View {
    let files: [URL]

    var body: some View {
        let total = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(files.prefix(5), id: \.self) { f in
                Label(f.lastPathComponent, systemImage: "doc").lineLimit(1).truncationMode(.middle)
            }
            if files.count > 5 {
                Text("以及另外 \(files.count - 5) 个文件").font(.caption).foregroundStyle(.secondary)
            }
            Text("共 \(files.count) 个 · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
