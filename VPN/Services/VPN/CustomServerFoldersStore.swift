import Foundation
import Observation

@MainActor
@Observable
final class CustomServerFoldersStore {
    static let shared = CustomServerFoldersStore()

    private let storageKey = "CustomServerFolders.v1"
    private let defaults: UserDefaults = .standard

    private(set) var folders: [CustomServerFolder] = []

    private init() {
        load()
    }

    var isEmpty: Bool { folders.isEmpty }
    var totalServers: Int { folders.reduce(0) { $0 + $1.servers.count } }

    /// Add a single share-link — becomes a folder with 1 server.
    @discardableResult
    func addLink(_ rawURL: String, folderName: String? = nil) -> CustomServerFolder? {
        guard let config = VPNConfigParser.parseLine(rawURL) else { return nil }
        return append(servers: [config], suggestedName: folderName ?? config.remark)
    }

    /// Import a config file (base64 / plain list of share-links) — one folder with N servers.
    @discardableResult
    func importFile(contents: String, folderName: String? = nil, limit: Int = 500) -> CustomServerFolder? {
        let parsed = Array(VPNConfigParser.parseSubscription(contents).prefix(limit))
        guard !parsed.isEmpty else { return nil }
        return append(servers: parsed, suggestedName: folderName)
    }

    func remove(folderId: UUID) {
        folders.removeAll { $0.id == folderId }
        save()
    }

    func rename(folderId: UUID, to newName: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[idx].name = newName
        save()
    }

    // MARK: - Helpers
    private func append(servers: [VPNServerConfig], suggestedName: String?) -> CustomServerFolder {
        let name = (suggestedName?.isEmpty == false ? suggestedName! : defaultName())
        let folder = CustomServerFolder(name: name, servers: servers)
        folders.append(folder)
        save()
        return folder
    }

    private func defaultName() -> String {
        "PROXY VPN - \(folders.count + 1)"
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CustomServerFolder].self, from: data)
        else { return }
        folders = decoded
    }
}
