import Foundation

struct VPNServerConfig: Identifiable, Hashable, Codable {
    enum Kind: String, Codable { case vless, vmess, trojan, shadowsocks, unknown }

    let id: UUID
    let kind: Kind
    let rawURL: String        // vless://... — отдаём в extension как есть
    let remark: String
    let host: String
    let port: Int
    let countryCode: String?  // ISO alpha-2 если удалось определить
    let dateAdded: Date?      // только для custom-конфигов; у subscription-серверов nil

    init(
        id: UUID = UUID(),
        kind: Kind,
        rawURL: String,
        remark: String,
        host: String,
        port: Int,
        countryCode: String?,
        dateAdded: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.rawURL = rawURL
        self.remark = remark
        self.host = host
        self.port = port
        self.countryCode = countryCode
        self.dateAdded = dateAdded
    }

    /// Копия с проставленной датой добавления — для пользовательских конфигов.
    func withDateAdded(_ date: Date) -> VPNServerConfig {
        VPNServerConfig(
            id: id, kind: kind, rawURL: rawURL, remark: remark,
            host: host, port: port, countryCode: countryCode, dateAdded: date
        )
    }
}
