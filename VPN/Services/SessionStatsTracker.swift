import Foundation
import Darwin

/// Кумулятивная статистика активной VPN-сессии: суммарно скачано/выгружено байт
/// через `utun*` (наш тоннель) + HTTP-latency до публичного эндпоинта.
@Observable
@MainActor
final class SessionStatsTracker {
    @ObservationIgnored static let shared = SessionStatsTracker()

    private(set) var sessionDownloadBytes: UInt64 = 0
    private(set) var sessionUploadBytes:   UInt64 = 0
    private(set) var latencyMs: Int? = nil
    private(set) var isRunning: Bool = false

    @ObservationIgnored private var initialDown: UInt64 = 0
    @ObservationIgnored private var initialUp:   UInt64 = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tickCount: Int = 0
    @ObservationIgnored private var isMeasuringPing = false

    private init() {}

    //MARK: - Lifecycle
    func start() {
        guard !isRunning else { return }
        let (d, u) = Self.byteCounts()
        initialDown = d
        initialUp   = u
        sessionDownloadBytes = 0
        sessionUploadBytes   = 0
        latencyMs            = nil
        tickCount = 0
        isRunning = true

        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Первый замер пинга через 1.5с — чтобы тоннель успел устаканиться.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.measurePing()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        sessionDownloadBytes = 0
        sessionUploadBytes   = 0
        latencyMs            = nil
        tickCount = 0
    }

    //MARK: - Tick
    private func tick() {
        let (d, u) = Self.byteCounts()
        sessionDownloadBytes = d >= initialDown ? d - initialDown : 0
        sessionUploadBytes   = u >= initialUp   ? u - initialUp   : 0

        tickCount += 1
        if tickCount % 10 == 0 {
            measurePing()
        }
    }

    //MARK: - Ping (HTTP-latency через тоннель)
    private func measurePing() {
        guard !isMeasuringPing else { return }
        isMeasuringPing = true
        Task { [weak self] in
            let ms = await Self.measureLatency()
            await MainActor.run {
                self?.latencyMs = ms
                self?.isMeasuringPing = false
            }
        }
    }

    private static func measureLatency() async -> Int? {
        guard let url = URL(string: "https://api.ipify.org/?format=json") else { return nil }
        var req = URLRequest(url: url,
                             cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                             timeoutInterval: 5)
        req.httpMethod = "HEAD"
        let session = URLSession(configuration: .ephemeral)
        let start = Date()
        do {
            _ = try await session.data(for: req)
            let elapsed = Date().timeIntervalSince(start) * 1000
            return Int(elapsed)
        } catch {
            return nil
        }
    }

    //MARK: - Interface byte counters
    /// Сумма rx/tx по всем `utun*` интерфейсам (наш VPN-тоннель — один из них).
    private static func byteCounts() -> (down: UInt64, up: UInt64) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return (0, 0) }
        defer { freeifaddrs(ifaddrPtr) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let name = String(cString: cur.pointee.ifa_name)
            if let addr = cur.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               name.hasPrefix("utun") {
                if let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    rx &+= UInt64(data.pointee.ifi_ibytes)
                    tx &+= UInt64(data.pointee.ifi_obytes)
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return (rx, tx)
    }
}
