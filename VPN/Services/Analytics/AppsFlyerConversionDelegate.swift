import Foundation
import AppsFlyerLib
import ApphudSDK

/// Приёмник данных атрибуции от AppsFlyer.
///
/// Без назначенного делегата SDK пишет в лог `[GCD-E01] Delegate is nil or does
/// not respond to -[AppsFlyerLibDelegate onConversionDataSuccess:]`, а сами
/// данные (органика/не органика, источник, кампания) просто выбрасываются —
/// приложение не знает, откуда пришёл юзер.
///
/// Полученный ответ уходит в Apphud вместе с AppsFlyer UID: так подписка в
/// Apphud привязывается к кампании, и отчёты по выручке сходятся с AppsFlyer.
///
/// ВАЖНО: `AppsFlyerLib.delegate` объявлен `weak`, поэтому владеть этим
/// объектом должен кто-то ещё — им владеет `AppsFlyerService`.
final class AppsFlyerConversionDelegate: NSObject, AppsFlyerLibDelegate {

    /// Вызывается не на главном потоке. `Apphud.setAttribution` не требует
    /// главного потока, поэтому переключение не нужно.
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        Apphud.setAttribution(
            data: ApphudAttributionData(rawData: conversionInfo),
            from: .appsFlyer,
            identifer: AppsFlyerLib.shared().getAppsFlyerUID(),
            callback: nil
        )

        #if DEBUG
        let status   = conversionInfo["af_status"]     as? String ?? "?"
        let source   = conversionInfo["media_source"]  as? String ?? "-"
        let campaign = conversionInfo["campaign"]      as? String ?? "-"
        print("[AppsFlyer] conversion: af_status=\(status), media_source=\(source), campaign=\(campaign)")
        #endif
    }

    func onConversionDataFail(_ error: Error) {
        print("[AppsFlyer] conversion data failed: \(error.localizedDescription)")
    }
}
