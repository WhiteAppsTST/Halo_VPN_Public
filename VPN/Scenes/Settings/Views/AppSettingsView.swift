import SwiftUI

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(SubscriptionService.self) private var subscription

    @State private var prefs = AppPreferencesStore.shared
    @State private var supportAlert: AppAlertModel?
    @State private var showDiagnostics = false

    var body: some View {
        contentView
            .background(
                Image("subScreenBG")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            )
            .overlay(alignment: .center) {
                if let alert = supportAlert {
                    AppAlertView(
                        model: alert,
                        onClose: { supportAlert = nil }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: supportAlert)
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
                    .preferredColorScheme(.dark)
            }
    }

    // MARK: - Content
    private var contentView: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    premiumCard

                    section(title: "CONNECTION") {
                        protocolRow
                        divider
                        killSwitchRow
                        divider
                        autoConnectRow
                    }

                    section(title: "ACCOUNT") {
                        supportRow
                        divider
                        privacyRow
                        divider
                        termsRow
                        divider
                        diagnosticsRow
                    }

                    restoreCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Nav bar
    // Settings — это один из табов внутри MainTabView, назад некуда возвращаться.
    // Слева уже сидит menuButton из MainTabView, свой back тут не нужен.
    private var navBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Text("Settings")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(height: 50)
    }

    // MARK: - Premium card
    private var premiumCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("GET PREMIUM")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Unlimited configs &\nfull privacy tools")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                subscription.showPaywall(.settings)
            } label: {
                Text("Upgrade")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .glassedEffect(
                        in: Capsule(),
                        isClear: false,
                        tint: .white.opacity(0.1),
                        interactive: false
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 97)
        .background(
            Image("settings_premium_btn_bg")
                .resizable()
        )
        .padding(.top, 20)
        .padding(.bottom, 5)
    }

    // MARK: - Rows
    private var protocolRow: some View {
        row(title: "Protocol") {
            Text(currentProtocolLabel)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var currentProtocolLabel: String {
        VPNService.shared.currentServer?.kind.rawValue.uppercased() ?? "Xray"
    }

    private var killSwitchRow: some View {
        @Bindable var prefs = prefs
        return row(title: "Kill Switch") {
            Toggle("", isOn: $prefs.killSwitchEnabled)
                .labelsHidden()
                .tint(Color(hex: "34D27A"))
                // Пишем в уже сохранённый профиль сразу, а не «при следующем connect».
                .onChange(of: prefs.killSwitchEnabled) { _, _ in
                    Task { await VPNService.shared.applyKillSwitchPreference() }
                }
        }
    }

    private var autoConnectRow: some View {
        @Bindable var prefs = prefs
        return row(title: "Auto-Connect") {
            Toggle("", isOn: $prefs.autoConnectEnabled)
                .labelsHidden()
                .tint(Color(hex: "34D27A"))
                .onChange(of: prefs.autoConnectEnabled) { _, _ in
                    Task { await VPNService.shared.applyAutoConnectPreference() }
                }
        }
    }

    private var supportRow: some View {
        row(title: "Support") {
            chevron
        } onTap: {
            MailSupport.open { alert in
                supportAlert = alert
            }
        }
    }

    private var privacyRow: some View {
        row(title: "Privacy Policy") {
            chevron
        } onTap: {
            openExternal(AppConstants.Foundation.privacyURLString)
        }
    }

    private var termsRow: some View {
        row(title: "Terms of Service") {
            chevron
        } onTap: {
            openExternal(AppConstants.Foundation.termsURLString)
        }
    }

    // MARK: - Restore card
    /// Экран диагностики для удалённого тестирования: тестер копирует текст
    /// и присылает — по нему видно точную причину сбоя без второй сборки.
    private var diagnosticsRow: some View {
        row(title: "Diagnostics") {
            chevron
        } onTap: {
            showDiagnostics = true
        }
    }

    private var restoreCard: some View {
        Button {
            Task { await subscription.restore() }
        } label: {
            Text("Restore purchase")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassedEffect(
            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
            isClear: false,
            tint: .white.opacity(0.04),
            interactive: false
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Helpers
    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0, content: content)
                .glassedEffect(
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                    isClear: false,
                    tint: .white.opacity(0.04),
                    interactive: false
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                )
        }
    }

    /// Общий row-хелпер. Если `onTap == nil` — НЕ оборачиваем в Button
    /// (иначе toggle'ы блокируются, а лейблы бледнеют из-за .disabled).
    @ViewBuilder
    private func row<Trailing: View>(
        title: LocalizedStringResource,
        @ViewBuilder trailing: () -> Trailing,
        onTap: (() -> Void)? = nil
    ) -> some View {
        let content = HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())

        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.white.opacity(0.4))
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    // MARK: - URL open
    private func openExternal(_ string: String) {
        guard !string.isEmpty, let url = URL(string: string) else { return }
        openURL(url)
    }
}

#Preview {
    AppSettingsView()
}
