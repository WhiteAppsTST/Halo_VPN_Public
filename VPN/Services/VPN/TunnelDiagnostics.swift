import Foundation

/// Канал передачи ошибок PT extension → main app через App Group UserDefaults.
/// В PT extension существует дубль этого файла (нельзя шарить код без SPM-пакета).
enum TunnelDiagnostics {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppConstants.Bundle.appGroup)
    }

    static func recordError(stage: String, message: String) {
        guard let d = defaults else { return }
        d.set(message, forKey: AppConstants.UDKeys.Shared.tunnelLastErrorMessage)
        d.set(stage,   forKey: AppConstants.UDKeys.Shared.tunnelLastErrorStage)
        d.set(Date().timeIntervalSince1970, forKey: AppConstants.UDKeys.Shared.tunnelLastErrorAt)
    }

    /// Читает последнюю ошибку, если она записана не позднее `seconds` назад.
    /// TTL нужен чтобы отличить свежую ошибку коннекта от обычного disconnect.
    static func readLastError(notOlderThan seconds: TimeInterval = 30) -> (stage: String, message: String)? {
        guard let d = defaults else { return nil }
        let at = d.double(forKey: AppConstants.UDKeys.Shared.tunnelLastErrorAt)
        guard at > 0, Date().timeIntervalSince1970 - at <= seconds else { return nil }
        guard let msg = d.string(forKey: AppConstants.UDKeys.Shared.tunnelLastErrorMessage), !msg.isEmpty else { return nil }
        return (d.string(forKey: AppConstants.UDKeys.Shared.tunnelLastErrorStage) ?? "", msg)
    }

    static func clear() {
        guard let d = defaults else { return }
        d.removeObject(forKey: AppConstants.UDKeys.Shared.tunnelLastErrorMessage)
        d.removeObject(forKey: AppConstants.UDKeys.Shared.tunnelLastErrorStage)
        d.removeObject(forKey: AppConstants.UDKeys.Shared.tunnelLastErrorAt)
    }
}
