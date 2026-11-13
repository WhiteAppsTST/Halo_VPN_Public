import Foundation
import ApphudSDK

struct PaywallInfo {
    let title: [PremiumResponse.TitlePart]
    let subtitle: String
    let tryFreeButton: String
    let continueButton: String
}

struct PremiumProduct: Identifiable, Equatable {
    var id: String
    var title: String
    var periodly: String
    var label: String?
    var includesTrial: Bool
    var apphudProduct: ApphudProduct?
    var pricePerPeriod: String
    var pricePerMonth: String?
    var trialDays: Int?
}

extension [PremiumProduct] {
    var weeklyOption: PremiumProduct? {
        first(where: { $0.periodly == "week" || $0.periodly == "1" || $0.periodly == "2" })
    }
}
