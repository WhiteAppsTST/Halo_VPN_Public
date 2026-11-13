import Foundation

/// Канал ошибок PT extension → main app через App Group UserDefaults.
/// Дубль файла из main app — таргеты не шарят код без SPM-пакета.
enum TunnelDiagnostics {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: PTConstants.appGroup)
    }

    static func recordError(stage: String, message: String) {
        guard let d = defaults else { return }
        d.set(message, forKey: PTConstants.UDKeys.tunnelLastErrorMessage)
        d.set(stage,   forKey: PTConstants.UDKeys.tunnelLastErrorStage)
        d.set(Date().timeIntervalSince1970, forKey: PTConstants.UDKeys.tunnelLastErrorAt)
    }

    static func clear() {
        guard let d = defaults else { return }
        d.removeObject(forKey: PTConstants.UDKeys.tunnelLastErrorMessage)
        d.removeObject(forKey: PTConstants.UDKeys.tunnelLastErrorStage)
        d.removeObject(forKey: PTConstants.UDKeys.tunnelLastErrorAt)
    }
}
