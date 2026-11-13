import Foundation
import ApphudSDK
import StoreKit
import SwiftUI
import AdServices
import Combine

@MainActor
@Observable
final class SubscriptionService {
    @ObservationIgnored
    @AppStorage("FIRST_LAUNCH") private var firstLaunch = true

    /// Срок доступа, выданного бэкендом (например, серверный триал на 3 дня).
    /// Apphud о нём не знает: покупки в App Store не было. Кэшируем в UD, чтобы
    /// холодный старт без сети не отбирал у юзера уже выданный доступ, и всегда
    /// сверяем с датой — протухший кэш премиум не даёт.
    @ObservationIgnored
    @AppStorage("backend.entitlementExpiresAt") private var backendEntitlementExpiresAt = ""
    
    var appState: AppState = .onboarding
    var products = [PremiumProduct]()
    var selection: PremiumProduct?
    var isActiveSubscription = false
    var isPaywallShown = false
    var purchaseState: PurchaseState = .idle
    var fetchState: FetchState = .loading
    
    var paywall: PaywallInfo?
    var canUseTrial = true
    var activePaywallId: PaywallId?
    var expectedProductsCount: Int = 0
    
    private var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "ApphudApi") as? String ?? ""
    }
    
    static let shared = SubscriptionService()
    private init() {
        appState = firstLaunch ? .onboarding : .home
        // До ответа бэка и до старта Apphud опираемся на кэш срока: иначе на
        // холодном старте юзер с активным серверным триалом на секунду видит
        // себя бесплатным, и ему успевает прилететь пейвол.
        isActiveSubscription = backendEntitlementActive
    }
}

extension SubscriptionService {
    
    var titledText: String {
        guard let prod = selection else { return "" }
        return formatTrialOrSubscription(prod: prod)
    }
    
    var purchaseBtnTitle: LocalizedStringResource {
        let selectionHasTrial = selection?.includesTrial ?? false

        if canUseTrial && selectionHasTrial {
            if let backend = paywall?.tryFreeButton { return "\(backend)" }
            return "Start my Free Trial"
        }

        if let backend = paywall?.continueButton { return "\(backend)" }
        return "Continue & subscribe"
    }
    
    /// Премиум = покупка в Apphud ИЛИ активный доступ, выданный бэкендом.
    /// Одного Apphud мало: бэк сам выдаёт серверный триал и возвращает
    /// subscription_url, и без этой проверки юзер упирался бы в пейвол,
    /// хотя сервера ему уже выданы.
    func hasActiveSubscription() -> Bool {
        Apphud.hasActiveSubscription() || backendEntitlementActive
    }

    /// Не истёк ли срок, выданный бэкендом.
    var backendEntitlementActive: Bool {
        guard let until = Self.parseBackendDate(backendEntitlementExpiresAt) else { return false }
        return until > Date()
    }

    /// Бэк отдаёт ISO8601, иногда с долями секунды ("…T03:24:17.618Z"),
    /// иногда без — пробуем оба формата.
    private static func parseBackendDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
    
    func isNewUser() -> Bool {
        let subscriptions = Apphud.subscriptions() ?? []
        let purchases = Apphud.nonRenewingPurchases() ?? []

       return subscriptions.isEmpty && purchases.isEmpty
    }

    private func formatTrialOrSubscription(prod: PremiumProduct) -> String {
        if prod.includesTrial && canUseTrial {
            return "Not payment now.\nTry 3 days free"
        }
        
        return "Easy start with\n\(prod.title) \(prod.pricePerPeriod)"
    }
    
    func start() {
        Apphud.start(apiKey: apiKey)
        // IDFV передаём сразу после start(), как рекомендует Apphud. IDFA
        // добавится позже, когда отработает ATT — см.
        // AppsFlyerService.submitDeviceIdentifiersToApphud().
        AppsFlyerService.submitDeviceIdentifiersToApphud()
        trackAppleSearchAds()
        startTransactionListener()
        Apphud.refreshUserData { [weak self] _ in
            Task { @MainActor in
                await self?.registerOnBackend()
            }
        }
    }


    private func registerOnBackend() async {
        let apphudUserID = Apphud.userID()
        let obDone = UserDefaults.standard.bool(forKey: AppConstants.UDKeys.obStatusFlag)
        do {
            let state = try await VPNBackend.register(apphudUserID: apphudUserID)
            apply(state: state)

            // Бэк узнаёт о подписке ТОЛЬКО из sync (он сам проверяет чек у Apple).
            // Без этого вызова юзер, купивший подписку раньше или переустановивший
            // приложение, для бэка остаётся бесплатным — и серверов не получит.
            // Внутри стоит guard: если активного чека нет, запрос не уйдёт.
            await syncCurrentEntitlement()
        } catch {
            print("[VPNBackend] register failed: \(error)")
            // Бэк недоступен — опираемся на Apphud и на ещё не истёкший кэш.
            isActiveSubscription = hasActiveSubscription()
        }
        if !isActiveSubscription, obDone {
            showPaywall(.main)
        }
    }

    /// Повторный поход на бэк за subscription_url.
    ///
    /// register вызывается один раз за запуск (в start()), и если тот вызов
    /// не прошёл — сеть недоступна, Railway поднимал контейнер дольше таймаута —
    /// SubscriptionProvider так и остаётся без URL до перезапуска приложения:
    /// кнопка «Try again» в списке серверов дёргает refresh(), а тот падает на
    /// «No subscription URL». Поэтому экран серверов при отсутствии URL должен
    /// сначала переспросить бэк. Endpoint идемпотентный — он и так зовётся
    /// на каждом старте и для существующего юзера просто возвращает его состояние.
    @discardableResult
    func retryBackendRegistration() async -> Bool {
        do {
            let state = try await VPNBackend.register(apphudUserID: Apphud.userID())
            apply(state: state)
            return state.subscriptionURL?.isEmpty == false
        } catch {
            print("[VPNBackend] retry register failed: \(error)")
            return false
        }
    }

    private func apply(state: VPNBackend.UserState) {
        SubscriptionProvider.shared.applyOverrideURL(state.subscriptionURL)

        // is_active без даты доверять нельзя — тогда доступ стал бы вечным.
        if state.isActive, let expires = state.expiresAt, !expires.isEmpty {
            backendEntitlementExpiresAt = expires
        } else {
            backendEntitlementExpiresAt = ""
        }

        isActiveSubscription = hasActiveSubscription()
    }

    private func syncCurrentEntitlement() async {
        let apphudUserID = Apphud.userID()
        var jws: String?
        for await verificationResult in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let tx) = verificationResult,
                  tx.productType == .autoRenewable,
                  tx.revocationDate == nil else { continue }
            jws = verificationResult.jwsRepresentation
            break
        }
        guard let jws else { return }
        do {
            let state = try await VPNBackend.sync(
                apphudUserID: apphudUserID,
                signedTransaction: jws
            )
            apply(state: state)
        } catch {
            print("[VPNBackend] sync (post-purchase) failed: \(error)")
        }
    }

    private func startTransactionListener() {
        Task.detached { [weak self] () -> Void in
            for await result in StoreKit.Transaction.updates {
                guard case .verified(let tx) = result else { continue }
                await MainActor.run { AppsFlyerService.shared.handle(tx) }

                if tx.revocationDate == nil, tx.productType == .autoRenewable {
                    let jws = result.jwsRepresentation
                    let userID = await Apphud.userID()
                    do {
                        let state = try await VPNBackend.sync(
                            apphudUserID: userID,
                            signedTransaction: jws
                        )
                        guard let strongSelf = self else { return }
                        await MainActor.run { strongSelf.apply(state: state) }
                    } catch {
                    }
                }

                await tx.finish()
            }
        }
    }
    
    func fetchProductBy(paywall paywallId: PaywallId) async {
        activePaywallId = paywallId
        self.products = []
        self.selection = nil
        self.expectedProductsCount = 0

        guard let placement = await Apphud.placement(paywallId.rawValue) else {
            print("[Apphud] placement \"\(paywallId.rawValue)\" NOT found — check identifier in dashboard.")
            return
        }
        guard let paywall = placement.paywall else {
            print("[Apphud] placement \"\(paywallId.rawValue)\" has NO paywall attached.")
            return
        }

        self.expectedProductsCount = paywall.products.count
        let rawIds = paywall.products.map(\.productId)
        print("[Apphud] placement \"\(paywallId.rawValue)\" → paywall products: \(rawIds)")

        let converted = await paywall.convertProducts()
        let visibleIds = converted.map { "\($0.id) [\($0.periodly)]" }
        print("[Apphud] after filter/skProduct check → visible products: \(visibleIds)")

        self.products = converted
        updatePaywallInfo(from: paywall)
    }
    
    func completePurchase() async {
        guard let product = selection?.apphudProduct else { return }
        purchaseState = .purchasing
        let result = await Apphud.purchase(product)
        if result.success {
            await syncCurrentEntitlement()
            success()
        } else {
            failure()
        }
    }


    /// Раньше любой ответ без ошибки считался успехом — даже когда покупок
    /// не нашлось, пейвол закрывался и рапортовал «восстановлено».
    func restore() async {
        purchaseState = .purchasing
        let result = await Apphud.restorePurchases()
        if let error = result?.error {
            failure("Couldn't restore purchases: \(error.localizedDescription)")
            return
        }
        guard Apphud.hasActiveSubscription() else {
            purchaseState = .failure("No active subscription found for this Apple ID.")
            return
        }
        await syncCurrentEntitlement()
        success()
    }
    
    func limitedButtonTapped() {
        firstLaunch = false
        appState = .home
    }
    
    func showPaywall(_ paywallId: PaywallId = .main) {
        fetchState = .loading
        isPaywallShown = true
        Task { @MainActor in
            await fetchProductBy(paywall: paywallId)
            fetchState = .success
        }
    }
    
    func canGenerate() -> Bool {
        hasActiveSubscription()
    }
}

private extension SubscriptionService {
    private func success() {
        firstLaunch = false
        if !isPaywallShown {
            appState = .home
        }
        
        if isPaywallShown {
            isPaywallShown = false
        }
        
        isActiveSubscription = hasActiveSubscription()
        purchaseState = .success
    }
    
    private func failure(_ errorText: LocalizedStringResource = "Something went wrong with the purchase. Please try again!") {
        purchaseState = .failure(errorText)
    }
    
    private func trackAppleSearchAds() {
        Task {
            if let asaToken = try? AAAttribution.attributionToken() {
                Apphud.setAttribution(data: .init(rawData: [:]), from: .appleAdsAttribution, identifer: asaToken, callback: nil)
            }
        }
    }
    
    private func updatePaywallInfo(from paywall: ApphudPaywall) {
        self.canUseTrial = products.contains(where: \.includesTrial)
        self.paywall = PaywallContent.info(for: activePaywallId ?? .main)
        self.selection = products.weeklyOption ?? products.first
    }
}

enum AppState: String {
    case onboarding, home
}

enum PaywallId: String {
    case main             = "main"
    case settings         = "settingspaywall"
    case manualServer     = "manualserverpaywall"
    case pushSpecialOffer = "pushspecialoffer"
}


extension Decimal {
    func round(
        scale: Int,
        mode: NSDecimalNumber.RoundingMode = .plain
    ) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }
}
