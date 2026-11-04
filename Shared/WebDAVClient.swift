import Foundation

final class WebDAVClient: NSObject, RemoteClient {
    private let baseURL: URL
    private let username: String
    private let password: String
    private let allowUntrusted: Bool
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 60 * 60 * 6
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    init(server: Server) throws {
        var s = server.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else {
            throw RemoteError.invalidConfiguration("WebDAV 地址无效：\(server.url)")
        }
        baseURL = url
        username = server.username
        password = server.password
        allowUntrusted = server.allowUntrustedCertificate
    }

    // MARK: - URL helpers

    private static let segmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/;?#%")
        return set
    }()

    private func url(for path: String, directory: Bool = false) -> URL {
        let encoded = RemotePath.normalize(path)
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: Self.segmentAllowed) ?? String($0) }
            .joined(separator: "/")
        var s = baseURL.absoluteString
        if !encoded.isEmpty { s += "/" + encoded }
        if directory { s += "/" }
        return URL(string: s)!
    }

    private func request(_ method: String, _ path: String, directory: Bool = false) -> URLRequest {
        var req = URLRequest(url: url(for: path, directory: directory))
        req.httpMethod = method
        if !username.isEmpty || !password.isEmpty {
            let token = Data("\(username):\(password)".utf8).base64EncodedString()
            req.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func check(_ response: URLResponse, _ data: Data?, ok: Set<Int>) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard ok.contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0.prefix(300), encoding: .utf8) } ?? ""
            throw RemoteError.http(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode) + (body.isEmpty ? "" : "\n\(body)"))
        }
    }

    // MARK: - RemoteClient

    func connect() async throws {
        _ = try await list("")
    }

    func disconnect() async {
        session.finishTasksAndInvalidate()
    }

    func list(_ path: String) async throws -> [RemoteItem] {
        var req = request("PROPFIND", path, directory: true)
        req.setValue("1", forHTTPHeaderField: "Depth")
        req.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>
        """.utf8)
        let (data, resp) = try await session.data(for: req)
        try check(resp, data, ok: [207, 200])

        let parser = PropfindParser(data: data)
        let selfPath = RemotePath.normalize(path)
        let basePath = RemotePath.normalize(baseURL.path)
        var items: [RemoteItem] = []
        for entry in parser.parse() {
            // href may be absolute ("http://host/dav/a") or a path ("/dav/a").
            var hrefPath = entry.href
            if let u = URL(string: entry.href), u.scheme != nil { hrefPath = u.path }
            hrefPath = hrefPath.removingPercentEncoding ?? hrefPath
            var rel = RemotePath.normalize(hrefPath)
            if !basePath.isEmpty {
                if rel == basePath { rel = "" }
                else if rel.hasPrefix(basePath + "/") { rel = String(rel.dropFirst(basePath.count + 1)) }
            }
            if rel == selfPath { continue }
            let name = rel.split(separator: "/").last.map(String.init) ?? rel
            guard !name.isEmpty else { continue }
            items.append(RemoteItem(name: name, path: RemotePath.join(selfPath, name), isDirectory: entry.isCollection))
        }
        return items.sorted { ($0.isDirectory ? 0 : 1, $0.name.localizedLowercase) < ($1.isDirectory ? 0 : 1, $1.name.localizedLowercase) }
    }

    func exists(_ path: String) async throws -> Bool {
        var req = request("PROPFIND", path)
        req.setValue("0", forHTTPHeaderField: "Depth")
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 404 { return false }
        try check(resp, data, ok: [207, 200, 301, 302])
        return true
    }

    func makeDirectory(_ path: String) async throws {
        let req = request("MKCOL", path, directory: true)
        let (data, resp) = try await session.data(for: req)
        // 405 = already exists
        try check(resp, data, ok: [201, 200, 204, 405])
    }

    func upload(file: URL, to path: String, progress: @escaping (Int64) -> Void) async throws {
        var req = request("PUT", path)
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
            req.setValue(String(size), forHTTPHeaderField: "Content-Length")
        }
        let delegate = UploadProgressDelegate(progress: progress)
        let (data, resp) = try await session.upload(for: req, fromFile: file, delegate: delegate)
        try check(resp, data, ok: [200, 201, 204])
    }
}

extension WebDAVClient: URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler)
    }

    private func handle(_ challenge: URLAuthenticationChallenge,
                        _ completion: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            if allowUntrusted, let trust = challenge.protectionSpace.serverTrust {
                completion(.useCredential, URLCredential(trust: trust))
            } else {
                completion(.performDefaultHandling, nil)
            }
        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM:
            if challenge.previousFailureCount < 2 {
                completion(.useCredential, URLCredential(user: username, password: password, persistence: .forSession))
            } else {
                completion(.rejectProtectionSpace, nil)
            }
        default:
            completion(.performDefaultHandling, nil)
        }
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let progress: (Int64) -> Void
    init(progress: @escaping (Int64) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        progress(totalBytesSent)
    }
}

private final class PropfindParser: NSObject, XMLParserDelegate {
    struct Entry { var href = ""; var isCollection = false }

    private let parser: XMLParser
    private var entries: [Entry] = []
    private var current: Entry?
    private var text = ""

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.shouldProcessNamespaces = true
        parser.delegate = self
    }

    func parse() -> [Entry] {
        parser.parse()
        return entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        switch elementName.lowercased() {
        case "response": current = Entry()
        case "collection": current?.isCollection = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName.lowercased() {
        case "href": current?.href = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "response":
            if let c = current { entries.append(c) }
            current = nil
        default: break
        }
    }
}
