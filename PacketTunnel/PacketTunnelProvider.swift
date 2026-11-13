import NetworkExtension
import LibXray
import Tun2SocksKit
import Darwin

/// Архитектура (как у работающих iOS-клиентов на xray):
///
///   система → utun (NEPacketTunnelProvider)
///           → hev-socks5-tunnel (Tun2SocksKit) — разбирает IP-пакеты
///           → SOCKS5 127.0.0.1:10808 — штатный inbound xray
///           → xray-core → VPN-сервер
///
/// Прежняя схема отдавала xray сырые пакеты через `LibXraySetTunFd` и его
/// tun-inbound. В upstream Xray этот inbound помечен как недоделанный, а самой
/// функции `SetTunFd` в официальном libXray уже нет — она есть только в
/// сторонней пересборке без отладочных символов. Поэтому здесь используется
/// только стабильная часть xray (SOCKS), а работу с пакетами берёт на себя
/// hev-socks5-tunnel — тот же компонент, что и в других живых клиентах.
/// Старая реализация закомментирована в конце файла.
final class PacketTunnelProvider: NEPacketTunnelProvider {

    /// Локальный порт SOCKS5-инбаунда. Живёт внутри процесса расширения,
    /// наружу не слушает.
    private static let socksPort = 10808
    /// MTU. Одно значение и для системных настроек, и для tun2socks —
    /// рассинхрон приводит к тому, что крупные пакеты не проходят.
    private static let tunnelMTU = 1400

    private let running = AtomicFlag(false)

    override func startTunnel(options: [String : NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        TunnelDiagnostics.clear()
        NSLog("📡 PacketTunnel startTunnel begin")

        guard let proto = (protocolConfiguration as? NETunnelProviderProtocol),
              let config = proto.providerConfiguration,
              let rawURL = config["rawURL"] as? String, !rawURL.isEmpty else {
            let msg = "Missing rawURL in providerConfiguration"
            NSLog("❌ \(msg)")
            TunnelDiagnostics.recordError(stage: "config", message: msg)
            completionHandler(NSError(domain: "PacketTunnel", code: 1,
                userInfo: [NSLocalizedDescriptionKey: msg]))
            return
        }

        let host = (config["host"] as? String) ?? ""

        // Резолвим адрес сервера ДО поднятия туннеля: после setTunnelNetworkSettings
        // весь DNS уходит в ещё не работающий туннель. Полученные IP исключаем
        // из маршрутов, иначе соединение xray → сервер зациклится на самом себе.
        let endpoints = Self.resolve(host: host)
        guard !endpoints.isEmpty else {
            let msg = "Can't resolve server address \(host)"
            NSLog("❌ \(msg)")
            TunnelDiagnostics.recordError(stage: "dns", message: msg)
            completionHandler(NSError(domain: "PacketTunnel", code: 3,
                userInfo: [NSLocalizedDescriptionKey: msg]))
            return
        }
        NSLog("📡 host=\(host) → \(endpoints)")

        setTunnelNetworkSettings(Self.makeSettings(serverEndpoints: endpoints)) { [weak self] err in
            if let err {
                let msg = "setTunnelNetworkSettings: \(err.localizedDescription)"
                NSLog("❌ \(msg)")
                TunnelDiagnostics.recordError(stage: "tun-settings", message: msg)
                completionHandler(err)
                return
            }
            guard let self else {
                completionHandler(NSError(domain: "PacketTunnel", code: 2))
                return
            }
            do {
                try self.startXray(rawURL: rawURL, resolvedEndpoints: endpoints, originalHost: host)
                self.startTun2Socks()
                self.running.set(true)
                NSLog("🚀 tunnel up: xray socks:\(Self.socksPort) + hev-socks5-tunnel")
                completionHandler(nil)
            } catch let nsErr as NSError {
                let msg = "[\(nsErr.domain) \(nsErr.code)] \(nsErr.localizedDescription)"
                NSLog("❌ start failed: \(msg)")
                TunnelDiagnostics.recordError(stage: "xray-start", message: msg)
                self.shutdown()
                completionHandler(nsErr)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        NSLog("🛑 stopTunnel, reason=\(reason.rawValue)")
        shutdown()
        completionHandler()
    }

    /// Живое состояние по запросу приложения: `sendProviderMessage(Data("status".utf8))`
    /// → "running" / "stopped".
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard String(data: messageData, encoding: .utf8) == "status" else {
            completionHandler?(nil)
            return
        }
        let alive = running.value && LibXrayGetXrayState()
        completionHandler?(Data((alive ? "running" : "stopped").utf8))
    }

    //MARK: - Lifecycle

    private func shutdown() {
        running.set(false)
        Socks5Tunnel.quit()
        if LibXrayGetXrayState() {
            _ = LibXrayStopXray()
        }
    }

    private func startXray(rawURL: String, resolvedEndpoints: [ServerEndpoint], originalHost: String) throws {
        let finalJSON = try Self.buildXrayConfig(
            from: rawURL,
            resolvedEndpoints: resolvedEndpoints,
            originalHost: originalHost
        )
        NSLog("📝 Xray config built (\(finalJSON.count) bytes)")

        // datDir нужен libXray даже когда geosite/geoip не используются.
        let tmp     = FileManager.default.temporaryDirectory
        let dataDir = tmp.appendingPathComponent("xray-data", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        // mphCachePath ПУСТОЙ: иначе libXray пытается загрузить кэш матчера
        // с диска и падает, если файла нет.
        var err: NSError?
        let reqB64 = LibXrayNewXrayRunFromJSONRequest(dataDir.path, "", finalJSON, &err)
        if let err {
            NSLog("❌ NewXrayRunFromJSONRequest: \(err.localizedDescription)")
            throw err
        }
        if let runErr = Self.errorFromLibXrayResponse(LibXrayRunXrayFromJSON(reqB64)) {
            NSLog("❌ RunXrayFromJSON: \(runErr.localizedDescription)")
            throw runErr
        }
        NSLog("✅ xray running, socks5 on 127.0.0.1:\(Self.socksPort)")
    }

    /// Поднимает hev-socks5-tunnel. Дескриптор utun он находит сам, сканируя
    /// сокеты процесса (публичные getpeername/ioctl, не приватный API).
    /// Буферы уменьшены по рекомендации авторов для iOS: у NE-расширения
    /// жёсткий лимит памяти, дефолтные значения его пробивают.
    private func startTun2Socks() {
        let yaml = """
        tunnel:
          name: utun
          mtu: \(Self.tunnelMTU)
        socks5:
          address: 127.0.0.1
          port: \(Self.socksPort)
          udp: udp
        misc:
          task-stack-size: 24576
          tcp-buffer-size: 4096
          connect-timeout: 10000
          max-session-count: 1200
          log-level: warn
        """

        Socks5Tunnel.run(withConfig: .string(content: yaml)) { code in
            // Ненулевой код приходит уже после старта — сообщаем в приложение,
            // иначе туннель молча висит «подключённым» без трафика.
            guard code != 0 else { return }
            let msg = "hev-socks5-tunnel exited with code \(code)"
            NSLog("❌ \(msg)")
            TunnelDiagnostics.recordError(stage: "tun2socks", message: msg)
        }
    }

    /// Счётчики tun2socks — для диагностики в приложении.
    var trafficStats: (up: Int, down: Int) {
        let s = Socks5Tunnel.stats
        return (s.up.bytes, s.down.bytes)
    }

    //MARK: - JSON build
    private static func buildXrayConfig(from shareLink: String,
                                        resolvedEndpoints: [ServerEndpoint],
                                        originalHost: String) throws -> String {
        var outbound: [String: Any]
        if shareLink.hasPrefix("vless://") {
            outbound = try vlessOutbound(from: shareLink)
        } else if shareLink.hasPrefix("vmess://") {
            outbound = try vmessOutbound(from: shareLink)
        } else if shareLink.hasPrefix("trojan://") {
            outbound = try trojanOutbound(from: shareLink)
        } else if shareLink.hasPrefix("ss://") {
            outbound = try shadowsocksOutbound(from: shareLink)
        } else {
            throw NSError(domain: "PacketTunnel", code: 13,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported share-link scheme: \(shareLink.prefix(20))"])
        }

        // Подставляем заранее отрезолвленный IP: изнутри туннеля DNS ещё
        // недоступен, а домен нужен только для TLS/Reality SNI — он уже
        // проставлен в streamSettings ниже.
        if let ip = resolvedEndpoints.first?.address, !isIPAddress(originalHost) {
            outbound = applyResolvedAddress(ip, originalHost: originalHost, to: outbound)
        }

        // SOCKS5-inbound на localhost. Это штатный, годами отлаженный режим
        // xray — в отличие от tun-inbound, который в upstream помечен как
        // недоделанный. Пакеты в него заворачивает hev-socks5-tunnel.
        let inbound: [String: Any] = [
            "tag": "socks-in",
            "protocol": "socks",
            "listen": "127.0.0.1",
            "port": socksPort,
            "settings": [
                "auth": "noauth",
                "udp": true,
                "ip": "127.0.0.1"
            ],
            // Без sniffing домен теряется и в логах сервера видны только IP;
            // для TLS/HTTP он также нужен для корректной работы Reality-SNI.
            "sniffing": [
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "routeOnly": false
            ]
        ]

        let cfg: [String: Any] = [
            "log": ["loglevel": "warning"],
            "inbounds": [inbound],
            "outbounds": [
                outbound,
                ["tag": "direct", "protocol": "freedom", "settings": ["domainStrategy": "UseIP"]],
                ["tag": "block",  "protocol": "blackhole"]
            ]
        ]

        let bytes = try JSONSerialization.data(withJSONObject: cfg, options: [])
        return String(data: bytes, encoding: .utf8) ?? "{}"
    }

    /// Меняет адрес сервера на IP и гарантирует, что SNI остался исходным доменом.
    private static func applyResolvedAddress(_ ip: String,
                                             originalHost: String,
                                             to outbound: [String: Any]) -> [String: Any] {
        var out = outbound
        if var settings = out["settings"] as? [String: Any] {
            if var vnext = settings["vnext"] as? [[String: Any]], !vnext.isEmpty {
                vnext[0]["address"] = ip
                settings["vnext"] = vnext
            }
            if var servers = settings["servers"] as? [[String: Any]], !servers.isEmpty {
                servers[0]["address"] = ip
                settings["servers"] = servers
            }
            out["settings"] = settings
        }

        if var stream = out["streamSettings"] as? [String: Any] {
            let security = (stream["security"] as? String) ?? "none"
            if security == "tls" {
                var tls = (stream["tlsSettings"] as? [String: Any]) ?? [:]
                if (tls["serverName"] as? String)?.isEmpty ?? true {
                    tls["serverName"] = originalHost
                }
                stream["tlsSettings"] = tls
            } else if security == "reality" {
                var reality = (stream["realitySettings"] as? [String: Any]) ?? [:]
                if (reality["serverName"] as? String)?.isEmpty ?? true {
                    reality["serverName"] = originalHost
                }
                stream["realitySettings"] = reality
            }
            out["streamSettings"] = stream
        }
        return out
    }

    // vless://uuid@host:port?encryption=none&flow=xtls-rprx-vision&type=tcp&security=reality
    //   &sni=...&fp=...&pbk=...&sid=...&spx=...#remark
    private static func vlessOutbound(from url: String) throws -> [String: Any] {
        guard let comp = URLComponents(string: url),
              let uuid = comp.user,
              let host = comp.host,
              let port = comp.port else {
            throw NSError(domain: "PacketTunnel", code: 14,
                userInfo: [NSLocalizedDescriptionKey: "Bad VLESS URL"])
        }
        let q: [String: String] = queryDict(comp)

        // encryption ВСЕГДА "none" — единственное валидное значение для VLESS
        // (шифрует Reality/TLS-слой, не сам VLESS). Что бы ни пришло в URL — форсим.
        var user: [String: Any] = [
            "id":         uuid,
            "encryption": "none"
        ]
        if let flow = q["flow"], !flow.isEmpty { user["flow"] = flow }

        let network = q["type"] ?? "tcp"
        let security = q["security"] ?? "none"

        var stream: [String: Any] = [
            "network":  network,
            "security": security
        ]
        switch security {
        case "reality":
            let r: [String: Any] = [
                "serverName":  q["sni"] ?? host,
                "fingerprint": q["fp"]  ?? "chrome",
                "publicKey":   q["pbk"] ?? "",
                "shortId":     q["sid"] ?? "",
                "spiderX":     q["spx"] ?? ""
            ]
            stream["realitySettings"] = r
        case "tls":
            var t: [String: Any] = ["serverName": q["sni"] ?? host]
            if let v = q["fp"],   !v.isEmpty { t["fingerprint"] = v }
            if let v = q["alpn"], !v.isEmpty {
                t["alpn"] = v.split(separator: ",").map(String.init)
            }
            if q["allowInsecure"] == "1" { t["allowInsecure"] = true }
            stream["tlsSettings"] = t
        default: break
        }

        applyTransport(network: network, query: q, host: host, to: &stream)

        return [
            "tag":      "proxy",
            "protocol": "vless",
            "settings": [
                "vnext": [[
                    "address": host,
                    "port":    port,
                    "users":   [user]
                ]]
            ],
            "streamSettings": stream
        ]
    }

    // vmess://base64(json {add,port,id,aid,net,type,host,path,tls,sni,scy,ps})
    private static func vmessOutbound(from url: String) throws -> [String: Any] {
        let b64 = String(url.dropFirst("vmess://".count))
        guard let json = b64decode(b64),
              let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "PacketTunnel", code: 15,
                userInfo: [NSLocalizedDescriptionKey: "Bad VMess JSON"])
        }
        let host = (obj["add"] as? String) ?? ""
        let port: Int = {
            if let i = obj["port"] as? Int { return i }
            if let s = obj["port"] as? String, let i = Int(s) { return i }
            return 0
        }()
        guard !host.isEmpty, port > 0 else {
            throw NSError(domain: "PacketTunnel", code: 15,
                userInfo: [NSLocalizedDescriptionKey: "VMess config has no address"])
        }
        let id  = (obj["id"]  as? String) ?? ""
        let aid: Int = {
            if let i = obj["aid"] as? Int { return i }
            if let s = obj["aid"] as? String, let i = Int(s) { return i }
            return 0
        }()
        let net = (obj["net"] as? String) ?? "tcp"
        let tls = (obj["tls"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "none"
        let scy = (obj["scy"] as? String) ?? "auto"

        let userDict: [String: Any] = [
            "id":       id,
            "alterId":  aid,
            "security": scy
        ]
        var stream: [String: Any] = ["network": net, "security": tls]
        if tls == "tls" {
            let sni = (obj["sni"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (obj["host"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? host
            stream["tlsSettings"] = ["serverName": sni]
        }

        var q: [String: String] = [:]
        if let p = obj["path"] as? String, !p.isEmpty { q["path"] = p }
        if let h = obj["host"] as? String, !h.isEmpty { q["host"] = h }
        if let t = obj["type"] as? String, !t.isEmpty { q["headerType"] = t }
        // gRPC-сервис в vmess-ссылке традиционно едет в поле path.
        if net == "grpc", let p = obj["path"] as? String, !p.isEmpty { q["serviceName"] = p }
        applyTransport(network: net, query: q, host: host, to: &stream)

        return [
            "tag":      "proxy",
            "protocol": "vmess",
            "settings": [
                "vnext": [[
                    "address": host,
                    "port":    port,
                    "users":   [userDict]
                ]]
            ],
            "streamSettings": stream
        ]
    }

    private static func trojanOutbound(from url: String) throws -> [String: Any] {
        guard let comp = URLComponents(string: url),
              let password = comp.user?.removingPercentEncoding,
              let host = comp.host,
              let port = comp.port else {
            throw NSError(domain: "PacketTunnel", code: 16,
                userInfo: [NSLocalizedDescriptionKey: "Bad Trojan URL"])
        }
        let q: [String: String] = queryDict(comp)
        let network = q["type"] ?? "tcp"
        let security = q["security"] ?? "tls"
        var stream: [String: Any] = ["network": network, "security": security]
        if security == "tls" {
            var t: [String: Any] = ["serverName": q["sni"] ?? host]
            if let v = q["fp"],   !v.isEmpty { t["fingerprint"] = v }
            if let v = q["alpn"], !v.isEmpty {
                t["alpn"] = v.split(separator: ",").map(String.init)
            }
            stream["tlsSettings"] = t
        }
        applyTransport(network: network, query: q, host: host, to: &stream)

        return [
            "tag":      "proxy",
            "protocol": "trojan",
            "settings": [
                "servers": [[
                    "address":  host,
                    "port":     port,
                    "password": password
                ]]
            ],
            "streamSettings": stream
        ]
    }

    // ss://method:password@host:port  OR  ss://base64(method:password)@host:port
    private static func shadowsocksOutbound(from url: String) throws -> [String: Any] {
        var method = ""
        var password = ""
        var host = ""
        var port = 0
        if let comp = URLComponents(string: url), let h = comp.host, let p = comp.port {
            host = h; port = p
            if let user = comp.user, let pass = comp.password {
                method = user.removingPercentEncoding ?? user
                password = pass.removingPercentEncoding ?? pass
            } else if let user = comp.user {
                if let dec = b64decode(user), let colon = dec.firstIndex(of: ":") {
                    method   = String(dec[..<colon])
                    password = String(dec[dec.index(after: colon)...])
                }
            }
        }
        if method.isEmpty || password.isEmpty || host.isEmpty || port == 0 {
            let raw = String(url.dropFirst("ss://".count))
            guard let atIdx = raw.firstIndex(of: "@") else {
                throw NSError(domain: "PacketTunnel", code: 17,
                    userInfo: [NSLocalizedDescriptionKey: "Bad SS URL"])
            }
            let userPart = String(raw[..<atIdx])
            let hostPart = String(raw[raw.index(after: atIdx)...])
                .components(separatedBy: "#").first?
                .components(separatedBy: "?").first ?? ""
            if let dec = b64decode(userPart), let colon = dec.firstIndex(of: ":") {
                method   = String(dec[..<colon])
                password = String(dec[dec.index(after: colon)...])
            }
            if let colon = hostPart.lastIndex(of: ":") {
                host = String(hostPart[..<colon])
                if let p = Int(hostPart[hostPart.index(after: colon)...]) { port = p }
            }
        }
        guard !method.isEmpty, !password.isEmpty, !host.isEmpty, port > 0 else {
            throw NSError(domain: "PacketTunnel", code: 18,
                userInfo: [NSLocalizedDescriptionKey: "Bad SS components"])
        }
        return [
            "tag":      "proxy",
            "protocol": "shadowsocks",
            "settings": [
                "servers": [[
                    "address":  host,
                    "port":     port,
                    "method":   method,
                    "password": password
                ]]
            ]
        ]
    }

    /// ws / grpc / httpupgrade транспорты — общие для vless / vmess / trojan.
    private static func applyTransport(network: String,
                                       query q: [String: String],
                                       host: String,
                                       to stream: inout [String: Any]) {
        switch network {
        case "ws":
            var ws: [String: Any] = [:]
            ws["path"] = (q["path"]?.isEmpty == false) ? q["path"]! : "/"
            if let v = q["host"], !v.isEmpty { ws["headers"] = ["Host": v] }
            stream["wsSettings"] = ws
        case "httpupgrade":
            var hu: [String: Any] = [:]
            hu["path"] = (q["path"]?.isEmpty == false) ? q["path"]! : "/"
            hu["host"] = (q["host"]?.isEmpty == false) ? q["host"]! : host
            stream["httpupgradeSettings"] = hu
        case "grpc":
            var g: [String: Any] = [:]
            let service = q["serviceName"] ?? q["path"] ?? ""
            if !service.isEmpty { g["serviceName"] = service }
            if q["mode"] == "multi" { g["multiMode"] = true }
            stream["grpcSettings"] = g
        case "tcp":
            if q["headerType"] == "http" {
                var header: [String: Any] = ["type": "http"]
                if let h = q["host"], !h.isEmpty {
                    header["request"] = ["headers": ["Host": h.split(separator: ",").map(String.init)]]
                }
                stream["tcpSettings"] = ["header": header]
            }
        default:
            break
        }
    }

    //MARK: - Helpers
    private static func queryDict(_ comp: URLComponents) -> [String: String] {
        var d: [String: String] = [:]
        comp.queryItems?.forEach { if let v = $0.value { d[$0.name] = v } }
        return d
    }

    private static func isIPAddress(_ s: String) -> Bool {
        var sin = sockaddr_in()
        if s.withCString({ inet_pton(AF_INET, $0, &sin.sin_addr) }) == 1 { return true }
        var sin6 = sockaddr_in6()
        if s.withCString({ inet_pton(AF_INET6, $0, &sin6.sin6_addr) }) == 1 { return true }
        return false
    }

    struct ServerEndpoint: CustomStringConvertible {
        let address: String
        let isIPv6: Bool
        var description: String { address }
    }

    /// Синхронный резолв через getaddrinfo. IPv4 идёт первым — xray-outbound
    /// использует именно его, IPv6 нужен только чтобы исключить его из маршрутов.
    private static func resolve(host: String) -> [ServerEndpoint] {
        guard !host.isEmpty else { return [] }
        if isIPAddress(host) {
            return [ServerEndpoint(address: host, isIPv6: host.contains(":"))]
        }

        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &info) == 0, let first = info else { return [] }
        defer { freeaddrinfo(info) }

        var v4: [ServerEndpoint] = []
        var v6: [ServerEndpoint] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))

        while let node = cursor {
            if getnameinfo(node.pointee.ai_addr, node.pointee.ai_addrlen,
                           &buffer, socklen_t(buffer.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                let address = String(cString: buffer)
                if !address.isEmpty {
                    if node.pointee.ai_family == AF_INET6 {
                        v6.append(ServerEndpoint(address: address, isIPv6: true))
                    } else {
                        v4.append(ServerEndpoint(address: address, isIPv6: false))
                    }
                }
            }
            cursor = node.pointee.ai_next
        }
        return v4 + v6
    }

    private static func b64decode(_ s: String) -> String? {
        var padded = s.replacingOccurrences(of: "-", with: "+")
                      .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        guard let data = Data(base64Encoded: padded, options: .ignoreUnknownCharacters),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    // libXray response = base64({"success":bool,"data":...,"err":"..."})
    private static func errorFromLibXrayResponse(_ b64: String) -> NSError? {
        guard let obj = decodeResponse(b64) else {
            return NSError(domain: "libXray", code: 100,
                userInfo: [NSLocalizedDescriptionKey: "couldn't decode response: \(b64.prefix(200))"])
        }
        if (obj["success"] as? Bool) == true { return nil }
        // libXray в разных билдах кладёт текст ошибки то в "err", то в "error", то в "data"
        let candidates: [String?] = [
            obj["error"]   as? String,
            obj["err"]     as? String,
            obj["message"] as? String,
            obj["data"]    as? String
        ]
        let msg = candidates.compactMap { $0 }.first(where: { !$0.isEmpty })
            ?? "libXray failed (raw: \(b64.prefix(400)))"
        return NSError(domain: "libXray", code: 100,
            userInfo: [NSLocalizedDescriptionKey: msg])
    }

    private static func decodeResponse(_ b64: String) -> [String: Any]? {
        guard let raw = b64decode(b64)?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return nil }
        return obj
    }
    //MARK: - Network settings
    private static func makeSettings(serverEndpoints: [ServerEndpoint]) -> NEPacketTunnelNetworkSettings {
        // iOS требует IP в tunnelRemoteAddress. Hostnames отвергаются.
        let remote = serverEndpoints.first(where: { !$0.isIPv6 })?.address
            ?? serverEndpoints.first?.address
            ?? "127.0.0.1"
        let s = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remote)
        s.mtu = NSNumber(value: tunnelMTU)

        //MARK: IPv4
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        // Исключаем LAN — домашние роутеры/принтеры/AirPlay остаются доступны.
        var excludedV4 = [
            NEIPv4Route(destinationAddress: "10.0.0.0",    subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0",  subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0")
        ]
        // И сам VPN-сервер: иначе соединение xray → сервер зациклится на туннеле.
        for endpoint in serverEndpoints where !endpoint.isIPv6 {
            excludedV4.append(NEIPv4Route(destinationAddress: endpoint.address,
                                          subnetMask: "255.255.255.255"))
        }
        ipv4.excludedRoutes = excludedV4
        s.ipv4Settings = ipv4

        //MARK: IPv6
        // Без этого весь IPv6-трафик идёт мимо туннеля с реальным адресом.
        let ipv6 = NEIPv6Settings(addresses: ["fd6e:a81b:704f:1211::1"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        var excludedV6: [NEIPv6Route] = []
        for endpoint in serverEndpoints where endpoint.isIPv6 {
            excludedV6.append(NEIPv6Route(destinationAddress: endpoint.address,
                                          networkPrefixLength: 128))
        }
        ipv6.excludedRoutes = excludedV6
        s.ipv6Settings = ipv6

        //MARK: DNS
        // Берём провайдера, выбранного юзером в Privacy Center. Раньше здесь
        // всегда стояли 1.1.1.1/8.8.8.8, из-за чего выбор DNS в приложении
        // при активном туннеле не имел никакого эффекта.
        let shared = UserDefaults(suiteName: PTConstants.appGroup)
        let providerRaw = shared?.string(forKey: PTConstants.UDKeys.dnsProvider) ?? "off"
        let servers = PTConstants.dnsServers(for: providerRaw)
        let dns = NEDNSSettings(servers: servers.isEmpty ? PTConstants.defaultDNSServers : servers)
        dns.matchDomains = [""]
        s.dnsSettings = dns
        return s
    }
}

/// Потокобезопасный флаг: пишется на очереди NE, читается из detached-потока.
final class AtomicFlag {
    private var storage: Bool
    private let lock = NSLock()

    init(_ initial: Bool) { storage = initial }

    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func set(_ newValue: Bool) {
        lock.lock(); storage = newValue; lock.unlock()
    }
}


// =====================================================================
// ПРЕЖНЯЯ РЕАЛИЗАЦИЯ (xray tun-inbound через LibXraySetTunFd).
// Оставлена для истории: tun-inbound в upstream Xray недоделан, а SetTunFd
// есть только в сторонней пересборке libXray без отладочных символов.
// =====================================================================
// import NetworkExtension
// import LibXray
// import Darwin
//
// /// Архитектура (зеркалит SwiftyXrayKit):
// ///   1. socketpair(AF_UNIX, SOCK_STREAM) → fds[0], fds[1].
// ///   2. fds[0] → LibXraySetTunFd. Xray-core с патченым TUN inbound читает/пишет
// ///      сюда IP-пакеты в формате [4-byte big-endian AF][raw IP].
// ///   3. fds[1] держим у себя: NEPacketTunnelFlow ↔ swiftFd.
// final class PacketTunnelProvider: NEPacketTunnelProvider {
//
//     /// MTU туннеля. ОДНО значение и для системных настроек, и для tun-inbound
//     /// xray — рассинхрон приводит к тому, что крупные пакеты не проходят.
//     private static let tunnelMTU = 1400
//     private static let maxPacketSize = 65_536
//
//     private var xrayFd: Int32 = -1
//     private var swiftFd: Int32 = -1
//     private let running = AtomicFlag(false)
//
//     override func startTunnel(options: [String : NSObject]?,
//                               completionHandler: @escaping (Error?) -> Void) {
//         TunnelDiagnostics.clear()
//         NSLog("📡 PacketTunnel startTunnel begin")
//
//         guard let proto = (protocolConfiguration as? NETunnelProviderProtocol),
//               let config = proto.providerConfiguration,
//               let rawURL = config["rawURL"] as? String, !rawURL.isEmpty else {
//             let msg = "Missing rawURL in providerConfiguration"
//             NSLog("❌ \(msg)")
//             TunnelDiagnostics.recordError(stage: "config", message: msg)
//             completionHandler(NSError(domain: "PacketTunnel", code: 1,
//                 userInfo: [NSLocalizedDescriptionKey: msg]))
//             return
//         }
//
//         let host = (config["host"] as? String) ?? ""
//
//         // Резолвим адрес сервера ДО поднятия туннеля: после setTunnelNetworkSettings
//         // весь DNS уходит в ещё не работающий туннель, и резолв домена изнутри
//         // extension'а зависает. Полученные IP исключаем из маршрутов, чтобы
//         // соединение xray → сервер шло напрямую, а не по кругу через самого себя.
//         let endpoints = Self.resolve(host: host)
//         guard !endpoints.isEmpty else {
//             let msg = "Can't resolve server address \(host)"
//             NSLog("❌ \(msg)")
//             TunnelDiagnostics.recordError(stage: "dns", message: msg)
//             completionHandler(NSError(domain: "PacketTunnel", code: 3,
//                 userInfo: [NSLocalizedDescriptionKey: msg]))
//             return
//         }
//         NSLog("📡 PacketTunnel start, host=\(host) → \(endpoints), rawURL.prefix=\(rawURL.prefix(40))")
//
//         let settings = Self.makeSettings(serverEndpoints: endpoints)
//         setTunnelNetworkSettings(settings) { [weak self] err in
//             if let err = err {
//                 let msg = "setTunnelNetworkSettings: \(err.localizedDescription)"
//                 NSLog("❌ \(msg)")
//                 TunnelDiagnostics.recordError(stage: "tun-settings", message: msg)
//                 completionHandler(err)
//                 return
//             }
//             guard let self else {
//                 completionHandler(NSError(domain: "PacketTunnel", code: 2))
//                 return
//             }
//             do {
//                 try self.startXray(rawURL: rawURL, resolvedEndpoints: endpoints, originalHost: host)
//                 NSLog("🚀 Xray started, completionHandler(nil)")
//                 completionHandler(nil)
//             } catch let nsErr as NSError {
//                 let msg = "[\(nsErr.domain) \(nsErr.code)] \(nsErr.localizedDescription)"
//                 NSLog("❌ Xray start failed: \(msg)")
//                 TunnelDiagnostics.recordError(stage: "xray-start", message: msg)
//                 self.cleanupSocketpair()
//                 completionHandler(nsErr)
//             }
//         }
//     }
//
//     override func stopTunnel(with reason: NEProviderStopReason,
//                              completionHandler: @escaping () -> Void) {
//         NSLog("🛑 PacketTunnel stopTunnel, reason=\(reason.rawValue)")
//         running.set(false)
//         if LibXrayGetXrayState() {
//             _ = LibXrayStopXray()
//         }
//         cleanupSocketpair()
//         completionHandler()
//     }
//
//     /// Живое состояние туннеля по запросу приложения: `sendProviderMessage(Data("status".utf8))`
//     /// → "running" / "stopped". Полезно для диагностики на устройстве.
//     override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
//         let command = String(data: messageData, encoding: .utf8) ?? ""
//         switch command {
//         case "status":
//             let alive = running.value && LibXrayGetXrayState()
//             completionHandler?(Data((alive ? "running" : "stopped").utf8))
//         default:
//             completionHandler?(nil)
//         }
//     }
//
//     //MARK: - Lifecycle
//     private func cleanupSocketpair() {
//         let x = xrayFd, s = swiftFd
//         xrayFd = -1
//         swiftFd = -1
//         // shutdown разблокирует поток, висящий в recv, до того как fd закроется
//         // и его номер переиспользуют.
//         if s >= 0 { Darwin.shutdown(s, SHUT_RDWR) }
//         if x >= 0 { Darwin.close(x) }
//         if s >= 0 { Darwin.close(s) }
//     }
//
//     private func startXray(rawURL: String, resolvedEndpoints: [ServerEndpoint], originalHost: String) throws {
//         var fds: [Int32] = [-1, -1]
//         guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
//             throw NSError(domain: "PacketTunnel", code: 20,
//                 userInfo: [NSLocalizedDescriptionKey: "socketpair failed: errno=\(errno)"])
//         }
//         xrayFd = fds[0]
//         swiftFd = fds[1]
//
//         // Буфер сокета под самый крупный IP-пакет, иначе writev упирается
//         // в дефолтные 8 КБ и постоянно блокирует поток packetFlow.
//         var bufSize = Int32(Self.maxPacketSize * 4)
//         setsockopt(swiftFd, SOL_SOCKET, SO_SNDBUF, &bufSize, socklen_t(MemoryLayout<Int32>.size))
//         setsockopt(swiftFd, SOL_SOCKET, SO_RCVBUF, &bufSize, socklen_t(MemoryLayout<Int32>.size))
//
//         LibXraySetTunFd(xrayFd)
//         NSLog("🔗 socketpair created: xrayFd=\(xrayFd) swiftFd=\(swiftFd)")
//
//         // Собственный билдер JSON — конвертер libXray в этой сборке пихает remark
//         // в sendThrough, из-за чего xray-core падает на парсинге конфига.
//         let finalJSON = try Self.buildXrayConfig(
//             from: rawURL,
//             resolvedEndpoints: resolvedEndpoints,
//             originalHost: originalHost
//         )
//         NSLog("📝 Xray config built (\(finalJSON.count) bytes)")
//
//         // datDir нужен libXray даже когда мы не используем geosite/geoip dat'ы.
//         let tmp     = FileManager.default.temporaryDirectory
//         let dataDir = tmp.appendingPathComponent("xray-data", isDirectory: true)
//         try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
//
//         // mphCachePath ПУСТОЙ: libXray иначе пытается загрузить кэш MphDomainMatcher
//         // с диска и падает если файла нет. Пустой путь → in-memory билд матчера.
//         let mphPath = ""
//
//         var err: NSError?
//         let reqB64 = LibXrayNewXrayRunFromJSONRequest(dataDir.path, mphPath, finalJSON, &err)
//         if let err = err {
//             NSLog("❌ NewXrayRunFromJSONRequest failed: \(err.localizedDescription)")
//             throw err
//         }
//         let runResp = LibXrayRunXrayFromJSON(reqB64)
//         if let runErr = Self.errorFromLibXrayResponse(runResp) {
//             NSLog("❌ RunXrayFromJSON failed: \(runErr.localizedDescription)")
//             throw runErr
//         }
//         NSLog("✅ LibXrayRunXrayFromJSON success, isRunning=true")
//
//         running.set(true)
//         launchReadThread(fd: swiftFd)
//         readFromPacketFlow()
//     }
//
//     //MARK: - I/O threads
//     /// Читает packets из xray (swiftFd) и пишет в packetFlow.
//     /// Формат: [4-byte big-endian AF][raw IP packet].
//     private func launchReadThread(fd: Int32) {
//         let flow = self.packetFlow
//         let running = self.running
//         let maxPacket = Self.maxPacketSize
//
//         Thread.detachNewThread {
//             let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: maxPacket)
//             defer { buf.deallocate() }
//
//             while running.value {
//                 guard Self.readExactly(fd: fd, into: buf, count: 4) else { return }
//                 let afRaw = buf.withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
//                 let af = CFSwapInt32BigToHost(afRaw)
//
//                 let packet: Data
//                 if af == UInt32(AF_INET) {
//                     guard Self.readExactly(fd: fd, into: buf, count: 20) else { return }
//                     let total = Int(CFSwapInt16BigToHost(
//                         buf.withMemoryRebound(to: UInt16.self, capacity: 10) { $0[1] }
//                     ))
//                     // Битая длина = рассинхрон потока, дальше читать нечего.
//                     guard total >= 20, total <= maxPacket else {
//                         NSLog("❌ IPv4 length out of range: \(total)")
//                         return
//                     }
//                     let remaining = total - 20
//                     if remaining > 0 {
//                         guard Self.readExactly(fd: fd, into: buf + 20, count: remaining) else { return }
//                     }
//                     packet = Data(bytes: buf, count: total)
//                 } else if af == UInt32(AF_INET6) {
//                     guard Self.readExactly(fd: fd, into: buf, count: 40) else { return }
//                     let payloadLen = Int(CFSwapInt16BigToHost(
//                         buf.withMemoryRebound(to: UInt16.self, capacity: 20) { $0[2] }
//                     ))
//                     guard payloadLen >= 0, 40 + payloadLen <= maxPacket else {
//                         NSLog("❌ IPv6 payload out of range: \(payloadLen)")
//                         return
//                     }
//                     if payloadLen > 0 {
//                         guard Self.readExactly(fd: fd, into: buf + 40, count: payloadLen) else { return }
//                     }
//                     packet = Data(bytes: buf, count: 40 + payloadLen)
//                 } else {
//                     // Неизвестное семейство — поток рассинхронизирован, выходим.
//                     NSLog("❌ Unknown address family from xray: \(af)")
//                     return
//                 }
//                 flow.writePackets([packet], withProtocols: [NSNumber(value: af)])
//             }
//         }
//     }
//
//     /// Читает packets из packetFlow и пишет в xray через swiftFd.
//     /// Формат: [4-byte big-endian AF][raw IP packet] одной writev.
//     private func readFromPacketFlow() {
//         guard running.value, swiftFd >= 0 else { return }
//         let fd = swiftFd
//         packetFlow.readPackets { [weak self] packets, protocols in
//             guard let self, self.running.value, self.swiftFd >= 0 else { return }
//             for (packet, proto) in zip(packets, protocols) {
//                 var header = CFSwapInt32HostToBig(proto.uint32Value)
//                 let ok: Bool = withUnsafeBytes(of: &header) { headerBuf in
//                     packet.withUnsafeBytes { packetBuf in
//                         guard let headerBase = headerBuf.baseAddress,
//                               let packetBase = packetBuf.baseAddress else { return false }
//                         return Self.writeAll(fd: fd, header: headerBase, packet: packetBase, packetCount: packet.count)
//                     }
//                 }
//                 if !ok {
//                     NSLog("❌ writev to xray failed: errno=\(errno) — stopping tunnel")
//                     TunnelDiagnostics.recordError(stage: "tunnel-io",
//                                                   message: "Lost connection to the tunnel engine (errno \(errno))")
//                     self.running.set(false)
//                     self.cancelTunnelWithError(NSError(domain: "PacketTunnel", code: 21,
//                         userInfo: [NSLocalizedDescriptionKey: "Tunnel I/O failed"]))
//                     return
//                 }
//             }
//             self.readFromPacketFlow()
//         }
//     }
//
//     /// recv ровно `count` байт. MSG_WAITALL может вернуть меньше при сигнале,
//     /// поэтому дочитываем в цикле. false = сокет закрыт/ошибка.
//     private static func readExactly(fd: Int32, into buf: UnsafeMutablePointer<UInt8>, count: Int) -> Bool {
//         var received = 0
//         while received < count {
//             let n = Darwin.recv(fd, buf + received, count - received, Int32(MSG_WAITALL))
//             if n > 0 {
//                 received += n
//             } else if n < 0 && errno == EINTR {
//                 continue
//             } else {
//                 return false
//             }
//         }
//         return true
//     }
//
//     /// Пишет [header][packet] целиком. Частичная запись в SOCK_STREAM
//     /// рассинхронизировала бы фрейминг, поэтому дописываем остаток вручную.
//     private static func writeAll(fd: Int32,
//                                  header: UnsafeRawPointer,
//                                  packet: UnsafeRawPointer,
//                                  packetCount: Int) -> Bool {
//         var iov = [
//             iovec(iov_base: UnsafeMutableRawPointer(mutating: header), iov_len: 4),
//             iovec(iov_base: UnsafeMutableRawPointer(mutating: packet), iov_len: packetCount)
//         ]
//         let total = 4 + packetCount
//         var written = 0
//
//         while written < total {
//             let n = Darwin.writev(fd, &iov, 2)
//             if n > 0 {
//                 written += n
//                 if written >= total { return true }
//                 // Сдвигаем iovec на количество уже записанных байт.
//                 var advance = n
//                 for i in 0..<iov.count where advance > 0 {
//                     let len = iov[i].iov_len
//                     if advance >= len {
//                         advance -= len
//                         iov[i].iov_len = 0
//                     } else {
//                         iov[i].iov_base = iov[i].iov_base?.advanced(by: advance)
//                         iov[i].iov_len = len - advance
//                         advance = 0
//                     }
//                 }
//             } else if n < 0 && (errno == EINTR || errno == EAGAIN) {
//                 continue
//             } else {
//                 return false
//             }
//         }
//         return true
//     }
//
//     //MARK: - JSON build
//     private static func buildXrayConfig(from shareLink: String,
//                                         resolvedEndpoints: [ServerEndpoint],
//                                         originalHost: String) throws -> String {
//         var outbound: [String: Any]
//         if shareLink.hasPrefix("vless://") {
//             outbound = try vlessOutbound(from: shareLink)
//         } else if shareLink.hasPrefix("vmess://") {
//             outbound = try vmessOutbound(from: shareLink)
//         } else if shareLink.hasPrefix("trojan://") {
//             outbound = try trojanOutbound(from: shareLink)
//         } else if shareLink.hasPrefix("ss://") {
//             outbound = try shadowsocksOutbound(from: shareLink)
//         } else {
//             throw NSError(domain: "PacketTunnel", code: 13,
//                 userInfo: [NSLocalizedDescriptionKey: "Unsupported share-link scheme: \(shareLink.prefix(20))"])
//         }
//
//         // Подставляем заранее отрезолвленный IP: изнутри туннеля DNS ещё
//         // недоступен, а домен нужен только для TLS/Reality SNI — он уже
//         // проставлен в streamSettings ниже.
//         if let ip = resolvedEndpoints.first?.address, !isIPAddress(originalHost) {
//             outbound = applyResolvedAddress(ip, originalHost: originalHost, to: outbound)
//         }
//
//         // Официальная схема tun-inbound (xtls.github.io/en/config/inbounds/tun.html)
//         // называет поле `mtu`, но в части сборок встречается `MTU`. Отдаём оба —
//         // неизвестные ключи в settings просто игнорируются, зато MTU гарантированно
//         // совпадёт с тем, что мы объявили системе.
//         let inbound: [String: Any] = [
//             "tag": "in_proxy",
//             "protocol": "tun",
//             "settings": [
//                 "name": "utun",
//                 "mtu": tunnelMTU,
//                 "MTU": tunnelMTU
//             ]
//         ]
//
//         let cfg: [String: Any] = [
//             "log": ["loglevel": "warning"],
//             "inbounds": [inbound],
//             "outbounds": [
//                 outbound,
//                 ["tag": "direct", "protocol": "freedom", "settings": ["domainStrategy": "UseIP"]],
//                 ["tag": "block",  "protocol": "blackhole"]
//             ]
//         ]
//
//         let bytes = try JSONSerialization.data(withJSONObject: cfg, options: [])
//         return String(data: bytes, encoding: .utf8) ?? "{}"
//     }
//
//     /// Меняет адрес сервера на IP и гарантирует, что SNI остался исходным доменом.
//     private static func applyResolvedAddress(_ ip: String,
//                                              originalHost: String,
//                                              to outbound: [String: Any]) -> [String: Any] {
//         var out = outbound
//         if var settings = out["settings"] as? [String: Any] {
//             if var vnext = settings["vnext"] as? [[String: Any]], !vnext.isEmpty {
//                 vnext[0]["address"] = ip
//                 settings["vnext"] = vnext
//             }
//             if var servers = settings["servers"] as? [[String: Any]], !servers.isEmpty {
//                 servers[0]["address"] = ip
//                 settings["servers"] = servers
//             }
//             out["settings"] = settings
//         }
//
//         if var stream = out["streamSettings"] as? [String: Any] {
//             let security = (stream["security"] as? String) ?? "none"
//             if security == "tls" {
//                 var tls = (stream["tlsSettings"] as? [String: Any]) ?? [:]
//                 if (tls["serverName"] as? String)?.isEmpty ?? true {
//                     tls["serverName"] = originalHost
//                 }
//                 stream["tlsSettings"] = tls
//             } else if security == "reality" {
//                 var reality = (stream["realitySettings"] as? [String: Any]) ?? [:]
//                 if (reality["serverName"] as? String)?.isEmpty ?? true {
//                     reality["serverName"] = originalHost
//                 }
//                 stream["realitySettings"] = reality
//             }
//             out["streamSettings"] = stream
//         }
//         return out
//     }
//
//     // vless://uuid@host:port?encryption=none&flow=xtls-rprx-vision&type=tcp&security=reality
//     //   &sni=...&fp=...&pbk=...&sid=...&spx=...#remark
//     private static func vlessOutbound(from url: String) throws -> [String: Any] {
//         guard let comp = URLComponents(string: url),
//               let uuid = comp.user,
//               let host = comp.host,
//               let port = comp.port else {
//             throw NSError(domain: "PacketTunnel", code: 14,
//                 userInfo: [NSLocalizedDescriptionKey: "Bad VLESS URL"])
//         }
//         let q: [String: String] = queryDict(comp)
//
//         // encryption ВСЕГДА "none" — единственное валидное значение для VLESS
//         // (шифрует Reality/TLS-слой, не сам VLESS). Что бы ни пришло в URL — форсим.
//         var user: [String: Any] = [
//             "id":         uuid,
//             "encryption": "none"
//         ]
//         if let flow = q["flow"], !flow.isEmpty { user["flow"] = flow }
//
//         let network = q["type"] ?? "tcp"
//         let security = q["security"] ?? "none"
//
//         var stream: [String: Any] = [
//             "network":  network,
//             "security": security
//         ]
//         switch security {
//         case "reality":
//             let r: [String: Any] = [
//                 "serverName":  q["sni"] ?? host,
//                 "fingerprint": q["fp"]  ?? "chrome",
//                 "publicKey":   q["pbk"] ?? "",
//                 "shortId":     q["sid"] ?? "",
//                 "spiderX":     q["spx"] ?? ""
//             ]
//             stream["realitySettings"] = r
//         case "tls":
//             var t: [String: Any] = ["serverName": q["sni"] ?? host]
//             if let v = q["fp"],   !v.isEmpty { t["fingerprint"] = v }
//             if let v = q["alpn"], !v.isEmpty {
//                 t["alpn"] = v.split(separator: ",").map(String.init)
//             }
//             if q["allowInsecure"] == "1" { t["allowInsecure"] = true }
//             stream["tlsSettings"] = t
//         default: break
//         }
//
//         applyTransport(network: network, query: q, host: host, to: &stream)
//
//         return [
//             "tag":      "proxy",
//             "protocol": "vless",
//             "settings": [
//                 "vnext": [[
//                     "address": host,
//                     "port":    port,
//                     "users":   [user]
//                 ]]
//             ],
//             "streamSettings": stream
//         ]
//     }
//
//     // vmess://base64(json {add,port,id,aid,net,type,host,path,tls,sni,scy,ps})
//     private static func vmessOutbound(from url: String) throws -> [String: Any] {
//         let b64 = String(url.dropFirst("vmess://".count))
//         guard let json = b64decode(b64),
//               let data = json.data(using: .utf8),
//               let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
//             throw NSError(domain: "PacketTunnel", code: 15,
//                 userInfo: [NSLocalizedDescriptionKey: "Bad VMess JSON"])
//         }
//         let host = (obj["add"] as? String) ?? ""
//         let port: Int = {
//             if let i = obj["port"] as? Int { return i }
//             if let s = obj["port"] as? String, let i = Int(s) { return i }
//             return 0
//         }()
//         guard !host.isEmpty, port > 0 else {
//             throw NSError(domain: "PacketTunnel", code: 15,
//                 userInfo: [NSLocalizedDescriptionKey: "VMess config has no address"])
//         }
//         let id  = (obj["id"]  as? String) ?? ""
//         let aid: Int = {
//             if let i = obj["aid"] as? Int { return i }
//             if let s = obj["aid"] as? String, let i = Int(s) { return i }
//             return 0
//         }()
//         let net = (obj["net"] as? String) ?? "tcp"
//         let tls = (obj["tls"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "none"
//         let scy = (obj["scy"] as? String) ?? "auto"
//
//         let userDict: [String: Any] = [
//             "id":       id,
//             "alterId":  aid,
//             "security": scy
//         ]
//         var stream: [String: Any] = ["network": net, "security": tls]
//         if tls == "tls" {
//             let sni = (obj["sni"] as? String).flatMap { $0.isEmpty ? nil : $0 }
//                 ?? (obj["host"] as? String).flatMap { $0.isEmpty ? nil : $0 }
//                 ?? host
//             stream["tlsSettings"] = ["serverName": sni]
//         }
//
//         var q: [String: String] = [:]
//         if let p = obj["path"] as? String, !p.isEmpty { q["path"] = p }
//         if let h = obj["host"] as? String, !h.isEmpty { q["host"] = h }
//         if let t = obj["type"] as? String, !t.isEmpty { q["headerType"] = t }
//         // gRPC-сервис в vmess-ссылке традиционно едет в поле path.
//         if net == "grpc", let p = obj["path"] as? String, !p.isEmpty { q["serviceName"] = p }
//         applyTransport(network: net, query: q, host: host, to: &stream)
//
//         return [
//             "tag":      "proxy",
//             "protocol": "vmess",
//             "settings": [
//                 "vnext": [[
//                     "address": host,
//                     "port":    port,
//                     "users":   [userDict]
//                 ]]
//             ],
//             "streamSettings": stream
//         ]
//     }
//
//     private static func trojanOutbound(from url: String) throws -> [String: Any] {
//         guard let comp = URLComponents(string: url),
//               let password = comp.user?.removingPercentEncoding,
//               let host = comp.host,
//               let port = comp.port else {
//             throw NSError(domain: "PacketTunnel", code: 16,
//                 userInfo: [NSLocalizedDescriptionKey: "Bad Trojan URL"])
//         }
//         let q: [String: String] = queryDict(comp)
//         let network = q["type"] ?? "tcp"
//         let security = q["security"] ?? "tls"
//         var stream: [String: Any] = ["network": network, "security": security]
//         if security == "tls" {
//             var t: [String: Any] = ["serverName": q["sni"] ?? host]
//             if let v = q["fp"],   !v.isEmpty { t["fingerprint"] = v }
//             if let v = q["alpn"], !v.isEmpty {
//                 t["alpn"] = v.split(separator: ",").map(String.init)
//             }
//             stream["tlsSettings"] = t
//         }
//         applyTransport(network: network, query: q, host: host, to: &stream)
//
//         return [
//             "tag":      "proxy",
//             "protocol": "trojan",
//             "settings": [
//                 "servers": [[
//                     "address":  host,
//                     "port":     port,
//                     "password": password
//                 ]]
//             ],
//             "streamSettings": stream
//         ]
//     }
//
//     // ss://method:password@host:port  OR  ss://base64(method:password)@host:port
//     private static func shadowsocksOutbound(from url: String) throws -> [String: Any] {
//         var method = ""
//         var password = ""
//         var host = ""
//         var port = 0
//         if let comp = URLComponents(string: url), let h = comp.host, let p = comp.port {
//             host = h; port = p
//             if let user = comp.user, let pass = comp.password {
//                 method = user.removingPercentEncoding ?? user
//                 password = pass.removingPercentEncoding ?? pass
//             } else if let user = comp.user {
//                 if let dec = b64decode(user), let colon = dec.firstIndex(of: ":") {
//                     method   = String(dec[..<colon])
//                     password = String(dec[dec.index(after: colon)...])
//                 }
//             }
//         }
//         if method.isEmpty || password.isEmpty || host.isEmpty || port == 0 {
//             let raw = String(url.dropFirst("ss://".count))
//             guard let atIdx = raw.firstIndex(of: "@") else {
//                 throw NSError(domain: "PacketTunnel", code: 17,
//                     userInfo: [NSLocalizedDescriptionKey: "Bad SS URL"])
//             }
//             let userPart = String(raw[..<atIdx])
//             let hostPart = String(raw[raw.index(after: atIdx)...])
//                 .components(separatedBy: "#").first?
//                 .components(separatedBy: "?").first ?? ""
//             if let dec = b64decode(userPart), let colon = dec.firstIndex(of: ":") {
//                 method   = String(dec[..<colon])
//                 password = String(dec[dec.index(after: colon)...])
//             }
//             if let colon = hostPart.lastIndex(of: ":") {
//                 host = String(hostPart[..<colon])
//                 if let p = Int(hostPart[hostPart.index(after: colon)...]) { port = p }
//             }
//         }
//         guard !method.isEmpty, !password.isEmpty, !host.isEmpty, port > 0 else {
//             throw NSError(domain: "PacketTunnel", code: 18,
//                 userInfo: [NSLocalizedDescriptionKey: "Bad SS components"])
//         }
//         return [
//             "tag":      "proxy",
//             "protocol": "shadowsocks",
//             "settings": [
//                 "servers": [[
//                     "address":  host,
//                     "port":     port,
//                     "method":   method,
//                     "password": password
//                 ]]
//             ]
//         ]
//     }
//
//     /// ws / grpc / httpupgrade транспорты — общие для vless / vmess / trojan.
//     private static func applyTransport(network: String,
//                                        query q: [String: String],
//                                        host: String,
//                                        to stream: inout [String: Any]) {
//         switch network {
//         case "ws":
//             var ws: [String: Any] = [:]
//             ws["path"] = (q["path"]?.isEmpty == false) ? q["path"]! : "/"
//             if let v = q["host"], !v.isEmpty { ws["headers"] = ["Host": v] }
//             stream["wsSettings"] = ws
//         case "httpupgrade":
//             var hu: [String: Any] = [:]
//             hu["path"] = (q["path"]?.isEmpty == false) ? q["path"]! : "/"
//             hu["host"] = (q["host"]?.isEmpty == false) ? q["host"]! : host
//             stream["httpupgradeSettings"] = hu
//         case "grpc":
//             var g: [String: Any] = [:]
//             let service = q["serviceName"] ?? q["path"] ?? ""
//             if !service.isEmpty { g["serviceName"] = service }
//             if q["mode"] == "multi" { g["multiMode"] = true }
//             stream["grpcSettings"] = g
//         case "tcp":
//             if q["headerType"] == "http" {
//                 var header: [String: Any] = ["type": "http"]
//                 if let h = q["host"], !h.isEmpty {
//                     header["request"] = ["headers": ["Host": h.split(separator: ",").map(String.init)]]
//                 }
//                 stream["tcpSettings"] = ["header": header]
//             }
//         default:
//             break
//         }
//     }
//
//     //MARK: - Helpers
//     private static func queryDict(_ comp: URLComponents) -> [String: String] {
//         var d: [String: String] = [:]
//         comp.queryItems?.forEach { if let v = $0.value { d[$0.name] = v } }
//         return d
//     }
//
//     private static func isIPAddress(_ s: String) -> Bool {
//         var sin = sockaddr_in()
//         if s.withCString({ inet_pton(AF_INET, $0, &sin.sin_addr) }) == 1 { return true }
//         var sin6 = sockaddr_in6()
//         if s.withCString({ inet_pton(AF_INET6, $0, &sin6.sin6_addr) }) == 1 { return true }
//         return false
//     }
//
//     struct ServerEndpoint: CustomStringConvertible {
//         let address: String
//         let isIPv6: Bool
//         var description: String { address }
//     }
//
//     /// Синхронный резолв через getaddrinfo. IPv4 идёт первым — xray-outbound
//     /// использует именно его, IPv6 нужен только чтобы исключить его из маршрутов.
//     private static func resolve(host: String) -> [ServerEndpoint] {
//         guard !host.isEmpty else { return [] }
//         if isIPAddress(host) {
//             return [ServerEndpoint(address: host, isIPv6: host.contains(":"))]
//         }
//
//         var hints = addrinfo(
//             ai_flags: 0,
//             ai_family: AF_UNSPEC,
//             ai_socktype: SOCK_STREAM,
//             ai_protocol: IPPROTO_TCP,
//             ai_addrlen: 0,
//             ai_canonname: nil,
//             ai_addr: nil,
//             ai_next: nil
//         )
//         var info: UnsafeMutablePointer<addrinfo>?
//         guard getaddrinfo(host, nil, &hints, &info) == 0, let first = info else { return [] }
//         defer { freeaddrinfo(info) }
//
//         var v4: [ServerEndpoint] = []
//         var v6: [ServerEndpoint] = []
//         var cursor: UnsafeMutablePointer<addrinfo>? = first
//         var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
//
//         while let node = cursor {
//             if getnameinfo(node.pointee.ai_addr, node.pointee.ai_addrlen,
//                            &buffer, socklen_t(buffer.count),
//                            nil, 0, NI_NUMERICHOST) == 0 {
//                 let address = String(cString: buffer)
//                 if !address.isEmpty {
//                     if node.pointee.ai_family == AF_INET6 {
//                         v6.append(ServerEndpoint(address: address, isIPv6: true))
//                     } else {
//                         v4.append(ServerEndpoint(address: address, isIPv6: false))
//                     }
//                 }
//             }
//             cursor = node.pointee.ai_next
//         }
//         return v4 + v6
//     }
//
//     private static func b64decode(_ s: String) -> String? {
//         var padded = s.replacingOccurrences(of: "-", with: "+")
//                       .replacingOccurrences(of: "_", with: "/")
//         while padded.count % 4 != 0 { padded.append("=") }
//         guard let data = Data(base64Encoded: padded, options: .ignoreUnknownCharacters),
//               let str = String(data: data, encoding: .utf8) else { return nil }
//         return str
//     }
//
//     // libXray response = base64({"success":bool,"data":...,"err":"..."})
//     private static func errorFromLibXrayResponse(_ b64: String) -> NSError? {
//         guard let obj = decodeResponse(b64) else {
//             return NSError(domain: "libXray", code: 100,
//                 userInfo: [NSLocalizedDescriptionKey: "couldn't decode response: \(b64.prefix(200))"])
//         }
//         if (obj["success"] as? Bool) == true { return nil }
//         // libXray в разных билдах кладёт текст ошибки то в "err", то в "error", то в "data"
//         let candidates: [String?] = [
//             obj["error"]   as? String,
//             obj["err"]     as? String,
//             obj["message"] as? String,
//             obj["data"]    as? String
//         ]
//         let msg = candidates.compactMap { $0 }.first(where: { !$0.isEmpty })
//             ?? "libXray failed (raw: \(b64.prefix(400)))"
//         return NSError(domain: "libXray", code: 100,
//             userInfo: [NSLocalizedDescriptionKey: msg])
//     }
//
//     private static func decodeResponse(_ b64: String) -> [String: Any]? {
//         guard let raw = b64decode(b64)?.data(using: .utf8),
//               let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return nil }
//         return obj
//     }
//
//     //MARK: - Network settings
//     private static func makeSettings(serverEndpoints: [ServerEndpoint]) -> NEPacketTunnelNetworkSettings {
//         // iOS требует IP в tunnelRemoteAddress. Hostnames отвергаются.
//         let remote = serverEndpoints.first(where: { !$0.isIPv6 })?.address
//             ?? serverEndpoints.first?.address
//             ?? "127.0.0.1"
//         let s = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remote)
//         s.mtu = NSNumber(value: tunnelMTU)
//
//         //MARK: IPv4
//         let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
//         ipv4.includedRoutes = [NEIPv4Route.default()]
//         // Исключаем LAN — домашние роутеры/принтеры/AirPlay остаются доступны.
//         var excludedV4 = [
//             NEIPv4Route(destinationAddress: "10.0.0.0",    subnetMask: "255.0.0.0"),
//             NEIPv4Route(destinationAddress: "172.16.0.0",  subnetMask: "255.240.0.0"),
//             NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0")
//         ]
//         // И сам VPN-сервер: иначе соединение xray → сервер зациклится на туннеле.
//         for endpoint in serverEndpoints where !endpoint.isIPv6 {
//             excludedV4.append(NEIPv4Route(destinationAddress: endpoint.address,
//                                           subnetMask: "255.255.255.255"))
//         }
//         ipv4.excludedRoutes = excludedV4
//         s.ipv4Settings = ipv4
//
//         //MARK: IPv6
//         // Без этого весь IPv6-трафик идёт мимо туннеля с реальным адресом.
//         let ipv6 = NEIPv6Settings(addresses: ["fd6e:a81b:704f:1211::1"], networkPrefixLengths: [64])
//         ipv6.includedRoutes = [NEIPv6Route.default()]
//         var excludedV6: [NEIPv6Route] = []
//         for endpoint in serverEndpoints where endpoint.isIPv6 {
//             excludedV6.append(NEIPv6Route(destinationAddress: endpoint.address,
//                                           networkPrefixLength: 128))
//         }
//         ipv6.excludedRoutes = excludedV6
//         s.ipv6Settings = ipv6
//
//         //MARK: DNS
//         // Берём провайдера, выбранного юзером в Privacy Center. Раньше здесь
//         // всегда стояли 1.1.1.1/8.8.8.8, из-за чего выбор DNS в приложении
//         // при активном туннеле не имел никакого эффекта.
//         let shared = UserDefaults(suiteName: PTConstants.appGroup)
//         let providerRaw = shared?.string(forKey: PTConstants.UDKeys.dnsProvider) ?? "off"
//         let servers = PTConstants.dnsServers(for: providerRaw)
//         let dns = NEDNSSettings(servers: servers.isEmpty ? PTConstants.defaultDNSServers : servers)
//         dns.matchDomains = [""]
//         s.dnsSettings = dns
//         return s
//     }
// }
//
// /// Потокобезопасный флаг: пишется на очереди NE, читается из detached-потока.
// final class AtomicFlag {
//     private var storage: Bool
//     private let lock = NSLock()
//
//     init(_ initial: Bool) { storage = initial }
//
//     var value: Bool {
//         lock.lock(); defer { lock.unlock() }
//         return storage
//     }
//
//     func set(_ newValue: Bool) {
//         lock.lock(); storage = newValue; lock.unlock()
//     }
// }
//