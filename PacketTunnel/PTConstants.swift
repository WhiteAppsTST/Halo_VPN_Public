import Foundation

enum PTConstants {
    static let appGroup = "group.com.guardiumvpn.apppp"

    enum UDKeys {
        static let subscriptionExpiresAt  = "subscription.expiresAt"
        static let dnsProvider            = "prefs.dnsProvider"
        static let tunnelLastErrorStage   = "tunnel.lastError.stage"
        static let tunnelLastErrorMessage = "tunnel.lastError.message"
        static let tunnelLastErrorAt      = "tunnel.lastError.at"
    }

    /// DNS-серверы по выбору пользователя в Privacy Center. Дублирует
    /// `DNSProvider.servers` из основного таргета (таргеты не шарят код).
    /// Пустой список = провайдер `off`, тогда туннель отдаёт дефолтные резолверы.
    static func dnsServers(for rawValue: String) -> [String] {
        switch rawValue {
        case "cloudflare":             return ["1.1.1.1", "1.0.0.1"]
        case "cloudflareBlockMalware": return ["1.1.1.2", "1.0.0.2"]
        case "google":                 return ["8.8.8.8", "8.8.4.4"]
        case "adguard":                return ["94.140.14.14", "94.140.15.15"]
        case "nextDNS":                return ["45.90.28.0", "45.90.30.0"]
        default:                       return []
        }
    }

    static let defaultDNSServers = ["1.1.1.1", "8.8.8.8"]
}
