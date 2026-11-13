import Foundation

struct ManualEdFormState {
    // Общие
    var proto: ManualEdProtocol = .vless
    var name: String = ""
    var host: String = ""
    var port: String = ""

    // VLESS / VMess — user credential
    var uuid: String = ""

    // VMess-specific
    var alterId: String = "0"
    var vmessSecurity: ManualEdVmessSecurity = .auto
    var vmessTLS: Bool = false

    // Trojan / Shadowsocks — password
    var password: String = ""

    // Shadowsocks-specific
    var ssMethod: ManualEdSSMethod = .aes256gcm

    // Transport (VLESS/VMess/Trojan)
    var network: ManualEdNetwork = .tcp
    var headerType: ManualEdHeaderType = .none

    // VLESS/Trojan security
    var security: ManualEdSecurity = .none

    // TLS / Reality
    var sni: String = ""
    var fingerprint: ManualEdFingerprint = .chrome

    // Reality-only
    var publicKey: String = ""
    var shortID: String = ""
    var flow: String = "xtls-rprx-vision"

    // WS/gRPC transport
    var path: String = ""
    var wsHost: String = ""
}
