import Foundation

/// Парсит base64-подписку или plain-text список share-link'ов.
/// Поддерживает: vless / vmess (base64 JSON) / trojan / shadowsocks.
enum VPNConfigParser {

    static func parseSubscription(_ raw: String) -> [VPNServerConfig] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String = decodeBase64(trimmed) ?? trimmed

        // Формат 1 — Remnawave JSON:
        // { "isFound": true, "user": {...}, "links": ["vless://...", ...] }
        if let data = normalized.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let links = json["links"] as? [String], !links.isEmpty {
                return links.compactMap { parseLine($0) }
            }
            if json["isFound"] != nil { return [] }
        }

        // Формат 2 — plain text, по одному share-link на строку
        var result: [VPNServerConfig] = []
        normalized
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .forEach { line in
                if let cfg = parseLine(line) { result.append(cfg) }
            }
        return result
    }

    static func parseLine(_ raw: String) -> VPNServerConfig? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        if line.hasPrefix("vless://")  { return parseVless(line) }
        if line.hasPrefix("vmess://")  { return parseVmess(line) }
        if line.hasPrefix("trojan://") { return parseTrojan(line) }
        if line.hasPrefix("ss://")     { return parseShadowsocks(line) }
        return nil
    }

    //MARK: - URL-shape (vless/trojan/ss)
    private static func parseVless(_ url: String) -> VPNServerConfig? {
        guard let comp = URLComponents(string: url),
              let host = comp.host, let port = comp.port else { return nil }
        let remark = comp.fragment?.removingPercentEncoding ?? "\(host):\(port)"
        return VPNServerConfig(kind: .vless, rawURL: url, remark: remark,
                               host: host, port: port, countryCode: extractISO(from: remark))
    }

    private static func parseTrojan(_ url: String) -> VPNServerConfig? {
        guard let comp = URLComponents(string: url),
              let host = comp.host, let port = comp.port else { return nil }
        let remark = comp.fragment?.removingPercentEncoding ?? "\(host):\(port)"
        return VPNServerConfig(kind: .trojan, rawURL: url, remark: remark,
                               host: host, port: port, countryCode: extractISO(from: remark))
    }

    private static func parseShadowsocks(_ url: String) -> VPNServerConfig? {
        guard let comp = URLComponents(string: url),
              let host = comp.host, let port = comp.port else { return nil }
        let remark = comp.fragment?.removingPercentEncoding ?? "\(host):\(port)"
        return VPNServerConfig(kind: .shadowsocks, rawURL: url, remark: remark,
                               host: host, port: port, countryCode: extractISO(from: remark))
    }

    //MARK: - VMess (base64 JSON)
    private static func parseVmess(_ url: String) -> VPNServerConfig? {
        let base64Part = String(url.dropFirst("vmess://".count))
        guard let json = decodeBase64(base64Part),
              let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let host = (obj["add"] as? String) ?? ""
        let port: Int = {
            if let i = obj["port"] as? Int { return i }
            if let s = obj["port"] as? String, let i = Int(s) { return i }
            return 0
        }()
        let remark = (obj["ps"] as? String) ?? "\(host):\(port)"
        guard !host.isEmpty, port > 0 else { return nil }
        return VPNServerConfig(kind: .vmess, rawURL: url, remark: remark,
                               host: host, port: port, countryCode: extractISO(from: remark))
    }

    //MARK: - Helpers
    private static func decodeBase64(_ s: String) -> String? {
        var padded = s.replacingOccurrences(of: "-", with: "+")
                      .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        guard let data = Data(base64Encoded: padded, options: .ignoreUnknownCharacters),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    /// ISO из фрагмента share-link: сперва по emoji-флагу (regional indicators),
    /// fallback — regex `\b[A-Z]{2}\b`.
    private static func extractISO(from remark: String) -> String? {
        let scalars = remark.unicodeScalars
        let regionalA: UInt32 = 127462
        let regionalZ: UInt32 = 127487
        var letters: [Character] = []
        for s in scalars {
            if s.value >= regionalA && s.value <= regionalZ {
                let asciiVal = UInt32(s.value - regionalA) + 65
                if let u = UnicodeScalar(asciiVal) { letters.append(Character(u)) }
                if letters.count == 2 { return String(letters) }
            } else if !letters.isEmpty {
                letters.removeAll()
            }
        }
        if let re = try? NSRegularExpression(pattern: #"\b([A-Z]{2})\b"#) {
            let ns = remark as NSString
            if let m = re.firstMatch(in: remark, range: NSRange(location: 0, length: ns.length)),
               m.numberOfRanges > 1 {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }
}
