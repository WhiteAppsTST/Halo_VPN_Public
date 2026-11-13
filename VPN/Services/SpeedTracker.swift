import Foundation
import Darwin

/// Считает download/upload дельту байт раз в секунду через getifaddrs.
/// Только `utun*` — это трафик самого туннеля; складывать сюда `en*`/`pdp_ip*`
/// означало показывать в качестве «скорости VPN» весь трафик устройства.
@Observable
final class SpeedTracker {
    @ObservationIgnored static let shared = SpeedTracker()

    private(set) var downloadMbps: Double = 0
    private(set) var uploadMbps: Double = 0

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastRx: UInt64 = 0
    @ObservationIgnored private var lastTx: UInt64 = 0
    @ObservationIgnored private var lastTick: Date = .distantPast

    private init() {}

    func start() {
        stop()
        lastTick = Date()
        let (rx, tx) = Self.byteCounts()
        lastRx = rx
        lastTx = tx
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        downloadMbps = 0
        uploadMbps = 0
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        let (rx, tx) = Self.byteCounts()
        let drx = rx >= lastRx ? rx - lastRx : 0
        let dtx = tx >= lastTx ? tx - lastTx : 0
        lastRx = rx
        lastTx = tx
        let bitsRx = Double(drx) * 8
        let bitsTx = Double(dtx) * 8
        let mbpsRx = (bitsRx / dt) / 1_000_000
        let mbpsTx = (bitsTx / dt) / 1_000_000
        downloadMbps = max(0, mbpsRx)
        uploadMbps   = max(0, mbpsTx)
    }

    private static func byteCounts() -> (UInt64, UInt64) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return (0, 0) }
        defer { freeifaddrs(ifaddrPtr) }
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let name = String(cString: cur.pointee.ifa_name)
            // ifa_addr бывает NULL у интерфейсов без адреса — разыменование роняло приложение.
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
