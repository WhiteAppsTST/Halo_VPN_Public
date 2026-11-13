import Foundation
import AppTrackingTransparency
import AppsFlyerLib
import ApphudSDK
import AdSupport
import StoreKit
import UIKit

@MainActor
final class AppsFlyerService {
    static let shared = AppsFlyerService()
    private init() {}

    private var isConfigured = false

    /// `AppsFlyerLib.delegate` — weak, поэтому владеем делегатом здесь,
    /// иначе он умрёт сразу после configure() и данные атрибуции не придут.
    private let conversionDelegate = AppsFlyerConversionDelegate()

    func configure() {
        guard !isConfigured else { return }

        let devKey = Bundle.main.object(forInfoDictionaryKey: "AppsFlyerDevKey") as? String ?? ""
        guard !devKey.isEmpty else {
            print("[AppsFlyer] Dev key missing (Info.plist: AppsFlyerDevKey). SDK not configured.")
            return
        }

        let appId = String(AppConstants.Foundation.appID)
        // Типизированный вызов вместо Selector(("...")) — опечатка в строке
        // селектора раньше уронила бы инициализацию молча, в рантайме.
        AppsFlyerLib.shared().initialize(devKey: devKey, appId: appId)
        // Делегат обязательно до start(): conversion data приходит один раз,
        // сразу после первого запроса SDK, и без делегата теряется.
        AppsFlyerLib.shared().delegate = conversionDelegate
        #if DEBUG
        AppsFlyerLib.shared().isDebug = true
        #endif

        AppsFlyerLib.shared().registerSessionReadyListener {
            Task { @MainActor in
                await Self.requestATTIfNeeded()
                Self.startSDK()
            }
        }

        isConfigured = true
    }

    /// Отдельный синхронный хелпер: внутри async-контекста `start()`
    /// резолвится в async throws overload, что здесь не нужно.
    private static func startSDK() {
        AppsFlyerLib.shared().start()
    }

    func registerForUninstall(_ deviceToken: Data) {
        guard isConfigured else { return }
        AppsFlyerLib.shared().registerUninstall(deviceToken)
    }

    func logTrialStart(productId: String, placementId: String?) {
        guard isConfigured else { return }
        AppsFlyerLib.shared().logEvent(AFEventStartTrial, withValues: [
            AFEventParamContentId: productId,
            "placement_id": placementId ?? "unknown"
        ])
    }

    func logPurchase(revenue: Double, currency: String, productId: String, placementId: String?) {
        guard isConfigured else { return }
        AppsFlyerLib.shared().logEvent(AFEventPurchase, withValues: [
            AFEventParamRevenue: revenue,
            AFEventParamCurrency: currency,
            AFEventParamContentId: productId,
            "placement_id": placementId ?? "unknown"
        ])
    }

    func logSubscriptionCancelled(productId: String, reason: String) {
        guard isConfigured else { return }
        AppsFlyerLib.shared().logEvent("af_subscription_cancelled", withValues: [
            AFEventParamContentId: productId,
            "reason": reason
        ])
    }

    /// Триал сконвертился в платную подписку (первое списание после free trial).
    /// Считаем только один раз на каждый originalTransactionID.
    func logTrialConverted(revenue: Double, currency: String, productId: String, placementId: String?) {
        guard isConfigured else { return }
        AppsFlyerLib.shared().logEvent("trial_converted", withValues: [
            AFEventParamRevenue: revenue,
            AFEventParamCurrency: currency,
            AFEventParamContentId: productId,
            "placement_id": placementId ?? "unknown"
        ])
    }

    /// Пейвол открылся — фиксируем placement id
    /// (main / settingspaywall / manualserverpaywall / pushspecialoffer).
    func logPaywallOpened(placementId: String) {
        guard isConfigured else { return }
        AppsFlyerLib.shared().logEvent("paywall_opened", withValues: [
            "placement_id": placementId
        ])
    }

    /// Юзер тапнул по карточке продукта внутри пейвола (ещё до нажатия Continue).
    func logProductSelected(productId: String, placementId: String?) {
        guard isConfigured else { return }
        AppsFlyerLib.shared().logEvent("paywall_product_selected", withValues: [
            AFEventParamContentId: productId,
            "placement_id": placementId ?? "unknown"
        ])
    }

    func handle(_ tx: StoreKit.Transaction) {
        if tx.revocationDate != nil {
            let reason: String
            switch tx.revocationReason {
            case .developerIssue: reason = "developer_issue"
            case .other:          reason = "other"
            default:              reason = "unknown"
            }
            logSubscriptionCancelled(productId: tx.productID, reason: reason)
            return
        }

        let isRenewal = tx.id != tx.originalID
        let placement = isRenewal ? "renewal" : SubscriptionService.shared.activePaywallId?.rawValue
        let isTrial = tx.offer?.paymentMode == .freeTrial

        if isTrial {
            // Запоминаем originalID триала, чтобы позже поймать конверсию.
            Self.markTrialStarted(originalID: tx.originalID)
            logTrialStart(productId: tx.productID, placementId: placement)
            return
        }

        let revenue = tx.price.map { Double(truncating: $0 as NSDecimalNumber) } ?? 0
        let currency = tx.currency?.identifier
            ?? Locale.current.currency?.identifier
            ?? "USD"

        // Первое платное списание после триала = конверсия.
        // Определяем по флагу, сохранённому при .freeTrial (см. выше).
        // После стрельбы флаг снимаем, чтобы последующие продления шли как renewal.
        if isRenewal, Self.consumeTrialStarted(originalID: tx.originalID) {
            logTrialConverted(
                revenue: revenue,
                currency: currency,
                productId: tx.productID,
                placementId: placement
            )
        }

        logPurchase(
            revenue: revenue,
            currency: currency,
            productId: tx.productID,
            placementId: placement
        )
    }

    // MARK: - Trial → paid conversion tracking (UD-backed)

    private static let trialsUDKey = "AppsFlyerService.trialStartedOriginalIDs"

    private static func markTrialStarted(originalID: UInt64) {
        var set = Set(UserDefaults.standard.array(forKey: trialsUDKey) as? [UInt64] ?? [])
        set.insert(originalID)
        UserDefaults.standard.set(Array(set), forKey: trialsUDKey)
    }

    /// Возвращает true если для этого originalID был зафиксирован start-trial.
    /// После вызова originalID удаляется — конверсия считается один раз.
    private static func consumeTrialStarted(originalID: UInt64) -> Bool {
        var set = Set(UserDefaults.standard.array(forKey: trialsUDKey) as? [UInt64] ?? [])
        guard set.remove(originalID) != nil else { return false }
        UserDefaults.standard.set(Array(set), forKey: trialsUDKey)
        return true
    }

    private static func requestATTIfNeeded() async {
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        // Зовём в любом случае, а не только после свежего запроса: если доступ
        // выдали в прошлый запуск, IDFA всё равно нужно отдать Apphud.
        submitDeviceIdentifiersToApphud()
    }

    /// IDFV отдаём всегда, IDFA — только при разрешённом ATT.
    ///
    /// Без этого Apphud пишет «Device Identifiers (IDFA and/or IDFV) were not
    /// set» и не может сопоставить своего юзера с юзером AppsFlyer — атрибуция
    /// подписок разъезжается. Apphud рекомендует звать метод дважды: сразу
    /// после start() (только IDFV) и повторно после ответа ATT (уже с IDFA).
    static func submitDeviceIdentifiersToApphud() {
        let idfv = UIDevice.current.identifierForVendor?.uuidString

        var idfa: String?
        if ATTrackingManager.trackingAuthorizationStatus == .authorized {
            let raw = ASIdentifierManager.shared().advertisingIdentifier.uuidString
            // При запрете доступа система отдаёт нулевой UUID — он бесполезен.
            if raw != "00000000-0000-0000-0000-000000000000" { idfa = raw }
        }

        Apphud.setDeviceIdentifiers(idfa: idfa, idfv: idfv)
    }
}
