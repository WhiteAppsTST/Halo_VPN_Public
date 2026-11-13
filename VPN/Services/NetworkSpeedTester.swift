import Foundation

/// Собственный замер пропускной способности поверх URLSession.
///
/// Зачем свой, а не SpeedChecker: free-режим их SDK работает только при
/// включённой геолокации с ПОЛНОЙ точностью и реальными координатами, а также
/// шлёт данные на их серверы. На устройстве это регулярно оборачивается
/// `.locationUndefined` без внятной причины. Здесь же обычный HTTPS к
/// публичным эндпоинтам Cloudflare: меряется ровно тот канал, которым сейчас
/// пользуется приложение — включая активный VPN-туннель.
///
/// Методика: качаем/заливаем поток фиксированное время и делим объём на время.
/// Первые 500 мс отбрасываем — на них приходится TCP/TLS-хендшейк и разгон
/// окна, из-за чего результат занижался бы.
final class NetworkSpeedTester: NSObject, @unchecked Sendable {

    struct Result {
        let downloadMbps: Double
        let uploadMbps: Double
        let latencyMs: Int?
    }

    enum Failure: LocalizedError {
        case noData
        case http(Int)
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .noData:            return String(localized: "The test server returned no data.")
            case .http(let code):    return String(localized: "The test server replied with HTTP \(code).")
            case .transport(let m):  return m
            }
        }
    }

    private static let downloadURL = "https://speed.cloudflare.com/__down?bytes="
    private static let uploadURL   = "https://speed.cloudflare.com/__up"
    /// ВАЖНО: эндпоинт отдаёт 403 на запросы больше ~26 МБ (проверено:
    /// 26_214_400 → 200, 100_000_000 → 403). Поэтому качаем блоками по 25 МиБ
    /// подряд, пока не истечёт отведённое время, и складываем объём.
    private static let downloadChunkBytes = 26_214_400
    private static let uploadChunkBytes = 8_000_000
    /// Предохранитель: столько блоков максимум за один замер.
    private static let maxChunks = 40
    /// Хендшейк и разгон TCP-окна не должны попадать в результат.
    private static let warmup: TimeInterval = 0.5

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.timeoutIntervalForRequest = 20
        cfg.allowsCellularAccess = true
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    // Состояние текущего замера. Доступ только под lock.
    private let lock = NSLock()
    private var receivedBytes = 0
    private var sentBytes = 0
    private var startedAt: Date?
    private var warmupBytes = 0
    private var warmupPassedAt: Date?
    private var progressHandler: ((Double) -> Void)?
    private var lastFailure: Failure?

    deinit { session.invalidateAndCancel() }

    // MARK: - Public

    /// Полный прогон: latency → download → upload.
    /// `onProgress` вызывается на главном потоке с текущей скоростью в Мбит/с.
    func run(duration: TimeInterval = 6,
             onProgress: @escaping @MainActor (Double) -> Void) async throws -> Result {
        let latency = await measureLatency()

        let download = try await measureDownload(duration: duration, onProgress: onProgress)
        try Task.checkCancellation()

        let upload = try await measureUpload(duration: duration, onProgress: onProgress)
        try Task.checkCancellation()

        return Result(downloadMbps: download, uploadMbps: upload, latencyMs: latency)
    }

    // MARK: - Latency

    /// Минимум из трёх измерений time-to-first-byte — так случайный всплеск
    /// в сети не завышает результат.
    func measureLatency(probes: Int = 3) async -> Int? {
        guard let url = URL(string: Self.downloadURL + "0") else { return nil }
        var best: TimeInterval?

        for _ in 0..<probes {
            if Task.isCancelled { break }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 10

            let started = Date()
            do {
                let (_, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                let elapsed = Date().timeIntervalSince(started)
                best = min(best ?? elapsed, elapsed)
            } catch {
                continue
            }
        }
        return best.map { Int($0 * 1000) }
    }

    // MARK: - Download

    func measureDownload(duration: TimeInterval,
                         onProgress: @escaping @MainActor (Double) -> Void) async throws -> Double {
        guard let url = URL(string: Self.downloadURL + String(Self.downloadChunkBytes)) else {
            throw Failure.transport("Bad URL")
        }
        resetCounters(onProgress: onProgress)

        try await pump(duration: duration) { [weak self] in
            guard let self else { return nil }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            return self.session.dataTask(with: request)
        }

        let (bytes, seconds) = snapshotDownload()
        guard bytes > 0, seconds > 0.05 else { throw lastFailure ?? Failure.noData }
        return Double(bytes) * 8 / seconds / 1_000_000
    }

    // MARK: - Upload

    func measureUpload(duration: TimeInterval,
                       onProgress: @escaping @MainActor (Double) -> Void) async throws -> Double {
        guard let url = URL(string: Self.uploadURL) else { throw Failure.transport("Bad URL") }
        let payload = Data(count: Self.uploadChunkBytes)

        resetCounters(onProgress: onProgress)

        try await pump(duration: duration) { [weak self] in
            guard let self else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            return self.session.uploadTask(with: request, from: payload)
        }

        let (bytes, seconds) = snapshotUpload()
        guard bytes > 0, seconds > 0.05 else { throw lastFailure ?? Failure.noData }
        return Double(bytes) * 8 / seconds / 1_000_000
    }

    // MARK: - Общий движок замера

    /// Гоняет блоки один за другим, пока не выйдет время. Счётчики общие,
    /// поэтому скорость считается по суммарному объёму за вычетом прогрева.
    private func pump(duration: TimeInterval,
                      makeTask: @escaping () -> URLSessionTask?) async throws {
        beginMeasurement()

        let deadline = Date().addingTimeInterval(Self.warmup + duration)
        var chunks = 0

        while Date() < deadline, chunks < Self.maxChunks {
            try Task.checkCancellation()
            guard let task = makeTask() else { break }
            chunks += 1

            task.resume()
            while Date() < deadline {
                if task.state == .completed { break }
                if Task.isCancelled { task.cancel(); throw CancellationError() }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            if task.state != .completed { task.cancel() }

            // Ошибку запоминаем, но продолжаем: одиночный сбой блока не должен
            // рушить весь замер, если остальные прошли.
            if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                record(failure: .http(http.statusCode))
                break
            }
            if let error = task.error as NSError?, error.code != NSURLErrorCancelled {
                record(failure: .transport(error.localizedDescription))
                break
            }
        }
    }

    /// Синхронные хелперы: брать NSLock прямо в async-функции нельзя —
    /// компилятор справедливо ругается, а в Swift 6 это уже ошибка.
    private func beginMeasurement() {
        lock.lock()
        startedAt = Date()
        lastFailure = nil
        lock.unlock()
    }

    private func record(failure: Failure) {
        lock.lock()
        lastFailure = failure
        lock.unlock()
    }

    private func resetCounters(onProgress: @escaping @MainActor (Double) -> Void) {
        lock.lock()
        receivedBytes = 0
        sentBytes = 0
        warmupBytes = 0
        warmupPassedAt = nil
        startedAt = nil
        progressHandler = { mbps in
            Task { @MainActor in onProgress(mbps) }
        }
        lock.unlock()
    }

    private func snapshotDownload() -> (Int, TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        guard let from = warmupPassedAt else { return (0, 0) }
        return (receivedBytes - warmupBytes, Date().timeIntervalSince(from))
    }

    private func snapshotUpload() -> (Int, TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        guard let from = warmupPassedAt else { return (0, 0) }
        return (sentBytes - warmupBytes, Date().timeIntervalSince(from))
    }

    /// Учитывает очередную порцию и отдаёт текущую скорость наружу.
    private func account(total: Int) {
        lock.lock()
        guard let started = startedAt else { lock.unlock(); return }

        let now = Date()
        if warmupPassedAt == nil, now.timeIntervalSince(started) >= Self.warmup {
            warmupPassedAt = now
            warmupBytes = total
        }

        var mbps: Double?
        if let from = warmupPassedAt {
            let seconds = now.timeIntervalSince(from)
            if seconds > 0.2 {
                mbps = Double(total - warmupBytes) * 8 / seconds / 1_000_000
            }
        }
        let handler = progressHandler
        lock.unlock()

        if let mbps { handler?(mbps) }
    }
}

// MARK: - URLSession delegates

extension NetworkSpeedTester: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        receivedBytes += data.count
        let total = receivedBytes
        lock.unlock()
        account(total: total)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        lock.lock()
        sentBytes = Int(totalBytesSent)
        let total = sentBytes
        lock.unlock()
        account(total: total)
    }
}
