import Foundation

/// Источник серверов. subscription_url приходит извне (см. SubscriptionGate),
/// провайдер сам делает GET, парсит через VPNConfigParser и кэширует.
@Observable
@MainActor
final class SubscriptionProvider {
    @ObservationIgnored static let shared = SubscriptionProvider()

    @ObservationIgnored private var subscriptionURL: String?

    private(set) var servers: [VPNServerConfig] = []
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    @ObservationIgnored private let cacheKey = "SubscriptionProvider.cache.v3"
    @ObservationIgnored private let session = URLSession(configuration: .ephemeral)
    @ObservationIgnored private var currentGeneration = UUID()

    private init() {
        loadCache()
    }

    /// Принимаем subscription_url от подписочного слоя (Apphud → бэк).
    /// nil/пусто — юзер потерял доступ, чистим локально. Тот же URL — no-op.
    func applyOverrideURL(_ url: String?) {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (trimmed?.isEmpty == false) ? trimmed : nil

        guard next != subscriptionURL else { return }
        subscriptionURL = next

        if next == nil {
            servers = []
            lastError = nil
            UserDefaults.standard.removeObject(forKey: cacheKey)
        } else {
            refresh()
        }
    }

    /// Есть ли вообще откуда качать список. Экран серверов по этому флагу решает,
    /// достаточно ли повторить GET подписки — или сначала надо переспросить бэк
    /// про subscription_url.
    var hasSubscriptionURL: Bool { subscriptionURL != nil }

    /// Пока идёт повторный запрос к бэку, список должен показывать спиннер,
    /// а не «нет URL» — иначе кнопка «Try again» выглядит неработающей.
    func markBackendRetryStarted() {
        isLoading = true
        lastError = nil
    }

    func markBackendRetryFailed() {
        isLoading = false
        lastError = "No subscription URL. Sign in or contact support."
    }

    func refresh() {
        guard let raw = subscriptionURL, let url = URL(string: raw) else {
            isLoading = false
            lastError = "No subscription URL. Sign in or contact support."
            return
        }

        let gen = UUID()
        currentGeneration = gen
        isLoading = true
        lastError = nil

        Task { await performRefresh(url: url, gen: gen) }
    }


    private func performRefresh(url: URL, gen: UUID) async {
        var req = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        req.setValue(Self.clientUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(DeviceID.hwid,        forHTTPHeaderField: "x-hwid")
        req.setValue(DeviceID.os,          forHTTPHeaderField: "x-device-os")
        req.setValue(DeviceID.osVersion,   forHTTPHeaderField: "x-ver-os")
        req.setValue(DeviceID.model,       forHTTPHeaderField: "x-device-model")
        req.setValue("application/octet-stream, text/plain, application/json, */*",
                     forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await session.data(for: req)
            guard gen == currentGeneration else { return }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""

            guard (200..<300).contains(status) else {
                isLoading = false
                lastError = "HTTP \(status) from panel"
                return
            }

            let parsed = VPNConfigParser.parseSubscription(body)
            isLoading = false
            servers = parsed
            if parsed.isEmpty {
                lastError = "Panel returned 0 servers."
            } else {
                saveCache(parsed)
                VPNService.shared.alignDefaultCountryToAvailable()
            }
        } catch {
            guard gen == currentGeneration else { return }
            isLoading = false
            lastError = error.localizedDescription
        }
    }

    func servers(for country: VPNCountry) -> [VPNServerConfig] {
        servers.filter { $0.countryCode?.uppercased() == country.iso }
    }

    func bestServer(for country: VPNCountry) -> VPNServerConfig? {
        servers(for: country).first ?? servers.first
    }

    //MARK: - Cache
    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let obj  = try? JSONDecoder().decode([VPNServerConfig].self, from: data) else { return }
        self.servers = obj
    }

    private func saveCache(_ list: [VPNServerConfig]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    /// User-Agent в формате Remnawave-панели: `<AppName>/<Version>`.
    private static var clientUserAgent: String {
        let name = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? "vpn"
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        return "\(name)/\(version)"
    }
}
