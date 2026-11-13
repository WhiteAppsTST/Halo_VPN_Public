import Foundation

enum ManualEdProtocol: String, CaseIterable, Identifiable, Hashable {
    case vless = "VLESS"
    case vmess = "VMESS"
    case trojan = "TROJAN"
    case shadowsocks = "SS"

    var id: String { rawValue }
    var title: String { rawValue }
}

enum ManualEdSecurity: String, CaseIterable, Identifiable {
    case none    = "none"
    case tls     = "tls"
    case reality = "reality"

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum ManualEdVmessSecurity: String, CaseIterable, Identifiable {
    case auto              = "auto"
    case none              = "none"
    case aes128gcm         = "aes-128-gcm"
    case chacha20poly1305  = "chacha20-poly1305"

    var id: String { rawValue }
    var title: String { rawValue }
}

enum ManualEdNetwork: String, CaseIterable, Identifiable {
    case tcp
    case ws
    case grpc

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum ManualEdHeaderType: String, CaseIterable, Identifiable {
    case none
    case http

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ManualEdFingerprint: String, CaseIterable, Identifiable {
    case chrome, firefox, safari, ios, android, edge, qq, random

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ManualEdSSMethod: String, CaseIterable, Identifiable {
    case aes256gcm = "aes-256-gcm"
    case aes128gcm = "aes-128-gcm"
    case chacha20poly1305 = "chacha20-poly1305"
    case xchacha20poly1305 = "xchacha20-poly1305"

    var id: String { rawValue }
    var title: String { rawValue }
}
