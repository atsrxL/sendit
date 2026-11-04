import Foundation

enum ServerKind: String, Codable, CaseIterable, Identifiable {
    case webdav
    case smb

    var id: String { rawValue }
    var title: String {
        switch self {
        case .webdav: return "WebDAV"
        case .smb: return "SMB"
        }
    }
}

/// A folder on a server that files can be sent to.
struct Destination: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Path relative to the server root (WebDAV URL or SMB share), e.g. "Photos/Inbox".
    var path: String

    var displayName: String {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        let p = RemotePath.normalize(path)
        return p.isEmpty ? "/" : p
    }
}

struct Server: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var kind: ServerKind = .webdav

    // WebDAV: full base URL, e.g. http://nas.local:5005/dav
    var url: String = ""
    var allowUntrustedCertificate: Bool = false

    // SMB
    var host: String = ""
    var port: Int? = nil
    var share: String = ""
    var domain: String = ""

    var username: String = ""
    var password: String = ""

    var destinations: [Destination] = []

    var displayName: String {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        switch kind {
        case .webdav: return url.isEmpty ? "WebDAV" : url
        case .smb: return host.isEmpty ? "SMB" : "\(host)/\(share)"
        }
    }

    var subtitle: String {
        switch kind {
        case .webdav: return "WebDAV · \(url)"
        case .smb:
            let p = port.map { ":\($0)" } ?? ""
            return "SMB · \(host)\(p)/\(share)"
        }
    }
}

struct AppConfig: Codable {
    var servers: [Server] = []
    /// Remember the most recently used destination so it shows first.
    var lastDestinationID: UUID? = nil
}

enum RemotePath {
    /// Strips leading/trailing slashes and collapses duplicate separators.
    static func normalize(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }

    static func join(_ parts: String...) -> String {
        normalize(parts.filter { !$0.isEmpty }.joined(separator: "/"))
    }

    static func parent(_ path: String) -> String {
        var comps = normalize(path).split(separator: "/")
        guard !comps.isEmpty else { return "" }
        comps.removeLast()
        return comps.joined(separator: "/")
    }
}
