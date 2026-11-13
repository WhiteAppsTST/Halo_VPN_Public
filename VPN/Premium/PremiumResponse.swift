import Foundation

struct PremiumResponse: Codable {
    let title: [TitlePart]
    let subtitle: String
    let tryFreeButton: String
    let continueButton: String
    let products: [PaywallProductResponse]

    struct TitlePart: Codable, Hashable {
        let text: String
        let accent: Bool
    }

    struct PaywallProductResponse: Codable {
        let id: String
        let title: String
        let periodly: String
        /// Опциональный бейдж над карточкой продукта, например "BEST VALUE".
        /// `nil` — без бейджа.
        let label: String?
    }
}

extension [PremiumResponse.PaywallProductResponse] {
    func product(_ productId: String) -> PremiumResponse.PaywallProductResponse? {
        first(where: { productId == $0.id })
    }
}
