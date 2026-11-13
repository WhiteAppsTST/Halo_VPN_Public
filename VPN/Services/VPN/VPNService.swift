import Foundation
@preconcurrency import NetworkExtension

@Observable
@MainActor
final class VPNService {
    @ObservationIgnored static let shared = VPNService()

    private(set) var status: ConnectionStatus = .disconnected
    private(set) var sessionStartedAt: Date?
    private(set) var currentCountry: VPNCountry = .defaultCountry
    private(set) var currentServer: VPNServerConfig? {
        didSet {
            guard currentServer?.id != oldValue?.id else { return }
            currentPingMs = nil
            if let server = currentServer {
                measurePing(for: server)
            }
        }
    }
    /// Latency последнего измерения для currentServer.
    private(set) var currentPingMs: Int?

    /// true на симуляторе: NetworkExtension там не существует, туннель поднять
    /// физически нельзя. UI показывает это честным сообщением вместо фейкового
    /// «Connected».
    static var isTunnelSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    @ObservationIgnored private var manager: NETunnelProviderManager?
    @ObservationIgnored private var statusObserver: NSObjectProtocol?
    @ObservationIgnored private var killSwitchWatchdog: Task<Void, Never>?
    @ObservationIgnored private let serverProvider: SubscriptionProvider = .shared

    private init() {}

    //MARK: - Setup
    func prepare() async {
        // Восстанавливаем ранее выбранный сервер по persisted rawURL (стабильный
        // ключ между refresh'ами subscription).
        restoreSelectedServer()
        alignDefaultCountryToAvailable()

        guard Self.isTunnelSupported else { return }

        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let m = managers.first {
                self.manager = m
                subscribeStatus(m)
                // Активную сессию НЕ рвём: юзер мог включить VPN раньше или
                // его подняли on-demand правила. Просто подхватываем статус.
                syncStatus(from: m.connection.status)
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func subscribeStatus(_ m: NETunnelProviderManager) {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: m.connection,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncStatus(from: m.connection.status)
            }
        }
    }

    private func syncStatus(from sysStatus: NEVPNStatus) {
        switch sysStatus {
        case .invalid, .disconnected:
            if let diag = TunnelDiagnostics.readLastError() {
                status = .failed(Self.friendlyMessage(forStage: diag.stage, message: diag.message))
                TunnelDiagnostics.clear()
            } else {
                status = .disconnected
            }
        case .connecting:    status = .connecting
        case .connected:     status = .connected
        case .disconnecting: status = .disconnecting
        case .reasserting:   status = .connecting
        @unknown default:    status = .disconnected
        }
        if status.isActive {
            killSwitchWatchdog?.cancel()
            killSwitchWatchdog = nil
            if sessionStartedAt == nil { sessionStartedAt = Date() }
            SpeedTracker.shared.start()
            SessionStatsTracker.shared.start()
        } else {
            sessionStartedAt = nil
            SpeedTracker.shared.stop()
            SessionStatsTracker.shared.stop()
        }
    }

    //MARK: - Ping
    private func measurePing(for server: VPNServerConfig) {
        Task { [weak self] in
            let ms = await PingService.measure(host: server.host, port: server.port)
            guard let self, self.currentServer?.id == server.id else { return }
            self.currentPingMs = ms
        }
    }

    //MARK: - Public API
    func selectCountry(_ country: VPNCountry) {
        currentCountry = country
        if let s = currentServer, s.countryCode?.uppercased() != country.iso {
            currentServer = nil
        }
    }

    func selectServer(_ server: VPNServerConfig) {
        currentServer = server
        if let iso = server.countryCode?.uppercased(),
           let match = VPNCountry.allCases.first(where: { $0.iso == iso }) {
            currentCountry = match
        }
        UserDefaults.standard.set(server.rawURL, forKey: AppConstants.UDKeys.selectedServerRawURL)
    }

    /// Сбрасывает выбор — например, когда выбранный сервер удалили.
    func clearSelection() {
        currentServer = nil
        UserDefaults.standard.removeObject(forKey: AppConstants.UDKeys.selectedServerRawURL)
    }

    /// Все доступные сервера: подписка + пользовательские папки.
    var availableServers: [VPNServerConfig] {
        serverProvider.servers
            + CustomServerFoldersStore.shared.folders.flatMap(\.servers)
    }

    /// Читает persisted rawURL из UD и находит соответствующий сервер в pools.
    private func restoreSelectedServer() {
        guard let raw = UserDefaults.standard.string(forKey: AppConstants.UDKeys.selectedServerRawURL) else { return }
        if let match = availableServers.first(where: { $0.rawURL == raw }) {
            currentServer = match
            if let iso = match.countryCode?.uppercased(),
               let country = VPNCountry.allCases.first(where: { $0.iso == iso }) {
                currentCountry = country
            }
        }
    }

    /// После загрузки/обновления подписки: если ничего не выбрано или выбранный
    /// сервер исчез из ВСЕХ пулов — берём первый доступный. Собственные конфиги
    /// пользователя при этом не затираются (раньше сверялись только с подпиской).
    func alignDefaultCountryToAvailable() {
        let pool = availableServers
        guard !pool.isEmpty else { return }

        if currentServer == nil {
            currentServer = pool.first
        } else if let s = currentServer, !pool.contains(where: { $0.rawURL == s.rawURL }) {
            currentServer = pool.first
        }

        if let iso = currentServer?.countryCode?.uppercased(),
           let match = VPNCountry.allCases.first(where: { $0.iso == iso }) {
            currentCountry = match
        }
    }

    func toggleConnection() {
        switch status {
        case .connected:
            disconnect()
        case .disconnected, .failed:
            Task { await connect() }
        case .connecting, .disconnecting:
            break
        }
    }

    func connect() async {
        guard Self.isTunnelSupported else {
            status = .failed(String(localized: "The VPN tunnel needs a real device — iOS Simulator has no Network Extension support."))
            return
        }

        let chosen: VPNServerConfig? = currentServer ?? availableServers.first
        guard let server = chosen else {
            status = .failed(String(localized: "No server selected. Add a configuration first."))
            return
        }

        currentServer = server
        status = .connecting
        TunnelDiagnostics.clear()
        do {
            let m = try await ensureManager(for: server)
            try m.connection.startVPNTunnel()
            armKillSwitchWatchdogIfNeeded()
        } catch let nsErr as NSError {
            status = .failed(Self.friendlyMessage(for: nsErr))
        }
    }

    /// `includeAllNetworks` на части устройств/версий iOS глушит исходящие сокеты
    /// самого tunnel-расширения — а именно ими xray и ходит на сервер. Тогда
    /// туннель не поднимается вообще, и причина совершенно неочевидна.
    /// Сторожевой таймер ловит этот случай, снимает Kill Switch и объясняет,
    /// что произошло, вместо вечного «Connecting…».
    /// См. developer.apple.com/forums/thread/653116 и mullvad.net/blog/why-we-still-dont-use-includeallnetworks
    private func armKillSwitchWatchdogIfNeeded() {
        killSwitchWatchdog?.cancel()
        guard AppPreferencesStore.shared.killSwitchEnabled else { return }

        killSwitchWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard AppPreferencesStore.shared.killSwitchEnabled else { return }
            // Успели подключиться — всё в порядке.
            if case .connected = self.status { return }
            // Пользователь сам отключил — не вмешиваемся.
            if case .disconnected = self.status { return }

            self.disconnect()
            AppPreferencesStore.shared.killSwitchEnabled = false
            await self.applyKillSwitchPreference()
            self.status = .failed(String(localized: "Kill Switch blocked the connection on this device, so it has been turned off. Tap Connect again."))
        }
    }

    func disconnect() {
        killSwitchWatchdog?.cancel()
        killSwitchWatchdog = nil
        manager?.connection.stopVPNTunnel()
    }

    /// Полное удаление профиля из системы.
    func removeConfiguration() async {
        guard Self.isTunnelSupported else { return }
        do {
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            for m in all {
                m.connection.stopVPNTunnel()
                try? await m.removeFromPreferences()
            }
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
            statusObserver = nil
        }
        manager = nil
        currentServer = nil
        currentCountry = .defaultCountry
        sessionStartedAt = nil
        status = .disconnected
    }

    //MARK: - Manager config
    private func ensureManager(for server: VPNServerConfig) async throws -> NETunnelProviderManager {
        let m = try await fetchOrCreateManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppConstants.Bundle.packetTunnel
        proto.serverAddress = server.host
        proto.providerConfiguration = [
            "rawURL":     server.rawURL,
            "kind":       server.kind.rawValue,
            "remark":     server.remark,
            "host":       server.host,
            "port":       server.port,
            "countryISO": server.countryCode ?? "",
            "appGroup":   AppConstants.Bundle.appGroup
        ]
        proto.disconnectOnSleep = false
        // Kill switch: при разрыве VPN весь трафик блокируется.
        proto.includeAllNetworks = AppPreferencesStore.shared.killSwitchEnabled
        // При includeAllNetworks система игнорирует excludedRoutes, поэтому LAN
        // (AirPlay, принтеры, роутер) исключается отдельным флагом — иначе
        // локальная сеть отваливается вместе со всем остальным.
        proto.excludeLocalNetworks = true
        m.protocolConfiguration = proto
        m.localizedDescription  = "VPN — \(server.remark.isEmpty ? currentCountry.title : server.remark)"
        m.isEnabled = true

        Self.applyOnDemand(to: m, enabled: AppPreferencesStore.shared.autoConnectEnabled)

        try await m.saveToPreferences()
        try await m.loadFromPreferences()
        subscribeStatus(m)
        self.manager = m
        return m
    }

    private func fetchOrCreateManager() async throws -> NETunnelProviderManager {
        let all = try await NETunnelProviderManager.loadAllFromPreferences()
        return all.first ?? NETunnelProviderManager()
    }

    /// Применяет Auto-Connect к сохранённому в системе профилю.
    func applyAutoConnectPreference() async {
        guard Self.isTunnelSupported else { return }
        let enabled = AppPreferencesStore.shared.autoConnectEnabled
        do {
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            guard let m = all.first else { return }
            Self.applyOnDemand(to: m, enabled: enabled)
            try await m.saveToPreferences()
        } catch {
            print("[VPNService] applyAutoConnectPreference failed:", error.localizedDescription)
        }
    }

    /// Kill switch раньше попадал в профиль только при следующем connect —
    /// переключатель во время активной сессии ничего не делал. Теперь пишем сразу.
    func applyKillSwitchPreference() async {
        guard Self.isTunnelSupported else { return }
        let enabled = AppPreferencesStore.shared.killSwitchEnabled
        do {
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            guard let m = all.first,
                  let proto = m.protocolConfiguration as? NETunnelProviderProtocol else { return }
            proto.includeAllNetworks = enabled
            m.protocolConfiguration = proto
            try await m.saveToPreferences()
        } catch {
            print("[VPNService] applyKillSwitchPreference failed:", error.localizedDescription)
        }
    }

    /// DNS применяется внутри туннеля, поэтому смену провайдера нужно донести
    /// до расширения — простейший способ переподнять настройки — reconnect.
    func reapplyTunnelSettingsIfConnected() async {
        guard Self.isTunnelSupported, status.isActive else { return }
        disconnect()
        try? await Task.sleep(nanoseconds: 700_000_000)
        await connect()
    }

    private static func applyOnDemand(to m: NETunnelProviderManager, enabled: Bool) {
        if enabled {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            m.onDemandRules = [rule]
            m.isOnDemandEnabled = true
        } else {
            m.onDemandRules = []
            m.isOnDemandEnabled = false
        }
    }

    //MARK: - Error text
    private static func friendlyMessage(for err: NSError) -> String {
        if err.domain == NEVPNErrorDomain {
            switch err.code {
            case 1: return String(localized: "VPN configuration invalid. Reinstall the app.")
            case 2: return String(localized: "VPN configuration disabled. Open Settings → General → VPN.")
            case 3: return String(localized: "VPN couldn't reach the server. Try another configuration.")
            case 4: return String(localized: "VPN configuration is stale. Tap Connect again.")
            case 5: return String(localized: "Couldn't save VPN configuration. Allow VPN permission in the system dialog.")
            default: break
            }
        }
        if err.localizedDescription.lowercased().contains("permission") {
            return String(localized: "VPN permission denied. Allow the VPN profile when the system dialog appears.")
        }
        return err.localizedDescription
    }

    /// Человеческий текст по стадии, на которой упало расширение.
    private static func friendlyMessage(forStage stage: String, message: String) -> String {
        switch stage {
        case "dns":
            return String(localized: "Server address couldn't be resolved. Check the host in your configuration.")
        case "config":
            return String(localized: "This configuration is incomplete. Re-import or re-enter it.")
        case "tun-settings":
            return String(localized: "iOS refused the tunnel settings: \(message)")
        case "xray-start":
            return String(localized: "The server rejected the connection: \(message)")
        case "tunnel-io":
            return message
        default:
            return message
        }
    }
}
