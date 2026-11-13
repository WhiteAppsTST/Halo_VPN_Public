import Foundation
import Network
import Darwin

/// TCP-connect ping до host:port. ICMP на iOS требует entitlement, поэтому
/// меряем время до `NWConnection` state = .ready — так делают V2RayNG,
/// Streisand и прочие живые клиенты.
///
/// Важное отличие от наивной реализации: DNS резолвим ОТДЕЛЬНО и в замер не
/// включаем, а из нескольких проб берём минимум. Раньше в «пинг» попадали
/// резолв домена и разгон при восьми параллельных пробах — числа выходили
/// втрое больше реальных (193 мс до Нидерландов превращались в 700).
enum PingService {

    /// `probes` подряд, возвращается лучший результат. nil — хост недоступен.
    static func measure(host: String, port: Int, timeout: TimeInterval = 3.0, probes: Int = 3) async -> Int? {
        guard let port16 = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }

        // Резолвим один раз и дальше коннектимся к литералу IP — иначе каждая
        // проба тянула бы за собой DNS.
        guard let ip = await resolveFirstIPv4(host) else { return nil }

        var best: Int?
        for _ in 0..<probes {
            if Task.isCancelled { break }
            guard let ms = await connectOnce(ip: ip, port: port16, timeout: timeout) else { continue }
            best = min(best ?? ms, ms)
        }
        return best
    }

    private static func connectOnce(ip: String, port: NWEndpoint.Port, timeout: TimeInterval) async -> Int? {
        let params = NWParameters.tcp
        // Быстрый отказ вместо долгих ретраев — нам нужна задержка, а не упорство.
        params.prohibitedInterfaceTypes = []
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: port, using: params)

        return await withCheckedContinuation { continuation in
            let start = DispatchTime.now()
            let didFinish = AtomicBool(false)

            let finish: (Int?) -> Void = { result in
                guard didFinish.setIfFalse() else { return }
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                    finish(Int(ns / 1_000_000))
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
        }
    }

    /// getaddrinfo блокирующий — уводим с текущего потока.
    private static func resolveFirstIPv4(_ host: String) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            var hints = addrinfo(
                ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM,
                ai_protocol: IPPROTO_TCP, ai_addrlen: 0,
                ai_canonname: nil, ai_addr: nil, ai_next: nil
            )
            var info: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &info) == 0, let first = info else { return nil }
            defer { freeaddrinfo(info) }

            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(first.pointee.ai_addr, first.pointee.ai_addrlen,
                              &buffer, socklen_t(buffer.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { return nil }
            let address = String(cString: buffer)
            return address.isEmpty ? nil : address
        }.value
    }
}

private final class AtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ initial: Bool) { self.value = initial }

    func setIfFalse() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard value == false else { return false }
        value = true
        return true
    }
}
