import Foundation

struct CustomServerFolder: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let addedAt: Date
    var servers: [VPNServerConfig]

    init(
        id: UUID = UUID(),
        name: String,
        addedAt: Date = Date(),
        servers: [VPNServerConfig]
    ) {
        self.id = id
        self.name = name
        self.addedAt = addedAt
        self.servers = servers
    }
}
