import Foundation
@preconcurrency import ApphudSDK
import StoreKit

extension ApphudProduct {

    /// Строим PremiumProduct на базе synchronous `skProduct` (Apphud кладёт его
    /// туда после успешного fetch из StoreKit). Async `product()` — только для
    /// проверки eligibility для intro-offer, которая доступна лишь в SK2.
    /// Если skProduct == nil → App Store вообще не вернул этот productId
    /// (обычно продукт не approved / не создан в ASC). Такой продукт наверх
    /// не всплывает — см. filter в `ApphudPaywall.convertProducts`.
    func toPremiumProduct() async -> PremiumProduct? {
        guard let sk = skProduct else {
            print("[Apphud] skProduct nil for \(productId) — skipped (not in App Store).")
            return nil
        }

        let period    = Self.periodString(from: sk.subscriptionPeriod)
        let price     = Self.formattedPrice(sk)
        let perMonth  = Self.pricePerMonth(sk)
        let hasTrial  = await isTrialEligible()
        let trialDays = Self.trialDaysCount(from: sk)

        return PremiumProduct(
            id: productId,
            title: PaywallContent.productTitle(for: productId, period: period),
            periodly: period ?? "unknown",
            label: nil, // выставляется на самом длинном периоде в convertProducts
            includesTrial: hasTrial,
            apphudProduct: self,
            pricePerPeriod: price,
            pricePerMonth: perMonth,
            trialDays: trialDays
        )
    }

    // MARK: - Trial eligibility (SK2 required)

    private func isTrialEligible() async -> Bool {
        guard let sk2 = try? await self.product(),
              let subscription = sk2.subscription,
              subscription.introductoryOffer != nil,
              await subscription.isEligibleForIntroOffer
        else { return false }
        return true
    }

    // MARK: - SK1 helpers

    /// StoreKit нормализует периоды по-разному: локальный .storekit-конфиг
    /// отдаёт P1W как «7 days», из-за чего недельный продукт подписывался
    /// как «Daily». Поэтому смотрим и на unit, и на количество единиц.
    private static func periodString(from period: SKProductSubscriptionPeriod?) -> String? {
        guard let period else { return nil }
        let count = max(1, period.numberOfUnits)
        switch period.unit {
        case .day:
            if count % 365 == 0 { return "year" }
            if count % 30  == 0 { return "month" }
            if count % 7   == 0 { return "week" }
            return "day"
        case .week:
            if count % 52 == 0 { return "year" }
            if count % 4  == 0 { return "month" }
            return "week"
        case .month:
            if count % 12 == 0 { return "year" }
            return "month"
        case .year:
            return "year"
        @unknown default: return nil
        }
    }

    private static func formattedPrice(_ sk: SKProduct) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = sk.priceLocale
        return f.string(from: sk.price) ?? "\(sk.price)"
    }

    private static func pricePerMonth(_ sk: SKProduct) -> String? {
        guard let period = sk.subscriptionPeriod else { return nil }
        let count = max(1, period.numberOfUnits)
        let months: Int
        switch period.unit {
        case .year:  months = 12 * count
        case .month: months = count
        case .day where count % 365 == 0: months = 12 * (count / 365)
        case .day where count % 30 == 0:  months = count / 30
        case .week where count % 4 == 0:  months = count / 4
        default:     return nil
        }
        let per = sk.price.dividing(by: NSDecimalNumber(value: months))
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = sk.priceLocale
        return f.string(from: per)
    }

    private static func trialDaysCount(from sk: SKProduct) -> Int? {
        guard let intro = sk.introductoryPrice else { return nil }
        let p = intro.subscriptionPeriod
        switch p.unit {
        case .day:   return p.numberOfUnits
        case .week:  return p.numberOfUnits * 7
        case .month: return p.numberOfUnits * 30
        case .year:  return p.numberOfUnits * 365
        @unknown default: return nil
        }
    }
}

extension ApphudPaywall {
    func convertProducts() async -> [PremiumProduct] {
        var products = [PremiumProduct]()

        await withTaskGroup(of: (Int, PremiumProduct?).self) { group in
            for (index, item) in self.products.enumerated() {
                group.addTask {
                    return (index, await item.toPremiumProduct())
                }
            }

            var tempResults = Array<PremiumProduct?>(repeating: nil, count: self.products.count)
            for await (index, product) in group {
                tempResults[index] = product
            }

            // nil здесь = продукта нет в App Store Connect. В UI не показываем.
            products = tempResults.compactMap { $0 }
        }

        // Сортировка: year → month → week → day → unknown.
        products.sort { periodPriority($0.periodly) < periodPriority($1.periodly) }

        // Best Value badge — на самом длинном доступном периоде.
        if let bestIdx = products.firstIndex(where: { $0.periodly == "year" })
            ?? products.firstIndex(where: { $0.periodly == "month" })
            ?? products.firstIndex(where: { $0.periodly == "week" }) {
            products[bestIdx].label = String(localized: "Best Value")
        }

        return products
    }

    private func periodPriority(_ periodly: String) -> Int {
        switch periodly {
        case "year":  return 0
        case "month": return 1
        case "week":  return 2
        case "day":   return 3
        default:      return 4
        }
    }
}
