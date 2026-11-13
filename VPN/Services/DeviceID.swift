import UIKit

enum DeviceID {

    /// Стабильный идентификатор vendor+device. Сбрасывается только при удалении
    /// всех приложений vendor'а с устройства. Идёт в header `x-hwid` к бэку.
    static var hwid: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
    }

    static var os: String { "iOS" }

    static var osVersion: String {
        UIDevice.current.systemVersion
    }

    /// Машинный идентификатор модели, e.g. "iPhone15,3".
    static var model: String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        let chars: [Int8] = mirror.children.compactMap { $0.value as? Int8 }
        let bytes = chars.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
        #endif
    }
}
