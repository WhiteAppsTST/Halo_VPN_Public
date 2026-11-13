import SwiftUI

struct PrivacyCenterView: View {
    @Environment(SubscriptionService.self) private var subscription
    @State private var prefs = AppPreferencesStore.shared
    @State private var vpn = VPNService.shared

    // Local UI state
    @State private var wifi: WiFiSnapshot?
    @State private var wifiChecked: Bool = false
    @State private var isDNSApplying: Bool = false
    @State private var dnsError: String?

    var body: some View {
        content
            .background(
                Image("subScreenBG")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            )
            .task { await rescanWiFi() }
    }

    // MARK: - Content
    private var content: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    scoreCard

                    section(title: "KILL SWITCH") {
                        killSwitchRow
                    }

                    section(title: "DNS PROTECTION") {
                        ForEach(DNSProvider.allCases) { p in
                            dnsRow(provider: p)
                            if p != DNSProvider.allCases.last { divider }
                        }
                        if let dnsError {
                            errorLine(dnsError)
                        }
                    }

                    section(title: "WI-FI SECURITY") {
                        wifiCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Nav bar
    private var navBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Text("Privacy Center")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(height: 50)
    }

    // MARK: - Privacy Score
    private var score: Int {
        var s = 0
        if vpn.status.isActive           { s += 30 }
        if subscription.isActiveSubscription { s += 20 }
        if prefs.killSwitchEnabled       { s += 20 }
        if prefs.dnsProvider != .off     { s += 20 }
        if wifiChecked, wifi?.isSecure == true { s += 10 }
        return s
    }

    private var scoreColor: Color {
        switch score {
        case 80...: return Color(hex: "34D27A")
        case 50..<80: return Color(hex: "F0C020")
        default: return Color(hex: "FF7070")
        }
    }

    private var scoreCard: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                    .frame(width: 96, height: 96)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: score)
                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text("/100")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                scoreLine(title: "Connected",        pass: vpn.status.isActive, weight: 30)
                scoreLine(title: "Active subscription",  pass: subscription.isActiveSubscription, weight: 20)
                scoreLine(title: "Kill Switch on",       pass: prefs.killSwitchEnabled, weight: 20)
                scoreLine(title: "Custom DNS",           pass: prefs.dnsProvider != .off, weight: 20)
                scoreLine(title: "Secure Wi-Fi",         pass: wifiChecked && wifi?.isSecure == true, weight: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
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

    private func scoreLine(title: String, pass: Bool, weight: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: pass ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(pass ? Color(hex: "34D27A") : Color.white.opacity(0.3))
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(pass ? 0.9 : 0.5))
            Spacer()
            Text("+\(weight)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(pass ? 0.6 : 0.25))
        }
    }

    // MARK: - Kill Switch
    private var killSwitchRow: some View {
        // @Bindable обязателен: при ручном Binding { get:… } SwiftUI не видит
        // чтение @Observable-свойства и не перерисовывает Toggle — переключатель
        // выглядел «мёртвым».
        @Bindable var prefs = prefs
        return row(title: "Block traffic if connection drops") {
            Toggle("", isOn: $prefs.killSwitchEnabled)
                .labelsHidden()
                .tint(Color(hex: "34D27A"))
                .onChange(of: prefs.killSwitchEnabled) { _, _ in
                    Task { await VPNService.shared.applyKillSwitchPreference() }
                }
        }
    }

    // MARK: - Premium gate

    private var isPremium: Bool { subscription.isActiveSubscription }

    private func requirePremium() {
        subscription.showPaywall(.settings)
    }

    // MARK: - DNS
    @ViewBuilder
    private func dnsRow(provider: DNSProvider) -> some View {
        let selected = prefs.dnsProvider == provider
        let locked   = !isPremium

        Button {
            if locked { requirePremium(); return }
            Task { await applyDNS(provider) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Color(hex: "34D27A") : Color.white.opacity(0.35))

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    Text(provider.subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if isDNSApplying, selected {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if locked {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "FBBF24"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .opacity(locked ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDNSApplying)
    }

    private func errorLine(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "FF7070"))
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color(hex: "FF7070"))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func applyDNS(_ provider: DNSProvider) async {
        guard !isDNSApplying else { return }
        isDNSApplying = true
        dnsError = nil
        defer { isDNSApplying = false }
        do {
            try await PrivacyCenterHelpers.applyDNS(provider: provider)
            prefs.dnsProvider = provider
            // Туннель подставляет DNS из App Group в свои NEDNSSettings, поэтому
            // активную сессию надо переподнять — иначе выбор не вступит в силу.
            await VPNService.shared.reapplyTunnelSettingsIfConnected()
        } catch {
            dnsError = error.localizedDescription
        }
    }

    // MARK: - Wi-Fi
    private var wifiCard: some View {
        VStack(spacing: 0) {
            if let w = wifi {
                wifiRow(icon: "wifi", title: "SSID", value: w.ssid)
                divider
                wifiRow(icon: "network", title: "BSSID", value: w.bssid.isEmpty ? "—" : w.bssid)
                divider
                wifiRow(
                    icon: w.isSecure ? "lock.fill" : "lock.open.fill",
                    title: "Security",
                    value: w.isSecure ? "Encrypted" : "Open",
                    valueColor: w.isSecure ? Color(hex: "34D27A") : Color(hex: "FF7070")
                )
                divider
                wifiRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Signal",
                    value: "\(Int(round(w.signalStrength * 100)))%"
                )
            } else if wifiChecked {
                emptyWiFi
            } else {
                loadingWiFi
            }

            divider

            Button {
                if !isPremium { requirePremium(); return }
                Task { await rescanWiFi() }
            } label: {
                HStack(spacing: 6) {
                    if !isPremium {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "FBBF24"))
                    }
                    Text("Rescan")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isPremium ? Color(hex: "5B9BFF") : Color(hex: "5B9BFF").opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func wifiRow(icon: String, title: String, value: String,
                         valueColor: Color = .white) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var loadingWiFi: some View {
        HStack {
            ProgressView().controlSize(.small).tint(.white)
            Text("Checking Wi-Fi…")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var emptyWiFi: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.white.opacity(0.4))
            Text(LocationAuthorizer.shared.isDenied
                 ? "Allow location access in Settings to see Wi-Fi details."
                 : "Not connected to Wi-Fi.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func rescanWiFi() async {
        wifiChecked = false
        wifi = await PrivacyCenterHelpers.fetchCurrentWiFi()
        wifiChecked = true
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

    @ViewBuilder
    private func row<Trailing: View>(
        title: LocalizedStringResource,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }
}

#Preview {
    PrivacyCenterView()
        .environment(SubscriptionService.shared)
}
