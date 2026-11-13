import Foundation

/// Обратка к VPNConfigParser: собирает share-link (`vless://…`, `vmess://…`,
/// `trojan://…`, `ss://…`) из отдельных полей формы Manual Setup. Результат
/// уходит в CustomServerFoldersStore.addLink(_:), где парсер валидирует и сохраняет.
enum ShareLinkBuilder {

    // vless://<uuid>@<host>:<port>?type=<net>&security=<sec>&sni=<sni>&pbk=<pbk>
    //   &sid=<sid>&fp=<fp>&flow=<flow>&path=<path>&host=<wsHost>&serviceName=<svc>
    //   &headerType=<hdr>#<name>
    static func buildVLESS(
        name: String,
        host: String,
        port: Int,
        uuid: String,
        security: String,   // none / tls / reality
        network: String,    // tcp / ws / grpc
        sni: String? = nil,
        publicKey: String? = nil,
        shortID: String? = nil,
        fingerprint: String? = nil,
        flow: String? = nil,
        path: String? = nil,
        wsHost: String? = nil,
        serviceName: String? = nil,
        headerType: String? = nil
    ) -> String {
        var q: [String: String] = [
            "type":     network,
            "security": security
        ]
        put(&q, "sni",         sni)
        put(&q, "pbk",         publicKey)
        put(&q, "sid",         shortID)
        put(&q, "fp",          fingerprint)
        put(&q, "flow",        flow)
        put(&q, "path",        path)
        put(&q, "host",        wsHost)
        put(&q, "serviceName", serviceName)
        put(&q, "headerType",  headerType)
        return "vless://\(uuid)@\(host):\(port)?\(encode(q))#\(fragment(name))"
    }

    // vmess://base64(json {v,ps,add,port,id,aid,scy,net,type,host,path,tls,sni})
    static func buildVMess(
        name: String,
        host: String,
        port: Int,
        uuid: String,
        alterId: Int,
        security: String,      // scy: auto / none / aes-128-gcm / chacha20-poly1305
        network: String,       // tcp / ws / grpc
        tls: Bool,
        sni: String? = nil,
        path: String? = nil,
        wsHost: String? = nil,
        headerType: String? = nil
    ) -> String {
        var obj: [String: Any] = [
            "v":    "2",
            "ps":   name,
            "add":  host,
            "port": port,
            "id":   uuid,
            "aid":  alterId,
            "scy":  security,
            "net":  network,
            "type": headerType ?? "none",
            "tls":  tls ? "tls" : ""
        ]
        if let sni,    !sni.isEmpty    { obj["sni"]  = sni }
        if let path,   !path.isEmpty   { obj["path"] = path }
        if let wsHost, !wsHost.isEmpty { obj["host"] = wsHost }

        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else {
            return ""
        }
        return "vmess://\(data.base64EncodedString())"
    }

    // trojan://<password>@<host>:<port>?type=<net>&security=<sec>&sni=<sni>
    //   &path=<path>&host=<wsHost>#<name>
    static func buildTrojan(
        name: String,
        host: String,
        port: Int,
        password: String,
        security: String,   // tls / none
        network: String,    // tcp / ws / grpc
        sni: String? = nil,
        path: String? = nil,
        wsHost: String? = nil
    ) -> String {
        var q: [String: String] = [
            "type":     network,
            "security": security
        ]
        put(&q, "sni",  sni)
        put(&q, "path", path)
        put(&q, "host", wsHost)
        let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? password
        return "trojan://\(encodedPassword)@\(host):\(port)?\(encode(q))#\(fragment(name))"
    }

    // ss://base64(method:password)@host:port#name
    static func buildShadowsocks(
        name: String,
        host: String,
        port: Int,
        method: String,
        password: String
    ) -> String {
        let userInfo = "\(method):\(password)"
        let b64 = Data(userInfo.utf8).base64EncodedString()
        return "ss://\(b64)@\(host):\(port)#\(fragment(name))"
    }

    //MARK: - Helpers
    private static func put(_ q: inout [String: String], _ key: String, _ val: String?) {
        guard let v = val, !v.isEmpty else { return }
        q[key] = v
    }

    private static func encode(_ q: [String: String]) -> String {
        var comp = URLComponents()
        comp.queryItems = q.keys.sorted().map { URLQueryItem(name: $0, value: q[$0]) }
        return comp.percentEncodedQuery ?? ""
    }

    private static func fragment(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? name
    }
}
