import SwiftUI
import SpeedcheckerSDK
import CoreLocation

@MainActor
@Observable
final class SpeedTestViewModel {

    enum Step: Int, CaseIterable, Identifiable {
        case speed, ip, dns
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .speed: return "SPEED"
            case .ip:    return "IP"
            case .dns:   return "DNS"
            }
        }
    }

    enum Status: Equatable {
        case idle
        case running(Step)
        case done
        case failed(Step)
    }

    enum ChipState: Equatable {
        case pending
        case active
        case completed
        case failed
        case skipped
    }

    var status: Status = .idle
    var completedSteps: Set<Step> = []

    /// Точная причина падения шага SPEED. Free-версия SpeedChecker SDK
    /// не стартует без геолокации — раньше это выглядело как «Connection failed».
    private(set) var speedFailureReason: String?

    var currentSpeedMbps: Double = 0

    var downloadMbps: Double?
    var uploadMbps: Double?
    var endpointIP: String?

    var failedStep: Step? {
        if case .failed(let step) = status { return step }
        return nil
    }

    var isFailed: Bool { failedStep != nil }

    func chipState(for step: Step) -> ChipState {
        if case .running(let s) = status, s == step { return .active }
        if let failed = failedStep {
            if step == failed { return .failed }
            return step.rawValue > failed.rawValue ? .skipped : .completed
        }
        if completedSteps.contains(step) { return .completed }
        return .pending
    }

    var vpnServerLabel: String {
        guard let s = VPNService.shared.currentServer else { return "—" }
        if let iso = s.countryCode, !iso.isEmpty {
            return "\(iso) · \(s.remark)"
        }
        return s.remark
    }

    var protocolLabel: String {
        VPNService.shared.currentServer?.kind.rawValue.uppercased() ?? "—"
    }

    var endpointLabel: String { endpointIP ?? "—" }

    /// Сколько бесплатных запусков осталось сегодня. nil — у премиума лимита нет.
    var attemptsCaption: String? {
        guard !SubscriptionService.shared.isActiveSubscription else { return nil }
        let left = attemptsLeftToday
        return left > 0
            ? String(localized: "\(left) of \(Self.freeDailyLimit) free tests left today")
            : String(localized: "Daily free limit reached — upgrade for unlimited tests")
    }

    /// Суммарный трафик текущей VPN-сессии (реальные счётчики utun).
    var sessionTrafficLabel: String {
        guard VPNService.shared.status.isActive else { return "—" }
        let stats = SessionStatsTracker.shared
        return "↓ \(Self.formatBytes(stats.sessionDownloadBytes))  ↑ \(Self.formatBytes(stats.sessionUploadBytes))"
    }

    /// Latency до публичного эндпоинта через активный туннель.
    var tunnelLatencyLabel: String {
        guard VPNService.shared.status.isActive else { return "—" }
        return SessionStatsTracker.shared.latencyMs.map { "\($0) ms" } ?? "…"
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: Int64(bytes))
    }

    var downloadLabel: String { downloadMbps.map { String(format: "%.0f Mbps", $0) } ?? "—" }
    var uploadLabel:   String { uploadMbps.map   { String(format: "%.0f Mbps", $0) } ?? "—" }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }
    var isDone: Bool { status == .done }

    var actionButtonTitle: LocalizedStringResource {
        switch status {
        case .idle:        return "Start test"
        case .running:     return "Testing…"
        case .done:        return "Test again"
        case .failed(.speed): return "Retry"
        case .failed:      return "Reconnect"
        }
    }

    var showsGaugeValue: Bool {
        if case .running(.speed) = status { return true }
        if completedSteps.contains(.speed) { return true }
        return false
    }

    var errorBanner: ErrorBannerModel? {
        guard let step = failedStep else { return nil }
        switch step {
        case .speed:
            return ErrorBannerModel(
                text: "Connection failed",
                textColor: Color(hex: "FF7070"),
                background: Color(red: 1, green: 112 / 255, blue: 112 / 255, opacity: 0.08),
                border: Color(red: 1, green: 112 / 255, blue: 112 / 255, opacity: 0.25),
                iconColor: Color(hex: "FF7070")
            )
        case .ip:
            return ErrorBannerModel(
                text: "Connection tunnel active but IP masking failed",
                textColor: Color(hex: "F0A020"),
                background: Color(red: 240 / 255, green: 160 / 255, blue: 32 / 255, opacity: 0.08),
                border: Color(red: 240 / 255, green: 160 / 255, blue: 32 / 255, opacity: 0.25),
                iconColor: Color(hex: "F0A020")
            )
        case .dns:
            return ErrorBannerModel(
                text: "DNS leak detected",
                textColor: Color(hex: "F0A020"),
                background: Color(red: 240 / 255, green: 160 / 255, blue: 32 / 255, opacity: 0.08),
                border: Color(red: 240 / 255, green: 160 / 255, blue: 32 / 255, opacity: 0.25),
                iconColor: Color(hex: "F0A020")
            )
        }
    }

    var errorCard: ErrorCardModel? {
        guard let step = failedStep else { return nil }
        switch step {
        case .speed:
            return ErrorCardModel(
                title: "Test Failed",
                message: speedFailureReason
                    ?? "The test server could not be reached. Check your network or try again.",
                titleColor: Color(hex: "E03A3A"),
                messageColor: Color(hex: "A36060"),
                background: Color(red: 224 / 255, green: 58 / 255, blue: 58 / 255, opacity: 0.08),
                border: Color(red: 224 / 255, green: 58 / 255, blue: 58 / 255, opacity: 0.2),
                iconColor: Color(hex: "E03A3A")
            )
        case .ip:
            return ErrorCardModel(
                title: "Real IP Exposed",
                message: "Your real IP address is visible to external services. Reconnect or enable Kill Switch in settings.",
                titleColor: Color(hex: "F0A020"),
                messageColor: Color(hex: "B8874A"),
                background: Color(red: 240 / 255, green: 160 / 255, blue: 32 / 255, opacity: 0.08),
                border: Color(red: 240 / 255, green: 160 / 255, blue: 32 / 255, opacity: 0.2),
                iconColor: Color(hex: "F0A020")
            )
        case .dns:
            return ErrorCardModel(
                title: "DNS Leak Risk",
                message: "Your DNS queries are visible to your ISP. Switch to a server with DNS leak protection enabled.",
                titleColor: Color(hex: "F0A020"),
                messageColor: Color(hex: "B8874A"),
                background: Color(red: 240 / 255, green: 160 / 255, blue: 32 / 255, opacity: 0.08),
                border: Color(red: 240 / 255, green: 160 / 255, blue: 32 / 255, opacity: 0.2),
                iconColor: Color(hex: "F0A020")
            )
        }
    }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var speedTest: InternetSpeedTest?
    @ObservationIgnored private var delegateProxy: SpeedTestDelegateProxy?
    @ObservationIgnored private var speedContinuation: CheckedContinuation<SpeedTestResult?, Never>?
    @ObservationIgnored private let locationGate = LocationAuthorizer.shared
    @ObservationIgnored private var builtInTester: NetworkSpeedTester?

    // MARK: - Free-tier daily limit
    /// Максимум запусков теста в сутки без активной подписки.
    /// Премиум-юзеры этой проверки не видят.
    static let freeDailyLimit: Int = 3

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Кол-во сегодняшних запусков. Читает актуальный день, при смене даты — обнуляет.
    var attemptsUsedToday: Int {
        let today = Self.dayFormatter.string(from: Date())
        let saved = UserDefaults.standard.string(forKey: AppConstants.UDKeys.speedTestLastDay)
        if saved != today { return 0 }
        return UserDefaults.standard.integer(forKey: AppConstants.UDKeys.speedTestCountToday)
    }

    var attemptsLeftToday: Int {
        max(0, Self.freeDailyLimit - attemptsUsedToday)
    }

    /// Тот же остаток, но без экземпляра — нужен отчёту диагностики.
    static var attemptsLeftTodayValue: Int {
        let today = dayFormatter.string(from: Date())
        let saved = UserDefaults.standard.string(forKey: AppConstants.UDKeys.speedTestLastDay)
        let used = saved == today ? UserDefaults.standard.integer(forKey: AppConstants.UDKeys.speedTestCountToday) : 0
        return max(0, freeDailyLimit - used)
    }

    /// Можно ли запустить ещё один тест: премиум — да, иначе есть ли остаток на сегодня.
    var canRunTest: Bool {
        SubscriptionService.shared.isActiveSubscription || attemptsLeftToday > 0
    }

    private func incrementDailyCounter() {
        let today = Self.dayFormatter.string(from: Date())
        let ud = UserDefaults.standard
        let saved = ud.string(forKey: AppConstants.UDKeys.speedTestLastDay)
        let current: Int = (saved == today)
            ? ud.integer(forKey: AppConstants.UDKeys.speedTestCountToday)
            : 0
        ud.set(today, forKey: AppConstants.UDKeys.speedTestLastDay)
        ud.set(current + 1, forKey: AppConstants.UDKeys.speedTestCountToday)
    }

    func actionButtonTapped() {
        switch status {
        case .idle, .done, .failed:
            guard canRunTest else {
                SubscriptionService.shared.showPaywall(.main)
                return
            }
            startFullTest()
        case .running:
            break
        }
    }

    private func startFullTest() {
        task?.cancel()

        withAnimation(.easeInOut(duration: 0.3)) {
            status = .idle
            completedSteps = []
            downloadMbps = nil
            uploadMbps = nil
            endpointIP = nil
            currentSpeedMbps = 0
            speedFailureReason = nil
        }

        task = Task { [weak self] in
            guard let self else { return }

            // 0. Геолокация. Free-версия SpeedChecker SDK работает только с ней:
            //    без КООРДИНАТ (а не просто разрешения) и без полной точности
            //    startFreeTest мгновенно возвращает .locationUndefined.
            if Self.requiresLocation,
               let failure = await self.locationGate.prepareForSpeedTest() {
                guard !Task.isCancelled else { return }
                self.speedFailureReason = Self.describe(failure)
                withAnimation(.easeInOut(duration: 0.35)) { self.status = .failed(.speed) }
                return
            }
            guard !Task.isCancelled else { return }

            // Списываем попытку только когда тест реально стартует.
            self.incrementDailyCounter()

            // 1. SPEED
            var sdkIP: String?
            let speedOK: Bool
            if Self.useSpeedCheckerSDK {
                let speedResult = await self.runSpeedStep()
                sdkIP = speedResult?.ipAddress
                speedOK = speedResult != nil
            } else {
                speedOK = await self.runSpeedStepBuiltIn()
            }
            guard !Task.isCancelled else { return }
            if !speedOK {
                withAnimation(.easeInOut(duration: 0.35)) { self.status = .failed(.speed) }
                return
            }

            // 2. IP — из результата SDK либо запросом наружу.
            let ipOK = await self.runIPStep(fromSDK: sdkIP)
            guard !Task.isCancelled else { return }
            if !ipOK {
                withAnimation(.easeInOut(duration: 0.35)) { self.status = .failed(.ip) }
                return
            }

            // 3. DNS-leak — сравниваем страну exit-IP (Cloudflare trace)
            //    со страной DNS-резолвера (Cloudflare DoH whoami).
            let dnsOK = await self.runDNSStep()
            guard !Task.isCancelled else { return }
            if !dnsOK {
                withAnimation(.easeInOut(duration: 0.35)) { self.status = .failed(.dns) }
                return
            }

            withAnimation(.easeInOut(duration: 0.35)) { self.status = .done }
        }
    }

    /// Ключ Speedchecker из Info.plist. Пусто/нет ключа — работаем в free-режиме.
    static var licenseKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SpeedcheckerLicenseKey") as? String else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// Встроенный движок (Cloudflare) геолокацию не требует вообще.
    /// Она нужна только SpeedChecker SDK в free-режиме — а туда мы идём,
    /// лишь если в Info.plist задан ключ и включён режим SDK.
    static var requiresLocation: Bool { useSpeedCheckerSDK && licenseKey == nil }

    /// Движок замера: свой (по умолчанию) или SpeedChecker.
    /// Переключается ключом `UseSpeedCheckerSDK` в Info.plist.
    static var useSpeedCheckerSDK: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UseSpeedCheckerSDK") as? Bool) ?? false
    }

    // MARK: - Step 1: замер скорости
    /// Возвращает true при успехе. Скорости кладутся в download/uploadMbps.
    private func runSpeedStepBuiltIn() async -> Bool {
        withAnimation(.easeInOut(duration: 0.35)) { status = .running(.speed) }

        let tester = NetworkSpeedTester()
        builtInTester = tester
        defer { builtInTester = nil }

        do {
            let result = try await tester.run { [weak self] mbps in
                self?.onDownloadProgress(mbps: mbps)
            }
            guard !Task.isCancelled else { return false }

            DiagnosticsReport.recordSpeedTestSuccess(downMbps: result.downloadMbps,
                                                     upMbps: result.uploadMbps)
            withAnimation(.easeInOut(duration: 0.35)) {
                currentSpeedMbps = result.downloadMbps
                downloadMbps = result.downloadMbps
                uploadMbps = result.uploadMbps
                _ = completedSteps.insert(.speed)
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            speedFailureReason = error.localizedDescription
            DiagnosticsReport.recordSpeedTestError(code: -2,
                                                   name: "builtin",
                                                   message: error.localizedDescription)
            return false
        }
    }

    // MARK: - Step 1 (альтернатива): SpeedcheckerSDK
    private func runSpeedStep() async -> SpeedTestResult? {
        withAnimation(.easeInOut(duration: 0.35)) { status = .running(.speed) }

        let proxy = SpeedTestDelegateProxy(vm: self)
        self.delegateProxy = proxy

        // Лицензионный ключ Speedchecker (Info.plist → SpeedcheckerLicenseKey).
        // С ключом SDK работает БЕЗ геолокации и без суточных ограничений
        // free-режима; без ключа — free-режим, которому геопозиция обязательна.
        let test: InternetSpeedTest
        let isLicensed: Bool
        if let key = Self.licenseKey {
            test = InternetSpeedTest(licenseKey: key, delegate: proxy)
            isLicensed = true
        } else {
            test = InternetSpeedTest(delegate: proxy)
            isLicensed = false
        }
        self.speedTest = test

        let result: SpeedTestResult? = await withCheckedContinuation { cont in
            self.speedContinuation = cont
            let completion: (SpeedTestError) -> Void = { error in
                if error != .ok {
                    Task { @MainActor in
                        self.speedFailureReason = Self.describe(error)
                        self.finishSpeed(result: nil)
                    }
                }
            }
            if isLicensed {
                test.start(completion)
            } else {
                test.startFreeTest(completion)
            }
        }

        self.speedTest = nil
        self.delegateProxy = nil
        return result
    }

    /// Человеческий текст вместо безликого «Connection failed».
    /// Заодно кладём сырой код SDK в диагностику — по нему видно точную причину.
    private static func describe(_ error: SpeedTestError) -> String {
        let text = describeText(error)
        DiagnosticsReport.recordSpeedTestError(code: error.rawValue, name: "\(error)", message: text)
        return text
    }

    private static func describeText(_ error: SpeedTestError) -> String {
        switch error {
        case .locationUndefined:
            return String(localized: "Location is unavailable. The free speed test engine needs it to select a server — allow location access and try again.")
        case .invalidlicenseKey:
            return String(localized: "The speed test engine rejected the license key.")
        case .invalidServers, .invalidSettings:
            return String(localized: "No measurement server is available right now. Try again in a minute.")
        case .inProgress:
            return String(localized: "A speed test is already running.")
        case .cancelled:
            return String(localized: "The speed test was cancelled.")
        case .appISPMismatch:
            return String(localized: "This network isn't supported by the measurement engine.")
        default:
            return String(localized: "The test server could not be reached. Check your connection and try again.")
        }
    }

    /// Причина, по которой не удалось подготовить геопозицию для SDK.
    private static func describe(_ failure: LocationAuthorizer.Failure) -> String {
        let text = describeText(failure)
        DiagnosticsReport.recordSpeedTestError(code: -1, name: "location.\(failure)", message: text)
        return text
    }

    private static func describeText(_ failure: LocationAuthorizer.Failure) -> String {
        switch failure {
        case .servicesDisabled:
            return String(localized: "Location Services are turned off. Enable them in Settings → Privacy & Security → Location Services — the free speed test engine needs your location to pick a measurement server.")
        case .denied:
            return String(localized: "Location access is denied. Allow it in Settings → Halo Hub → Location — the free speed test engine needs it to pick a measurement server.")
        case .reducedAccuracy:
            return String(localized: "Precise Location is off. Turn it on in Settings → Halo Hub → Location — the speed test can't pick a server from an approximate position.")
        case .noFix:
            return String(localized: "Couldn't determine your location. Move somewhere with a better signal and try again.")
        }
    }

    // Called from delegate proxy on MainActor.
    fileprivate func onDownloadProgress(mbps: Double) {
        withAnimation(.linear(duration: 0.15)) {
            currentSpeedMbps = min(1000, max(0, mbps))
        }
    }

    fileprivate func onTestFinish(result: SpeedTestResult) {
        let down = result.downloadSpeed.mbps
        let up   = result.uploadSpeed.mbps
        DiagnosticsReport.recordSpeedTestSuccess(downMbps: down, upMbps: up)
        withAnimation(.easeInOut(duration: 0.35)) {
            currentSpeedMbps = down
            downloadMbps = down
            uploadMbps = up
            completedSteps.insert(.speed)
        }
        finishSpeed(result: result)
    }

    fileprivate func onTestError(_ error: SpeedTestError) {
        speedFailureReason = Self.describe(error)
        finishSpeed(result: nil)
    }

    private func finishSpeed(result: SpeedTestResult?) {
        speedContinuation?.resume(returning: result)
        speedContinuation = nil
    }

    // MARK: - Step 2: IP
    private func runIPStep(fromSDK: String?) async -> Bool {
        withAnimation(.easeInOut(duration: 0.35)) { status = .running(.ip) }

        if let ip = fromSDK, !ip.isEmpty {
            withAnimation(.easeInOut(duration: 0.35)) {
                endpointIP = ip
                completedSteps.insert(.ip)
            }
            return true
        }

        // Fallback: api.ipify.org
        do {
            var req = URLRequest(url: URL(string: "https://api.ipify.org?format=json")!)
            req.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: req)
            struct Resp: Decodable { let ip: String }
            let ip = try JSONDecoder().decode(Resp.self, from: data).ip
            withAnimation(.easeInOut(duration: 0.35)) {
                endpointIP = ip
                completedSteps.insert(.ip)
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Step 3: DNS-leak
    private func runDNSStep() async -> Bool {
        withAnimation(.easeInOut(duration: 0.35)) { status = .running(.dns) }

        async let exitInfo = fetchCloudflareTrace()
        async let dnsInfo  = fetchDNSResolverInfo()
        let exit = await exitInfo
        let dns  = await dnsInfo

        // Если запрос не прошёл — это сетевая ошибка, а не утечка. Раньше
        // любой таймаут показывался как «DNS leak detected».
        guard let exitCC = exit?.countryCode,
              let dnsCC  = dns?.countryCode else {
            withAnimation(.easeInOut(duration: 0.35)) {
                _ = completedSteps.insert(.dns)
            }
            return true
        }

        let leak = exitCC.uppercased() != dnsCC.uppercased()
        if leak { return false }

        withAnimation(.easeInOut(duration: 0.35)) {
            _ = completedSteps.insert(.dns)
        }
        return true
    }

    /// GET https://1.1.1.1/cdn-cgi/trace → парсим `ip=` и `loc=` (страна exit-IP).
    private func fetchCloudflareTrace() async -> (ip: String, countryCode: String)? {
        var req = URLRequest(url: URL(string: "https://1.1.1.1/cdn-cgi/trace")!)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            var ip: String?
            var loc: String?
            for line in text.split(separator: "\n") {
                let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2 else { continue }
                if kv[0] == "ip"  { ip  = kv[1] }
                if kv[0] == "loc" { loc = kv[1] }
            }
            guard let ip, let loc else { return nil }
            return (ip, loc)
        } catch {
            return nil
        }
    }

    /// GET https://cloudflare-dns.com/dns-query?name=whoami.cloudflare&type=TXT
    /// Возвращает страну DNS-резолвера (двухбуквенный ISO).
    private func fetchDNSResolverInfo() async -> (ip: String, countryCode: String)? {
        var comps = URLComponents(string: "https://cloudflare-dns.com/dns-query")!
        comps.queryItems = [
            URLQueryItem(name: "name", value: "whoami.cloudflare"),
            URLQueryItem(name: "type", value: "TXT")
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue("application/dns-json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            struct DoHAnswer: Decodable { let data: String }
            struct DoHResp: Decodable { let Answer: [DoHAnswer]? }
            let resp = try JSONDecoder().decode(DoHResp.self, from: data)
            // Ожидаемый data: `"104.28.171.29 US"` (в кавычках).
            guard let raw = resp.Answer?.first?.data else { return nil }
            let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let parts = cleaned.split(separator: " ")
            guard parts.count >= 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        } catch {
            return nil
        }
    }
}

// MARK: - SpeedcheckerSDK delegate proxy

private final class SpeedTestDelegateProxy: NSObject, InternetSpeedTestDelegate {
    weak var vm: SpeedTestViewModel?

    init(vm: SpeedTestViewModel) { self.vm = vm }

    func internetTestError(error: SpeedTestError) {
        Task { @MainActor [weak vm] in vm?.onTestError(error) }
    }

    func internetTestFinish(result: SpeedTestResult) {
        Task { @MainActor [weak vm] in vm?.onTestFinish(result: result) }
    }

    func internetTestReceived(servers: [SpeedTestServer]) {}

    func internetTestSelected(server: SpeedTestServer, latency: Int, jitter: Int) {}

    func internetTestDownloadStart() {}
    func internetTestDownloadFinish() {}
    func internetTestDownload(progress: Double, speed: SpeedTestSpeed) {
        let mbps = speed.mbps
        Task { @MainActor [weak vm] in vm?.onDownloadProgress(mbps: mbps) }
    }

    func internetTestUploadStart() {}
    func internetTestUploadFinish() {}
    func internetTestUpload(progress: Double, speed: SpeedTestSpeed) {}
}

struct ErrorBannerModel: Equatable {
    let text: String
    let textColor: Color
    let background: Color
    let border: Color
    let iconColor: Color
}

struct ErrorCardModel: Equatable {
    let title: String
    let message: String
    let titleColor: Color
    let messageColor: Color
    let background: Color
    let border: Color
    let iconColor: Color
}
