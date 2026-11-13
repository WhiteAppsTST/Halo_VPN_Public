import SwiftUI

enum SideMenuRow: Hashable, CaseIterable {
    case ownerServers
    case vpn
    case privacy
    case speed
    case settings
    case support

    var title: LocalizedStringResource {
        switch self {
        case .ownerServers: return "Own server"
        case .vpn:          return "Get PRO VPN"
        case .privacy:      return "Privacy Center"
        case .speed:        return "Speed test"
        case .settings:     return "Settings"
        case .support:      return "Support"
        }
    }

    var iconName: String {
        switch self {
        case .ownerServers: return "rectangle.grid.1x2"
        case .vpn:          return "globe"
        case .privacy:      return "lock.shield"
        case .speed:        return "gauge.open.with.lines.needle.33percent"
        case .settings:     return "gearshape"
        case .support:      return "shield"
        }
    }

    @ViewBuilder
    var destinationView: some View {
        switch self {
        case .ownerServers: OwnServersView()
        case .vpn:          GetProVPNView()
        case .privacy:      PrivacyCenterView()
        case .speed:        SpeedTestView()
        case .settings:     AppSettingsView()
        case .support:      SupportView()
        }
    }
}
