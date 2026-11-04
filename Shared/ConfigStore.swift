import Foundation
import Security

/// Resolves the App Group shared between the app and the share extension.
///
/// Sideloading tools (AltStore, SideStore, Sideloadly…) often rewrite the
/// app group identifier (e.g. append the team ID), so the hard-coded value
/// may not be the one actually granted. We try, in order:
/// 1. The group listed in Info.plist (`SendItAppGroup`).
/// 2. Any `group.*` entry in the embedded provisioning profile.
enum AppGroup {
    static let identifier: String? = resolve()

    static var containerURL: URL? {
        guard let id = identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    private static func resolve() -> String? {
        var candidates: [String] = []
        if let id = Bundle.main.object(forInfoDictionaryKey: "SendItAppGroup") as? String {
            candidates.append(id)
        }
        let groups = provisionedGroups()
        // Prefer groups that look like ours (possibly with a suffix added by the signer).
        candidates += groups.filter { $0.contains("sendit") }
        candidates += groups
        for id in candidates where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil {
            return id
        }
        return nil
    }

    private static func provisionedGroups() -> [String] {
        // The extension lives in App.app/PlugIns/X.appex, check both bundles.
        var urls = [Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")]
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        urls.append(appURL.appendingPathComponent("embedded.mobileprovision"))
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let start = data.range(of: Data("<?xml".utf8)),
                  let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
            else { continue }
            let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
            guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                  let ent = plist["Entitlements"] as? [String: Any],
                  let groups = ent["com.apple.security.application-groups"] as? [String]
            else { continue }
            return groups
        }
        return []
    }
}

final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published var config: AppConfig {
        didSet { save() }
    }

    /// False when the App Group is unavailable; then the share extension
    /// cannot see servers configured in the app.
    let isShared: Bool

    private let fileURL: URL

    private init() {
        if let dir = AppGroup.containerURL {
            fileURL = dir.appendingPathComponent("config.json")
            isShared = true
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            fileURL = dir.appendingPathComponent("config.json")
            isShared = false
        }
        if let data = try? Data(contentsOf: fileURL),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = cfg
        } else {
            config = AppConfig()
        }
    }

    func reload() {
        if let data = try? Data(contentsOf: fileURL),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = cfg
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func server(withID id: UUID) -> Server? {
        config.servers.first { $0.id == id }
    }

    func upsert(_ server: Server) {
        if let i = config.servers.firstIndex(where: { $0.id == server.id }) {
            config.servers[i] = server
        } else {
            config.servers.append(server)
        }
    }
}
