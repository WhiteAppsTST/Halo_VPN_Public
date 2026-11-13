import Foundation

struct AppConstants {
    struct Foundation {
        static let email: String = "contact@guardiumvpn.app"
        static let appID: Int = 6755680512
        static let privacyURLString: String = "https://sites.google.com/view/halo-hub-gateway-manager/privacy-policy?authuser=1"
        static let termsURLString: String = "https://sites.google.com/view/halo-hub-gateway-manager/terms-of-use?authuser=1"
        static let supportURLString: String = "https://sites.google.com/view/guardiumvpnunlimitedproxy/support"
        static let appLinkString: String = "http://itunes.apple.com/app/id\(appID)"
    }

    struct Bundle {
        static let app: String          = "com.guardiumvpn.app"
        static let packetTunnel: String = "com.guardiumvpn.app.PacketTunnel"
        static let appGroup: String     = "group.com.guardiumvpn.apppp"
    }

    struct UDKeys {
        static let obStatusFlag: String = "isOnboardingDone"
        static let userNameFlag: String = "user_name_flag"
        static let selectedServerRawURL: String = "selectedServerRawURL"
        static let speedTestLastDay: String = "speedTest.lastDay"
        static let speedTestCountToday: String = "speedTest.countToday"

        struct Shared {
            static let subscriptionExpiresAt: String = "subscription.expiresAt"
            static let killSwitchEnabled: String     = "prefs.killSwitchEnabled"
            static let autoConnectEnabled: String    = "prefs.autoConnectEnabled"
            static let dnsProvider: String           = "prefs.dnsProvider"
            static let tunnelLastErrorStage: String  = "tunnel.lastError.stage"
            static let tunnelLastErrorMessage: String = "tunnel.lastError.message"
            static let tunnelLastErrorAt: String     = "tunnel.lastError.at"
        }
    }
}
