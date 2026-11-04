import Foundation
import AMSMB2

final class SMBClient: RemoteClient {
    private let manager: SMB2Manager
    private let share: String
    private var connected = false

    init(server: Server) throws {
        var host = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("smb://") { host = String(host.dropFirst(6)) }
        while host.hasSuffix("/") { host.removeLast() }
        guard !host.isEmpty else { throw RemoteError.invalidConfiguration("SMB 主机不能为空") }
        var s = "smb://\(host)"
        if let port = server.port { s += ":\(port)" }
        guard let url = URL(string: s) else { throw RemoteError.invalidConfiguration("SMB 地址无效：\(s)") }
        let cred = URLCredential(user: server.username, password: server.password, persistence: .forSession)
        guard let m = SMB2Manager(url: url, domain: server.domain, credential: cred) else {
            throw RemoteError.invalidConfiguration("SMB 地址无效：\(s)")
        }
        manager = m
        share = RemotePath.normalize(server.share)
    }

    /// Lists shares on the host (used when configuring a server).
    func shares() async throws -> [String] {
        try await manager.listShares().map(\.name).filter { !$0.hasSuffix("$") }
    }

    func connect() async throws {
        guard !connected else { return }
        guard !share.isEmpty else { throw RemoteError.invalidConfiguration("请填写共享名称") }
        do {
            try await manager.connectShare(name: share)
        } catch {
            throw RemoteError.invalidConfiguration("无法连接共享「\(share)」：请检查主机、共享名称、用户名和密码。\n(\(error.localizedDescription))")
        }
        connected = true
    }

    func disconnect() async {
        guard connected else { return }
        try? await manager.disconnectShare(gracefully: true)
        connected = false
    }

    func list(_ path: String) async throws -> [RemoteItem] {
        try await connect()
        let dir = RemotePath.normalize(path)
        let entries = try await manager.contentsOfDirectory(atPath: dir.isEmpty ? "/" : dir)
        return entries.compactMap { e -> RemoteItem? in
            guard let name = e[.nameKey] as? String, name != ".", name != "..", !name.hasPrefix(".") else { return nil }
            let isDir = (e[.isDirectoryKey] as? Bool) ?? false
            return RemoteItem(name: name, path: RemotePath.join(dir, name), isDirectory: isDir)
        }
        .sorted { ($0.isDirectory ? 0 : 1, $0.name.localizedLowercase) < ($1.isDirectory ? 0 : 1, $1.name.localizedLowercase) }
    }

    func exists(_ path: String) async throws -> Bool {
        try await connect()
        do {
            _ = try await manager.attributesOfItem(atPath: RemotePath.normalize(path))
            return true
        } catch let e as POSIXError where e.code == .ENOENT || e.code == .ENOTDIR {
            return false
        } catch let e as NSError where e.domain == NSPOSIXErrorDomain && (e.code == Int(ENOENT) || e.code == Int(ENOTDIR)) {
            return false
        }
    }

    func makeDirectory(_ path: String) async throws {
        try await connect()
        try await manager.createDirectory(atPath: RemotePath.normalize(path))
    }

    func upload(file: URL, to path: String, progress: @escaping (Int64) -> Void) async throws {
        try await connect()
        try await manager.uploadItem(at: file, toPath: RemotePath.normalize(path)) { bytes in
            progress(bytes)
            return !Task.isCancelled
        }
    }
}
