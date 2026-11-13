import Foundation

/// Пользовательские настройки VPN. Хранятся в App Group — их читает
/// PacketTunnel extension (DNS применяется прямо в туннеле, см.
/// PacketTunnelProvider.makeSettings).
@Observable
@MainActor
final class AppPreferencesStore {
    @ObservationIgnored static let shared = AppPreferencesStore()

    @ObservationIgnored private let defaults: UserDefaults

    /// Kill switch = `includeAllNetworks` у NETunnelProviderProtocol.
    /// Применяется к уже сохранённому профилю сразу (см. VPNService.applyKillSwitchPreference).
    var killSwitchEnabled: Bool {
        didSet { defaults.set(killSwitchEnabled, forKey: AppConstants.UDKeys.Shared.killSwitchEnabled) }
    }

    /// Включает системный on-demand у NETunnelProviderManager: iOS сам поднимает
    /// туннель при любом сетевом трафике. Применяется через
    /// `VPNService.applyAutoConnectPreference()`.
    var autoConnectEnabled: Bool {
        didSet { defaults.set(autoConnectEnabled, forKey: AppConstants.UDKeys.Shared.autoConnectEnabled) }
    }

    /// Активный DNS-провайдер. Пишется в App Group и читается расширением,
    /// которое подставляет эти серверы в NEDNSSettings туннеля. Плюс
    /// применяется системно (DoH) через PrivacyCenterHelpers.applyDNS.
    var dnsProvider: DNSProvider {
        didSet { defaults.set(dnsProvider.rawValue, forKey: AppConstants.UDKeys.Shared.dnsProvider) }
    }

    private init(defaults: UserDefaults? = nil) {
        let store = defaults
            ?? UserDefaults(suiteName: AppConstants.Bundle.appGroup)
            ?? .standard
        self.defaults = store
        self.killSwitchEnabled = store.bool(forKey: AppConstants.UDKeys.Shared.killSwitchEnabled)
        self.autoConnectEnabled = store.bool(forKey: AppConstants.UDKeys.Shared.autoConnectEnabled)
        let raw = store.string(forKey: AppConstants.UDKeys.Shared.dnsProvider) ?? DNSProvider.off.rawValue
        self.dnsProvider = DNSProvider(rawValue: raw) ?? .off
    }
}
