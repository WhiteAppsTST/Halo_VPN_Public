import Foundation
import CoreLocation
import UIKit

/// Снимок состояния для удалённой отладки. Тестер открывает Settings →
/// Diagnostics, копирует текст и присылает. Одна сборка отвечает на вопрос
/// «почему не сработало», без второго круга через TestFlight.
@MainActor
enum DiagnosticsReport {

    /// Последняя ошибка спидтеста: код SDK + расшифровка. Пишется из
    /// SpeedTestViewModel при каждом неудачном запуске.
    private(set) static var lastSpeedTestError: String?
    private(set) static var lastSpeedTestErrorAt: Date?
    /// Последний успешный результат — чтобы отличить «не запускался» от «упал».
    private(set) static var lastSpeedTestSuccess: String?

    static func recordSpeedTestError(code: Int, name: String, message: String) {
        lastSpeedTestError = "code=\(code) (\(name)) — \(message)"
        lastSpeedTestErrorAt = Date()
    }

    static func recordSpeedTestSuccess(downMbps: Double, upMbps: Double) {
        lastSpeedTestSuccess = String(format: "%.1f↓ / %.1f↑ Mbps", downMbps, upMbps)
        lastSpeedTestErrorAt = Date()
    }

    static func makeText(servicesEnabled: Bool) -> String {
        var lines: [String] = []

        lines.append("— APP —")
        lines.append("version: \(appVersion) (\(buildNumber))")
        lines.append("bundle: \(Bundle.main.bundleIdentifier ?? "?")")
        lines.append("iOS: \(UIDevice.current.systemVersion), model: \(DeviceID.model)")
        lines.append("date: \(ISO8601DateFormatter().string(from: Date()))")

        lines.append("")
        lines.append("— SPEED TEST —")
        let engine = SpeedTestViewModel.useSpeedCheckerSDK
            ? "SpeedChecker SDK (\(SpeedTestViewModel.licenseKey == nil ? "free — needs location" : "licensed"))"
            : "built-in (Cloudflare, no location needed)"
        lines.append("engine: \(engine)")
        lines.append("attempts left today: \(SpeedTestViewModel.attemptsLeftTodayValue) of \(SpeedTestViewModel.freeDailyLimit)")
        if let ok = lastSpeedTestSuccess {
            lines.append("last success: \(ok)")
        }
        if let err = lastSpeedTestError {
            lines.append("last error: \(err)")
        }
        if lastSpeedTestSuccess == nil && lastSpeedTestError == nil {
            lines.append("last run: none in this session")
        }

        lines.append("")
        lines.append("— LOCATION —")
        lines.append("services enabled: \(servicesEnabled)")
        lines.append("authorization: \(LocationAuthorizer.shared.authorizationDescription)")
        lines.append("accuracy: \(LocationAuthorizer.shared.accuracyDescription)")
        lines.append("has fix: \(LocationAuthorizer.shared.hasFix)")

        lines.append("")
        lines.append("— VPN —")
        lines.append("status: \(statusText)")
        lines.append("selected server: \(VPNService.shared.currentServer?.remark ?? "none")")
        lines.append("configs saved: \(CustomServerFoldersStore.shared.totalServers)")
        lines.append("kill switch: \(AppPreferencesStore.shared.killSwitchEnabled)")
        lines.append("auto-connect: \(AppPreferencesStore.shared.autoConnectEnabled)")
        lines.append("dns: \(AppPreferencesStore.shared.dnsProvider.rawValue)")
        if let diag = TunnelDiagnostics.readLastError(notOlderThan: 60 * 60 * 24) {
            lines.append("tunnel last error: [\(diag.stage)] \(diag.message)")
        }

        lines.append("")
        lines.append("— SUBSCRIPTION —")
        lines.append("active: \(SubscriptionService.shared.isActiveSubscription)")
        lines.append("backend entitlement: \(SubscriptionService.shared.backendEntitlementActive)")
        lines.append("servers from panel: \(SubscriptionProvider.shared.servers.count)")
        if let err = SubscriptionProvider.shared.lastError {
            lines.append("panel last error: \(err)")
        }
        lines.append("products loaded: \(SubscriptionService.shared.products.count)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers
    private static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
    }

    private static var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
    }

    private static var statusText: String {
        switch VPNService.shared.status {
        case .disconnected:      return "disconnected"
        case .connecting:        return "connecting"
        case .connected:         return "connected"
        case .disconnecting:     return "disconnecting"
        case .failed(let msg):   return "failed — \(msg)"
        }
    }
}
