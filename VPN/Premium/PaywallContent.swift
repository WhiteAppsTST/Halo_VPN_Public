import Foundation

enum PaywallContent {
    static func info(for placement: PaywallId) -> PaywallInfo {
        switch placement {
        case .main:             return main
        case .settings:         return settings
        case .manualServer:     return manualServer
        case .pushSpecialOffer: return pushSpecialOffer
        }
    }

    /// Название плана определяем по subscription period из StoreKit — работает
    /// для любого productId, не привязано к конкретному бренду.
    /// productId используется только как fallback, если period недоступен.
    static func productTitle(for productId: String, period: String?) -> String {
        switch period {
        case "year":  return String(localized: "Annual")
        case "month": return String(localized: "Monthly")
        case "week":  return String(localized: "Weekly")
        case "day":   return String(localized: "Daily")
        default:      return productId
        }
    }


    private static var main: PaywallInfo {
        PaywallInfo(
            title: [
                .init(text: String(localized: "Try Premium\nAccess for "), accent: false),
                .init(text: String(localized: "Free"), accent: true)
            ],
            subtitle: String(localized: "No charge today. Keep full protection or cancel\nbefore trials ends."),
            tryFreeButton: String(localized: "Start my Free Trial"),
            continueButton: String(localized: "Continue & subscribe")
        )
    }

    private static var settings: PaywallInfo {
        PaywallInfo(
            title: [
                .init(text: String(localized: "Try Premium "), accent: false),
                .init(text: String(localized: "Free"), accent: true),
                .init(text: String(localized: "\nfor 7 Days"), accent: false)
            ],
            subtitle: String(localized: "No charge today. Keep full protection or cancel\nbefore trials ends."),
            tryFreeButton: String(localized: "Start my Free Trial"),
            continueButton: String(localized: "Continue & subscribe")
        )
    }

    private static var manualServer: PaywallInfo {
        PaywallInfo(
            title: [
                .init(text: String(localized: "Unlock "), accent: false),
                .init(text: String(localized: "Everything"), accent: true)
            ],
            subtitle: String(localized: "Every location, full speed, zero logs -\nfree for 7 days."),
            tryFreeButton: String(localized: "Start my Free Trial"),
            continueButton: String(localized: "Continue & subscribe")
        )
    }

    private static var pushSpecialOffer: PaywallInfo {
        PaywallInfo(
            title: [
                .init(text: String(localized: "Get full "), accent: false),
                .init(text: String(localized: "Access"), accent: true)
            ],
            subtitle: String(localized: "with the maximum discount available:"),
            tryFreeButton: String(localized: "Start my Free Trial"),
            continueButton: String(localized: "Continue & subscribe")
        )
    }
}
