import CoreLocation

/// Разрешение и фактический фикс геопозиции. Нужно двум местам:
///   • SpeedChecker SDK — free-версия работает ТОЛЬКО с геолокацией и падает
///     в `.locationUndefined`, если координат нет или точность «приблизительная»;
///   • NEHotspotNetwork.fetchCurrent — без Location grant всегда отдаёт nil.
@MainActor
final class LocationAuthorizer: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuthorizer()

    /// Почему геопозиция недоступна — чтобы UI показал конкретную причину,
    /// а не общее «Connection failed».
    enum Failure {
        case servicesDisabled     // геолокация выключена во всей системе
        case denied               // пользователь запретил доступ приложению
        case reducedAccuracy      // дал «Приблизительно» и отказался от точной
        case noFix                // разрешение есть, но координат так и не пришло
    }

    private let manager = CLLocationManager()
    private var authContinuations: [CheckedContinuation<Bool, Never>] = []
    private var fixContinuations: [CheckedContinuation<Bool, Never>] = []

    private override init() {
        super.init()
        manager.delegate = self
        // SDK выбирает ближайший измерительный сервер — километровой точности хватает.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    /// Текстовое состояние для отчёта диагностики.
    var authorizationDescription: String {
        switch manager.authorizationStatus {
        case .notDetermined:       return "notDetermined"
        case .restricted:          return "restricted"
        case .denied:              return "denied"
        case .authorizedAlways:    return "always"
        case .authorizedWhenInUse: return "whenInUse"
        @unknown default:          return "unknown"
        }
    }

    var accuracyDescription: String {
        switch manager.accuracyAuthorization {
        case .fullAccuracy:    return "full"
        case .reducedAccuracy: return "REDUCED (free-mode SDK will fail)"
        @unknown default:      return "unknown"
        }
    }

    var hasFix: Bool { manager.location != nil }

    /// locationServicesEnabled() блокирует поток — зовём вне main.
    static func servicesEnabled() async -> Bool {
        await Task.detached { CLLocationManager.locationServicesEnabled() }.value
    }

    var isDenied: Bool {
        switch manager.authorizationStatus {
        case .denied, .restricted: return true
        default: return false
        }
    }

    /// Полная подготовка для SpeedChecker: сервисы включены → доступ выдан →
    /// точность полная → координаты реально получены. Возвращает nil, если всё ок,
    /// иначе конкретную причину отказа.
    func prepareForSpeedTest(timeout: TimeInterval = 10) async -> Failure? {
        // locationServicesEnabled() блокирующий — как и в сэмпле SDK, уводим с main.
        guard await Self.servicesEnabled() else { return .servicesDisabled }

        guard await ensureAuthorization() else { return .denied }

        await ensureFullAccuracy(purposeKey: "SpeedTest")
        guard manager.accuracyAuthorization == .fullAccuracy else { return .reducedAccuracy }

        guard await waitForFix(timeout: timeout) else { return .noFix }
        return nil
    }

    /// Запрашивает доступ (если ещё не спрашивали) и начинает обновление позиции.
    @discardableResult
    func ensureAuthorization() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            // Ждать могут сразу двое (Privacy Center открывается и запрашивает
            // геопозицию, а пользователь параллельно жмёт «Start test»).
            // Оба встают в очередь; системный запрос показываем только один раз.
            let alreadyAsking = !authContinuations.isEmpty
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                authContinuations.append(cont)
                if !alreadyAsking { manager.requestWhenInUseAuthorization() }
            }
            if granted { manager.startUpdatingLocation() }
            return granted
        @unknown default:
            return false
        }
    }

    /// Ждём НАСТОЯЩИЕ координаты, а не только факт разрешения: SDK стартует
    /// с выбора ближайшего сервера, и без фикса тест падает сразу же.
    private func waitForFix(timeout: TimeInterval) async -> Bool {
        if manager.location != nil { return true }

        manager.startUpdatingLocation()
        manager.requestLocation()

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.resumeFixWaiters(false) }
        }
        defer { timeoutTask.cancel() }

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            fixContinuations.append(cont)
        }
    }

    private func resumeFixWaiters(_ value: Bool) {
        guard !fixContinuations.isEmpty else { return }
        let waiters = fixContinuations
        fixContinuations = []
        waiters.forEach { $0.resume(returning: value) }
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
    }

    /// При «приблизительной» геопозиции SDK не находит сервер, а
    /// NEHotspotNetwork.fetchCurrent отдаёт nil. Просим временную полную точность
    /// (purpose key объявлен в Info.plist).
    func ensureFullAccuracy(purposeKey: String = "WiFiInfo") async {
        guard isAuthorized, manager.accuracyAuthorization == .reducedAccuracy else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey) { _ in
                cont.resume()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        let granted = status == .authorizedAlways || status == .authorizedWhenInUse
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.authContinuations.isEmpty {
                let waiters = self.authContinuations
                self.authContinuations = []
                waiters.forEach { $0.resume(returning: granted) }
            }
            if !granted { self.resumeFixWaiters(false) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !locations.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.resumeFixWaiters(true)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.resumeFixWaiters(false)
        }
    }
}
