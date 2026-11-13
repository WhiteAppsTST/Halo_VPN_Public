import Foundation

/// Известные публичные DNS-over-HTTPS провайдеры. Значение сохраняется в
/// UserDefaults как rawValue; применяется через NEDNSSettingsManager в
/// PrivacyCenterHelpers.applyDNS(provider:).
enum DNSProvider: String, CaseIterable, Identifiable {
    case off
    case cloudflare
    case cloudflareBlockMalware   // 1.1.1.2 — блок malware
    case google
    case adguard
    case nextDNS                  // публичный неперсонализированный endpoint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:                     return "System (Off)"
        case .cloudflare:              return "Cloudflare (1.1.1.1)"
        case .cloudflareBlockMalware:  return "Cloudflare — Block Malware"
        case .google:                  return "Google (8.8.8.8)"
        case .adguard:                 return "AdGuard DNS"
        case .nextDNS:                 return "NextDNS"
        }
    }

    var subtitle: String {
        switch self {
        case .off:                     return "Use system default resolver"
        case .cloudflare:              return "Fast, no logs, no filtering"
        case .cloudflareBlockMalware:  return "Blocks known malware domains"
        case .google:                  return "Reliable, minimal filtering"
        case .adguard:                 return "Blocks ads and trackers"
        case .nextDNS:                 return "Community filter lists"
        }
    }

    /// Cleartext-серверы (IPv4/IPv6) — резервный список для NEDNSOverHTTPSSettings.
    var servers: [String] {
        switch self {
        case .off:                    return []
        case .cloudflare:             return ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"]
        case .cloudflareBlockMalware: return ["1.1.1.2", "1.0.0.2", "2606:4700:4700::1112", "2606:4700:4700::1002"]
        case .google:                 return ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"]
        case .adguard:                return ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"]
        case .nextDNS:                return ["45.90.28.0", "45.90.30.0"]
        }
    }

    /// DoH endpoint (RFC 8484). nil для .off.
    var dohURL: URL? {
        switch self {
        case .off:                    return nil
        case .cloudflare:             return URL(string: "https://cloudflare-dns.com/dns-query")
        case .cloudflareBlockMalware: return URL(string: "https://security.cloudflare-dns.com/dns-query")
        case .google:                 return URL(string: "https://dns.google/dns-query")
        case .adguard:                return URL(string: "https://dns.adguard-dns.com/dns-query")
        case .nextDNS:                return URL(string: "https://dns.nextdns.io")
        }
    }
}
