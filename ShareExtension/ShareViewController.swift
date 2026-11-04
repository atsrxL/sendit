import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let state = ShareState()

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareRootView(state: state) { [weak self] success in
            self?.finish(success: success)
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { await state.load(items: items) }
    }

    private func finish(success: Bool) {
        state.cleanup()
        if success {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }
    }
}

@MainActor
final class ShareState: ObservableObject {
    @Published var files: [URL] = []
    @Published var preparing = true
    @Published var error: String?

    private let workDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)

    func load(items: [NSExtensionItem]) async {
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        var result: [URL] = []
        var errors: [String] = []
        var index = 0
        for item in items {
            for provider in item.attachments ?? [] {
                index += 1
                do {
                    if let url = try await ItemLoader.load(provider, title: item.attributedContentText?.string, index: index, into: workDir) {
                        result.append(url)
                    }
                } catch {
                    errors.append(error.localizedDescription)
                }
            }
        }
        files = result
        preparing = false
        if result.isEmpty {
            error = errors.first ?? "没有可发送的内容"
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: workDir)
    }
}

struct ShareRootView: View {
    @ObservedObject var state: ShareState
    let onClose: (Bool) -> Void

    var body: some View {
        SendView(files: state.files, preparing: state.preparing, prepareError: state.error, onClose: onClose)
    }
}

/// Turns an NSItemProvider into a local file we own.
enum ItemLoader {
    static func load(_ provider: NSItemProvider, title: String?, index: Int, into dir: URL) async throws -> URL? {
        let types = provider.registeredTypeIdentifiers

        // 1. Real files (Files app, Photos, documents, …)
        if let fileType = preferredFileType(types) {
            return try await copyFileRepresentation(provider, type: fileType, index: index, into: dir)
        }

        // 2. Web links -> .webloc-style text file
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
            if let url = (item as? URL) ?? (item as? NSURL as URL?) ?? (item as? String).flatMap(URL.init(string:)) {
                if url.isFileURL {
                    return try copy(url, named: url.lastPathComponent, into: dir)
                }
                let name = sanitized(title ?? url.host ?? "link") + ".url"
                let body = "[InternetShortcut]\nURL=\(url.absoluteString)\n"
                return try write(Data(body.utf8), named: name, into: dir)
            }
        }

        // 3. Plain text -> .txt
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
            let text = (item as? String) ?? (item as? NSAttributedString)?.string ?? ((item as? Data).flatMap { String(data: $0, encoding: .utf8) }) ?? ""
            let name = "Text_\(timestamp())\(index > 1 ? "_\(index)" : "").txt"
            return try write(Data(text.utf8), named: name, into: dir)
        }

        // 4. Anything else that is data
        if let any = types.first(where: { UTType($0)?.conforms(to: .data) == true }) {
            return try await copyFileRepresentation(provider, type: any, index: index, into: dir)
        }
        return nil
    }

    private static func preferredFileType(_ types: [String]) -> String? {
        let utTypes = types.compactMap(UTType.init)
        if utTypes.contains(where: { $0 == .fileURL }) {
            // A file URL: take the first concrete content type, else generic item.
            return utTypes.first(where: { $0.conforms(to: .data) && $0 != .fileURL })?.identifier ?? UTType.item.identifier
        }
        // Media & documents: images, movies, pdf, archives, …
        let skip: [UTType] = [.url, .plainText, .text]
        return utTypes.first(where: { t in
            (t.conforms(to: .image) || t.conforms(to: .audiovisualContent) || t.conforms(to: .pdf)
             || t.conforms(to: .archive) || t.conforms(to: .spreadsheet) || t.conforms(to: .presentation)
             || (t.conforms(to: .data) && !skip.contains(where: { t.conforms(to: $0) })))
        })?.identifier
    }

    private static func copyFileRepresentation(_ provider: NSItemProvider, type: String, index: Int, into dir: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else {
                    cont.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                var name = provider.suggestedName ?? url.deletingPathExtension().lastPathComponent
                if name.isEmpty { name = "File_\(timestamp())_\(index)" }
                let ext = url.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "") : url.pathExtension
                if !ext.isEmpty && (name as NSString).pathExtension.lowercased() != ext.lowercased() {
                    name += "." + ext
                }
                do {
                    cont.resume(returning: try copy(url, named: name, into: dir))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func uniqueURL(_ name: String, in dir: URL) -> URL {
        let safe = sanitized(name)
        var url = dir.appendingPathComponent(safe)
        var i = 1
        let ns = safe as NSString
        while FileManager.default.fileExists(atPath: url.path) {
            let ext = ns.pathExtension
            url = dir.appendingPathComponent(ext.isEmpty ? "\(ns.deletingPathExtension) (\(i))" : "\(ns.deletingPathExtension) (\(i)).\(ext)")
            i += 1
        }
        return url
    }

    private static func copy(_ src: URL, named name: String, into dir: URL) throws -> URL {
        let access = src.startAccessingSecurityScopedResource()
        defer { if access { src.stopAccessingSecurityScopedResource() } }
        let dst = uniqueURL(name, in: dir)
        // Hard link/clone when possible to avoid doubling disk usage for big videos.
        do {
            try FileManager.default.linkItem(at: src, to: dst)
        } catch {
            try FileManager.default.copyItem(at: src, to: dst)
        }
        return dst
    }

    private static func write(_ data: Data, named name: String, into dir: URL) throws -> URL {
        let dst = uniqueURL(name, in: dir)
        try data.write(to: dst)
        return dst
    }

    static func sanitized(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let cleaned = s.components(separatedBy: bad).joined(separator: "_").trimmingCharacters(in: .whitespaces)
        return String((cleaned.isEmpty ? "file" : cleaned).prefix(120))
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
