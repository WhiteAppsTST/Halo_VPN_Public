import Foundation

enum VPNBackend {
    static let baseURL = URL(string: "https://vpnmanager2-production.up.railway.app")!

    struct UserState: Decodable {
        let userId: String
        let expiresAt: String?
        let isActive: Bool
        let subscriptionURL: String?
        let isNewUser: Bool?

        enum CodingKeys: String, CodingKey {
            case userId          = "user_id"
            case expiresAt       = "expires_at"
            case isActive        = "is_active"
            case subscriptionURL = "subscription_url"
            case isNewUser       = "is_new_user"
        }
    }

    enum BackendError: Error {
        case missingAppSecret
        case http(status: Int, body: String)
        case badResponse
    }

    static func register(apphudUserID: String) async throws -> UserState {
        try await request(
            path: "/guardium/users/register",
            method: "POST",
            body: ["apphud_user_id": apphudUserID]
        )
    }

    static func profile(apphudUserID: String) async throws -> UserState {
        try await request(
            path: "/guardium/users/profile",
            method: "GET",
            query: ["apphud_user_id": apphudUserID]
        )
    }

    static func sync(apphudUserID: String, signedTransaction: String) async throws -> UserState {
        try await request(
            path: "/guardium/subscription/sync",
            method: "POST",
            body: [
                "apphud_user_id": apphudUserID,
                "signed_transaction": signedTransaction
            ]
        )
    }

    private static var appSecret: String {
        (Bundle.main.object(forInfoDictionaryKey: "VPNBackendAppSecret") as? String) ?? ""
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        // Замерено: /health отвечает за 0.5 с, а /users/profile и /users/register
        // висят 15-18 с (бэк ждёт панель Remnawave). При таймауте 15 с клиент
        // гарантированно отваливался раньше сервера — в логах это
        // NSURLErrorTimedOut (-1001) на register. Плюс холодный старт Railway.
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }()

    private static func request(
        path: String,
        method: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil
    ) async throws -> UserState {
        let secret = appSecret
        guard !secret.isEmpty else { throw BackendError.missingAppSecret }

        var comps = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(secret, forHTTPHeaderField: "X-App-Secret")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw BackendError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw BackendError.http(status: http.statusCode, body: text)
        }
        return try JSONDecoder().decode(UserState.self, from: data)
    }
}
