import Foundation
import NetworkExtension

/// Снапшот текущей Wi-Fi сети. nil если device на сотовой / нет прав.
struct WiFiSnapshot: Equatable {
    let ssid: String
    let bssid: String
    let isSecure: Bool
    /// 0.0…1.0 (iOS даёт RSSI, приводит к нормированной шкале).
    let signalStrength: Double
}

/// Утилиты для Privacy Center. Никакой @Observable / stored state — только
/// stateless async функции над системными менеджерами (NEDNSSettingsManager /
/// NEHotspotNetwork). Все настойчиво держатся `@MainActor`, чтобы совпадать
/// с actor'ами вьюмоделей, которые их дёргают.
enum PrivacyCenterHelpers {

    // MARK: - DNS

    /// Применяет DoH-профиль к системе. iOS сам показывает системный алерт при
    /// первом применении. Если provider == .off — удаляем профиль.
    @MainActor
    static func applyDNS(provider: DNSProvider) async throws {
        let manager = NEDNSSettingsManager.shared()
        try await manager.loadFromPreferences()

        guard provider != .off else {
            // Полное удаление профиля из системы.
            do {
                try await manager.removeFromPreferences()
            } catch {
                // removeFromPreferences кидает если профиля не было — это ок.
                let ns = error as NSError
                guard ns.domain == NEDNSSettingsErrorDomain else { throw error }
            }
            return
        }

        let dohURL = provider.dohURL ?? URL(string: "https://cloudflare-dns.com/dns-query")!
        let settings = NEDNSOverHTTPSSettings(servers: provider.servers)
        settings.serverURL = dohURL

        manager.dnsSettings = settings
        manager.localizedDescription = "Guardium DNS · \(provider.title)"

        try await manager.saveToPreferences()
    }

    /// Проверяет, что системный DoH-профиль соответствует нашему выбору.
    /// Возвращает провайдера согласно URL профиля, либо .off если ничего не стоит.
    @MainActor
    static func currentSystemDNSProvider() async -> DNSProvider {
        let manager = NEDNSSettingsManager.shared()
        do {
            try await manager.loadFromPreferences()
        } catch {
            return .off
        }

        guard manager.isEnabled,
              let dohSettings = manager.dnsSettings as? NEDNSOverHTTPSSettings,
              let url = dohSettings.serverURL else {
            return .off
        }
        return DNSProvider.allCases.first(where: { $0.dohURL == url }) ?? .off
    }

    // MARK: - Wi-Fi

    /// Текущая ассоциированная Wi-Fi сеть. Требует entitlement
    /// `com.apple.developer.networking.wifi-info` + Location When-In-Use grant.
    /// Без разрешения на геолокацию iOS всегда отдаёт nil — поэтому сначала
    /// спрашиваем доступ, иначе секция Wi-Fi вечно пустая.
    /// Apple: SSID отдаётся, если приложение (а) имеет точную геопозицию, либо
    /// (б) у него установлен активный VPN-профиль, либо (в) активный
    /// NEDNSSettingsManager. Первый connect создаёт профиль, так что после него
    /// секция работает и без локации — но до этого нужна именно точная позиция.
    @MainActor
    static func fetchCurrentWiFi() async -> WiFiSnapshot? {
        guard await LocationAuthorizer.shared.ensureAuthorization() else { return nil }
        await LocationAuthorizer.shared.ensureFullAccuracy()
        return await withCheckedContinuation { cont in
            NEHotspotNetwork.fetchCurrent { network in
                guard let network else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: WiFiSnapshot(
                    ssid: network.ssid,
                    bssid: network.bssid,
                    isSecure: network.isSecure,
                    signalStrength: network.signalStrength
                ))
            }
        }
    }
}
