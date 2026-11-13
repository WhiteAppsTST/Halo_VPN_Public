import SwiftUI

struct PaywallView: View {
    @Environment(SubscriptionService.self) private var service

    var body: some View {
        ZStack {
            content
                .opacity(isLoading ? 0 : 1)

            if isLoading {
                loadingState
            } else if service.products.isEmpty {
                unavailableState
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isLoading)
        .onAppear {
            // Единая точка трекинга открытия любого пейвола.
            let id = (service.activePaywallId ?? .main).rawValue
            AppsFlyerService.shared.logPaywallOpened(placementId: id)
        }
    }

    private var isLoading: Bool {
        if case .loading = service.fetchState { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch service.activePaywallId {
        case .main, .none:
            PaywallHaloView()               // Halo HUB
        case .settings:
            PaywallPremiumView()            // Try Unlimited Custom Server Configs for Free
        case .manualServer:
            PaywallTrustView()              // Trusted Protection
        case .pushSpecialOffer:
            PaywallSpecialOfferView()       // 76% OFF + countdown
        }
    }

    /// Раньше во время загрузки продуктов пейвол показывал пустой экран
    /// с неактивной кнопкой и без единого намёка, что что-то грузится.
    private var loadingState: some View {
        ZStack {
            Image(.homeBG)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Loading plans…")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .overlay(alignment: .topTrailing) { closeButton }
    }

    /// Продуктов нет вообще — сеть недоступна или placement не сконфигурирован.
    /// Пользователь должен иметь возможность выйти, а не залипнуть в пустоте.
    private var unavailableState: some View {
        ZStack {
            Image(.homeBG)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color(hex: "5B9BFF"))

                Text("Plans are unavailable")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text("Check your connection and try again.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                Button {
                    service.showPaywall(service.activePaywallId ?? .main)
                } label: {
                    Text("Try again")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color(hex: "2F63D8")))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(.horizontal, 40)
        }
        .overlay(alignment: .topTrailing) { closeButton }
    }

    private var closeButton: some View {
        Button {
            service.isPaywallShown = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.top, 8)
    }
}

#Preview {
    PaywallView()
        .environment(SubscriptionService.shared)
}
