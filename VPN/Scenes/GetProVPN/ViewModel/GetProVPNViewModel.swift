import SwiftUI

@MainActor
@Observable
final class GetProVPNViewModel {

    // MARK: - Sub-screen presentation flags
    var showServerList: Bool = false

    // MARK: - Ping measurement state
    var isMeasuringPings: Bool = false

    // MARK: - Fastest-server mode (persisted flag)
    @ObservationIgnored private let fastestModeKey = "getprovpn.useFastestServer"
    var isFastestModeActive: Bool = UserDefaults.standard.bool(forKey: "getprovpn.useFastestServer") {
        didSet {
            UserDefaults.standard.set(isFastestModeActive, forKey: fastestModeKey)
        }
    }

    // MARK: - Dependencies (reactive via @Observable)
    @ObservationIgnored private let subscriptionProvider = SubscriptionProvider.shared
    @ObservationIgnored private let speedTracker = SpeedTracker.shared
    @ObservationIgnored private let statsTracker = SessionStatsTracker.shared

    // MARK: - Connection state
    var connectionStatus: ConnectionStatus { VPNService.shared.status }
    var sessionStartedAt: Date? { VPNService.shared.sessionStartedAt }
    /// Показывать в GetProVPN только те сервера, что пришли из подписочного пула
    /// (иначе если юзер выбрал кастомный на OwnServers, он бы протёк сюда).
    var currentServer: VPNServerConfig? {
        guard let server = VPNService.shared.currentServer else { return nil }
        guard SubscriptionProvider.shared.servers.contains(where: { $0.rawURL == server.rawURL }) else { return nil }
        return server
    }
    var currentPingMs: Int? { VPNService.shared.currentPingMs }

    var connectionState: VPNConnectionState {
        switch VPNService.shared.status {
        case .connected:  return .connected
        case .connecting: return .connecting
        default:          return .disconnected
        }
    }

    // MARK: - Speeds (KB/s from Mbps)
    var downloadKBps: Double? {
        guard VPNService.shared.status.isActive else { return nil }
        return SpeedTracker.shared.downloadMbps * 125
    }
    var uploadKBps: Double? {
        guard VPNService.shared.status.isActive else { return nil }
        return SpeedTracker.shared.uploadMbps * 125
    }

    // MARK: - Server list from backend
    var servers: [VPNServerConfig] { SubscriptionProvider.shared.servers }
    var isLoadingServers: Bool { SubscriptionProvider.shared.isLoading }
    /// Причина, по которой список пуст: нет subscription_url, HTTP-ошибка панели
    /// или сеть. Без этого экран молча показывал бы пустоту.
    var loadError: String? { SubscriptionProvider.shared.lastError }

    /// Один сервер на страну (первый из пула). Для отображения flat-списком в ServerListView.
    var serversPerCountry: [VPNServerConfig] {
        var seen = Set<String>()
        var result: [VPNServerConfig] = []
        for server in SubscriptionProvider.shared.servers {
            let key = server.countryCode?.uppercased() ?? server.host
            if seen.insert(key).inserted { result.append(server) }
        }
        return result
    }

    /// «Fastest server» — с наименьшим ping'ом из закешированных.
    var fastestServer: VPNServerConfig? {
        SubscriptionProvider.shared.servers.min { a, b in
            let ap = PingCache.shared.ping(for:a.rawURL) ?? Int.max
            let bp = PingCache.shared.ping(for:b.rawURL) ?? Int.max
            return ap < bp
        }
    }

    /// Пинг из кеша для отображения в строке.
    func ping(for server: VPNServerConfig) -> Int? {
        PingCache.shared.ping(for:server.rawURL)
    }

    var isFastestSelected: Bool { isFastestModeActive }

    func selectFastestServer() {
        guard let fastest = fastestServer, !VPNService.shared.status.isActive else { return }
        isFastestModeActive = true
        VPNService.shared.selectServer(fastest)
    }

    func measurePings(force: Bool = false) {
        guard !isMeasuringPings else { return }
        Task {
            isMeasuringPings = true
            if force { PingCache.shared.clear() }
            await PingCache.shared.measureAll(SubscriptionProvider.shared.servers, force: force)
            isMeasuringPings = false
        }
    }

    // MARK: - Actions
    func toggleVPN() {
        if VPNService.shared.status.isActive || VPNService.shared.status == .connecting {
            VPNService.shared.disconnect()
        } else {
            // VPNService.connect() внутри сам возьмёт первый сервер из подписки
            // если currentServer не задан.
            Task { await VPNService.shared.connect() }
        }
    }

    /// Перезагрузка списка серверов. Дёргается при открытии экрана и кнопкой
    /// «Try again».
    ///
    /// Если subscription_url ещё не получен (единственный register на старте
    /// приложения не прошёл — не было сети, бэк холодно стартовал), одного GET'а
    /// подписки мало: URL'а просто нет и не появится до перезапуска. Поэтому
    /// сначала переспрашиваем бэк и только потом качаем список.
    func refreshServers() {
        guard SubscriptionProvider.shared.hasSubscriptionURL else {
            Task {
                SubscriptionProvider.shared.markBackendRetryStarted()
                if await SubscriptionService.shared.retryBackendRegistration() {
                    SubscriptionProvider.shared.refresh()
                } else {
                    SubscriptionProvider.shared.markBackendRetryFailed()
                }
                measurePings()
            }
            return
        }

        SubscriptionProvider.shared.refresh()
        // Пинги меряем по мере появления серверов — см. .task в ServerListView.
        measurePings()
    }

    func selectServer(_ server: VPNServerConfig) {
        guard !VPNService.shared.status.isActive else { return }
        isFastestModeActive = false
        VPNService.shared.selectServer(server)
    }

    // MARK: - Timer helpers
    func elapsedSeconds(now: Date = .now) -> Int {
        guard let start = VPNService.shared.sessionStartedAt else { return 0 }
        return max(0, Int(now.timeIntervalSince(start)))
    }

    func elapsedText(now: Date = .now) -> String {
        let s = elapsedSeconds(now: now)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
