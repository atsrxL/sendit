import Foundation

struct RemoteItem: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var isDirectory: Bool
}

enum RemoteError: LocalizedError {
    case invalidConfiguration(String)
    case http(Int, String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let m): return m
        case .http(let code, let m): return "HTTP \(code): \(m)"
        case .cancelled: return "已取消"
        }
    }
}

protocol RemoteClient: AnyObject {
    func connect() async throws
    func disconnect() async
    /// Lists entries of a directory (path relative to the server root).
    func list(_ path: String) async throws -> [RemoteItem]
    func exists(_ path: String) async throws -> Bool
    func makeDirectory(_ path: String) async throws
    /// Uploads a local file. `progress` receives total bytes sent so far.
    func upload(file: URL, to path: String, progress: @escaping (Int64) -> Void) async throws
}

extension RemoteClient {
    /// Creates every missing directory along `path`.
    func makeDirectories(_ path: String) async throws {
        var current = ""
        for comp in RemotePath.normalize(path).split(separator: "/") {
            current = RemotePath.join(current, String(comp))
            if try await !exists(current) {
                try await makeDirectory(current)
            }
        }
    }

    /// Returns a file name in `dir` that does not exist yet: "a.jpg", "a (1).jpg", ...
    func availableName(for name: String, in dir: String) async throws -> String {
        if try await !exists(RemotePath.join(dir, name)) { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        for i in 1...999 {
            let candidate = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            if try await !exists(RemotePath.join(dir, candidate)) { return candidate }
        }
        return "\(UUID().uuidString)-\(name)"
    }
}

enum RemoteClientFactory {
    static func make(for server: Server) throws -> RemoteClient {
        switch server.kind {
        case .webdav: return try WebDAVClient(server: server)
        case .smb: return try SMBClient(server: server)
        }
    }
}
