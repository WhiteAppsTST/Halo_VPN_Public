import Foundation

/// Кэш латенси до серверов. Ключ — `rawURL` (стабильный между refresh подписки).
/// `nil` в словаре = измеряли, но был timeout. Ключ отсутствует = ещё не измеряли.
@Observable
@MainActor
final class PingCache {
    @ObservationIgnored static let shared = PingCache()

    private(set) var pings: [String: Int?] = [:]

    private init() {}

    func ping(for rawURL: String) -> Int? {
        pings[rawURL] ?? nil
    }

    /// True если для этого rawURL уже был замер (успешный или timeout).
    func wasMeasured(_ rawURL: String) -> Bool {
        pings.keys.contains(rawURL)
    }

    /// Полная очистка кеша — после этого все rawURL считаются «не измеренными».
    /// Используется для force-refresh, чтобы в UI сразу показать «...» вместо старых значений.
    func clear() {
        pings.removeAll()
    }

    /// Максимум одновременных TCP-проб. Папка может содержать сотни конфигов,
    /// и без окна мы открывали столько же сокетов разом — устройство упиралось
    /// в лимит дескрипторов, а UI подвисал.
    /// Было 8 — при такой параллельности пробы мешали друг другу и завышали
    /// результат. Четыре хватает, чтобы список заполнялся быстро.
    private static let maxConcurrentProbes = 4

    /// Параллельно замеряет пинг для переданных серверов, окном по 8 штук.
    /// Уже измеренные — не перепинговывает (если `force == false`).
    /// UI реактивно обновляется по мере готовности каждого пинга.
    func measureAll(_ servers: [VPNServerConfig], force: Bool = false) async {
        let targets = servers.filter { force || !wasMeasured($0.rawURL) }
        guard !targets.isEmpty else { return }

        await withTaskGroup(of: (String, Int?).self) { group in
            var index = 0
            let window = min(Self.maxConcurrentProbes, targets.count)

            func addTask(_ server: VPNServerConfig) {
                group.addTask {
                    let ms = await PingService.measure(host: server.host, port: server.port)
                    return (server.rawURL, ms)
                }
            }

            while index < window {
                addTask(targets[index])
                index += 1
            }

            for await (rawURL, ms) in group {
                pings[rawURL] = ms
                if index < targets.count {
                    addTask(targets[index])
                    index += 1
                }
            }
        }
    }
}
