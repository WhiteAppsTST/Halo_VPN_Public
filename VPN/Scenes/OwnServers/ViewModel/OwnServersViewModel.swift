import SwiftUI
import UIKit

@MainActor
@Observable
final class OwnServersViewModel {

    // MARK: - Sub-screen presentation flags
    var showFileImporter: Bool = false
    var showScanner: Bool = false
    var showManualEd: Bool = false
    var showAddServerSheet: Bool = false

    // MARK: - Alerts / errors
    var alert: AppAlertModel?

    // MARK: - Manual entry form
    var manualForm = ManualEdFormState()
    private(set) var manualLastError: String?

    // MARK: - Custom servers
    var selectedServerId: UUID? { VPNService.shared.currentServer?.id }

    // MARK: - Rename folder alert (native TextField alert)
    var showRenameFolderAlert: Bool = false
    var renameFolderText: String = ""
    private(set) var renameFolderId: UUID?

    // MARK: - Dependencies
    @ObservationIgnored private let foldersStore = CustomServerFoldersStore.shared
    @ObservationIgnored private let subscription = SubscriptionService.shared

    // MARK: - Free-tier limit
    /// Максимум одного собственного конфига без подписки. Удалять и добавлять
    /// заново можно свободно, но одновременно в списке не более 1.
    static let freeTierServerLimit: Int = 1

    private var totalServers: Int { foldersStore.totalServers }

    /// Разрешено ли добавить N новых серверов с учётом текущего лимита.
    private func canAdd(count: Int) -> Bool {
        if subscription.isActiveSubscription { return true }
        return totalServers + count <= Self.freeTierServerLimit
    }

    // MARK: - VPN connection (read from VPNService — reactive via @Observable)
    var connectionStatus: ConnectionStatus { VPNService.shared.status }
    var sessionStartedAt: Date? { VPNService.shared.sessionStartedAt }
    var currentServer: VPNServerConfig? { VPNService.shared.currentServer }

    var connectionState: VPNConnectionState {
        switch VPNService.shared.status {
        case .connected:  return .connected
        case .connecting: return .connecting
        default:          return .disconnected
        }
    }

    /// Текст ошибки туннеля. Раньше `.failed` молча схлопывался в
    /// `.disconnected`, и пользователь видел «Click to Connect» вместо причины.
    var connectionError: String? {
        if case .failed(let message) = VPNService.shared.status { return message }
        return nil
    }

    func toggleVPN() {
        if VPNService.shared.status.isActive || VPNService.shared.status == .connecting {
            VPNService.shared.disconnect()
            return
        }
        guard VPNService.shared.currentServer != nil else {
            alert = AppAlertModel(
                title: "No server selected",
                message: "Choose a server from the list before connecting.",
                kind: .info
            )
            return
        }
        Task { await VPNService.shared.connect() }
    }

    func elapsedSeconds(now: Date = .now) -> Int {
        guard let start = VPNService.shared.sessionStartedAt else { return 0 }
        return max(0, Int(now.timeIntervalSince(start)))
    }

    func elapsedText(now: Date = .now) -> String {
        let s = elapsedSeconds(now: now)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    // MARK: - Live throughput (реальные счётчики utun, не моки)
    var downloadText: String { Self.format(mbps: SpeedTracker.shared.downloadMbps) }
    var uploadText:   String { Self.format(mbps: SpeedTracker.shared.uploadMbps) }

    private static func format(mbps: Double) -> String {
        if mbps >= 1 { return String(format: "%.1f Mbps", mbps) }
        return String(format: "%.0f KB/s", mbps * 125)
    }

    // MARK: - Clipboard
    /// Вставка share-link'а (или целого списка / base64-подписки) из буфера обмена.
    /// Основной сценарий добавления конфига: скопировал у провайдера — вставил.
    func addFromClipboard() {
        guard let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            alert = .clipboardEmpty
            return
        }
        importConfiguration(text: raw, emptyAlert: .clipboardUnrecognized)
    }

    /// Общий путь для буфера / файла / QR: распарсить, проверить лимит, сохранить.
    private func importConfiguration(text: String, emptyAlert: AppAlertModel) {
        let parsed = VPNConfigParser.parseSubscription(text)
        guard !parsed.isEmpty else {
            alert = emptyAlert
            return
        }
        guard canAdd(count: parsed.count) else {
            alert = .needsUpgrade
            return
        }
        guard let folder = foldersStore.importFile(contents: text) else {
            alert = emptyAlert
            return
        }
        alert = .importSuccess(count: folder.servers.count)
        // Первый добавленный конфиг сразу делаем активным, иначе кнопка
        // подключения ругается «No server selected».
        if VPNService.shared.currentServer == nil, let first = folder.servers.first {
            VPNService.shared.selectServer(first)
        }
    }

    // MARK: - File importer
    func handleImportedFile(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            do {
                let contents: String
                if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
                    contents = utf8
                } else {
                    contents = try String(contentsOf: url, encoding: .isoLatin1)
                }
                importConfiguration(text: contents, emptyAlert: .importEmpty)
            } catch {
                alert = .importFailed(error.localizedDescription)
            }
        case .failure(let error):
            alert = .importFailed(error.localizedDescription)
        }
    }

    // MARK: - QR scan
    func handleScannedPayload(_ payload: String?) {
        guard let payload, !payload.isEmpty else {
            alert = .scanEmpty
            return
        }
        importConfiguration(text: payload, emptyAlert: .scanEmpty)
    }

    // MARK: - Manual entry
    var canSaveManual: Bool {
        guard let portInt = Int(manualForm.port.trimmed),
              portInt > 0 else { return false }
        guard !manualForm.name.trimmed.isEmpty,
              !manualForm.host.trimmed.isEmpty else { return false }

        switch manualForm.proto {
        case .vless:
            guard !manualForm.uuid.trimmed.isEmpty else { return false }
            if manualForm.security == .reality {
                return !manualForm.publicKey.trimmed.isEmpty
                    && !manualForm.shortID.trimmed.isEmpty
                    && !manualForm.sni.trimmed.isEmpty
            }
            if manualForm.security == .tls {
                return !manualForm.sni.trimmed.isEmpty
            }
            return true
        case .vmess:
            guard !manualForm.uuid.trimmed.isEmpty else { return false }
            if manualForm.vmessTLS { return !manualForm.sni.trimmed.isEmpty }
            return true
        case .trojan:
            guard !manualForm.password.trimmed.isEmpty else { return false }
            if manualForm.security == .tls { return !manualForm.sni.trimmed.isEmpty }
            return true
        case .shadowsocks:
            return !manualForm.password.trimmed.isEmpty
        }
    }

    @discardableResult
    func saveManual() -> Bool {
        manualLastError = nil
        guard canSaveManual, let portInt = Int(manualForm.port.trimmed) else {
            manualLastError = String(localized: "Fill in all required fields.")
            return false
        }

        guard canAdd(count: 1) else {
            alert = .needsUpgrade
            return false
        }

        let raw = buildShareLink(port: portInt)

        guard let folder = foldersStore.addLink(raw, folderName: manualForm.name.trimmed) else {
            manualLastError = String(localized: "Invalid configuration — please check the fields.")
            return false
        }
        if VPNService.shared.currentServer == nil, let first = folder.servers.first {
            VPNService.shared.selectServer(first)
        }
        resetManualForm()
        return true
    }

    func resetManualForm() {
        manualForm = ManualEdFormState()
        manualLastError = nil
    }

    /// Preview of the share-link the current form would produce (used by the FinalMask section).
    var previewShareLink: String {
        guard let port = Int(manualForm.port.trimmed), port > 0 else { return "" }
        return buildShareLink(port: port)
    }

    // MARK: - Alerts
    func dismissAlert() {
        alert = nil
    }

    // MARK: - Custom folders actions
    func selectServer(_ server: VPNServerConfig) {
        guard !VPNService.shared.status.isActive else {
            alert = .disconnectFirst
            return
        }
        // Persists rawURL to UD internally, so selection survives app restarts.
        VPNService.shared.selectServer(server)
    }

    func deleteFolder(_ folder: CustomServerFolder) {
        let deletedSelected = VPNService.shared.currentServer.map { current in
            folder.servers.contains { $0.rawURL == current.rawURL }
        } ?? false

        foldersStore.remove(folderId: folder.id)

        guard deletedSelected else { return }
        // Раньше очищался только UserDefaults, а currentServer продолжал указывать
        // на удалённый конфиг — и кнопка питания к нему подключалась.
        VPNService.shared.disconnect()
        VPNService.shared.clearSelection()
        // Если остались другие конфиги — выбираем первый доступный.
        if let next = VPNService.shared.availableServers.first {
            VPNService.shared.selectServer(next)
        }
    }

    func beginRenameFolder(_ folder: CustomServerFolder) {
        renameFolderId = folder.id
        renameFolderText = folder.name
        showRenameFolderAlert = true
    }

    func confirmRenameFolder() {
        defer {
            renameFolderId = nil
            renameFolderText = ""
        }
        guard let id = renameFolderId else { return }
        let name = renameFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        foldersStore.rename(folderId: id, to: name)
    }

    func pingFolder(_ folder: CustomServerFolder) {
        guard !folder.servers.isEmpty else { return }
        Task {
            await PingCache.shared.measureAll(folder.servers, force: true)
            let lines = folder.servers.map { server -> String in
                let ms = PingCache.shared.ping(for: server.rawURL)
                return ms.map { "\(server.remark) — \($0) ms" } ?? "\(server.remark) — timeout"
            }
            alert = AppAlertModel(
                title: "Ping",
                message: LocalizedStringResource(stringLiteral: lines.joined(separator: "\n")),
                kind: .info
            )
        }
    }

    // MARK: - Link builder
    private func buildShareLink(port: Int) -> String {
        let s = manualForm
        switch s.proto {
        case .vless:
            return ShareLinkBuilder.buildVLESS(
                name:        s.name.trimmed,
                host:        s.host.trimmed,
                port:        port,
                uuid:        s.uuid.trimmed,
                security:    s.security.rawValue,
                network:     s.network.rawValue,
                sni:         s.security == .none ? nil : s.sni.trimmed,
                publicKey:   s.security == .reality ? s.publicKey.trimmed : nil,
                shortID:     s.security == .reality ? s.shortID.trimmed  : nil,
                fingerprint: s.security == .none ? nil : s.fingerprint.rawValue,
                flow:        s.security == .reality ? s.flow.trimmed : nil,
                path:        s.network == .ws ? s.path.trimmed : nil,
                wsHost:      s.network == .ws ? s.wsHost.trimmed : nil,
                serviceName: s.network == .grpc ? s.path.trimmed : nil,
                headerType:  s.network == .tcp && s.headerType != .none ? s.headerType.rawValue : nil
            )
        case .vmess:
            return ShareLinkBuilder.buildVMess(
                name:       s.name.trimmed,
                host:       s.host.trimmed,
                port:       port,
                uuid:       s.uuid.trimmed,
                alterId:    Int(s.alterId.trimmed) ?? 0,
                security:   s.vmessSecurity.rawValue,
                network:    s.network.rawValue,
                tls:        s.vmessTLS,
                sni:        s.vmessTLS ? s.sni.trimmed : nil,
                path:       s.network == .ws ? s.path.trimmed : nil,
                wsHost:     s.network == .ws ? s.wsHost.trimmed : nil,
                headerType: s.headerType == .none ? nil : s.headerType.rawValue
            )
        case .trojan:
            return ShareLinkBuilder.buildTrojan(
                name:     s.name.trimmed,
                host:     s.host.trimmed,
                port:     port,
                password: s.password.trimmed,
                security: s.security.rawValue,
                network:  s.network.rawValue,
                sni:      s.security == .tls ? s.sni.trimmed : nil,
                path:     s.network == .ws ? s.path.trimmed : nil,
                wsHost:   s.network == .ws ? s.wsHost.trimmed : nil
            )
        case .shadowsocks:
            return ShareLinkBuilder.buildShadowsocks(
                name:     s.name.trimmed,
                host:     s.host.trimmed,
                port:     port,
                method:   s.ssMethod.rawValue,
                password: s.password.trimmed
            )
        }
    }
}

// MARK: - Alert presets
extension AppAlertModel {
    static var importEmpty: AppAlertModel {
        AppAlertModel(
            title: "No configuration found",
            message: "Proxy configuration not found. Please import the configuration from your provider.",
            kind: .info
        )
    }

    static func importSuccess(count: Int) -> AppAlertModel {
        AppAlertModel(
            title: "Configuration added",
            message: count == 1
                ? "1 server has been added to your list."
                : "\(count) servers have been added to your list.",
            kind: .info
        )
    }

    static func importFailed(_ reason: String) -> AppAlertModel {
        AppAlertModel(
            title: "Import failed",
            message: "\(reason)",
            kind: .info
        )
    }

    static var scanEmpty: AppAlertModel {
        AppAlertModel(
            title: "QR code not recognized",
            message: "Try again with a clearer angle or better lighting.",
            kind: .info
        )
    }

    static var addServerPrompt: AppAlertModel {
        AppAlertModel(
            title: "You're Almost Ready",
            message: "Add your first proxy server to start browsing securely.",
            kind: .addServer
        )
    }

    static var needsUpgrade: AppAlertModel {
        AppAlertModel(
            title: "One config on the free plan",
            message: "Delete your current server or upgrade to add more.",
            kind: .upgrade
        )
    }

    static var clipboardEmpty: AppAlertModel {
        AppAlertModel(
            title: "Clipboard is empty",
            message: "Copy a vless://, vmess://, trojan:// or ss:// link first, then tap Clipboard.",
            kind: .info
        )
    }

    static var clipboardUnrecognized: AppAlertModel {
        AppAlertModel(
            title: "Nothing to import",
            message: "The copied text isn't a supported configuration. Expected a vless://, vmess://, trojan:// or ss:// link.",
            kind: .info
        )
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
