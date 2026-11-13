import SwiftUI

struct PaywallHaloView: View {
    @Environment(SubscriptionService.self) private var service
    @Environment(\.openURL) private var openURL

    var body: some View {
        contentView
            .background(
                Image(.homeBG)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            )
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            navBar
                .padding(.horizontal, 20)
                .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroBlock
                        .padding(.top, 40)

                    subtitleText
                        .padding(.top, 24)

                    featuresRow
                        .padding(.horizontal, 20)
                        .padding(.top, 44)

                    planCards
                        .padding(.horizontal, 20)
                        .padding(.top, 40)
                        .padding(.bottom, 24)
                }
            }

            bottomPinned
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomPinned: some View {
        VStack(spacing: 0) {
            trialCaption

            ctaButton
                .padding(.top, 8)
                .padding(.horizontal, 20)

            footerLinks
                .padding(.top, 20)
                .padding(.bottom, 12)
        }
    }

    private var navBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await service.restore() }
            } label: {
                Text("Restore")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

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
        }
        .frame(height: 32)
    }

    private var heroBlock: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Halo HUB")
                .font(.system(size: 33, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.81)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            proBadge
        }
    }

    private var proBadge: some View {
        Text("PRO")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color(hex: "5B9BFF"))
            .frame(width: 69, height: 31)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(hex: "5B9BFF"), lineWidth: 2.3)
            )
    }

    private var subtitleText: some View {
        Text("CREATE AND RUN YOUR PERSONALIZED TUNNEL\nCONFIGURATIONS WITH EASE.")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.white.opacity(0.72))
            .multilineTextAlignment(.center)
            .tracking(0.5)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
    }

    private var featuresRow: some View {
        HStack(spacing: 0) {
            featureItem(icon: "shield", title: "Secure", subtitle: "Encrypted DoH DNS")
            featureDivider
            featureItem(icon: "globe", title: "Unlimited Custom", subtitle: "Create your own tunnel configs")
            featureDivider
            featureItem(icon: "bolt", title: "Fast", subtitle: "Live speed & latency tests")
        }
    }

    private func featureItem(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color(hex: "5B9BFF"))
                .frame(width: 48, height: 48)

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.32))
                    .multilineTextAlignment(.center)
                    .lineSpacing(1.4)
                    .frame(width: 96)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var featureDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.05))
            .frame(width: 1, height: 82)
    }

    private var planCards: some View {
        VStack(spacing: 20) {
            ForEach(service.products) { product in
                PaywallProductCard(
                    product: product,
                    isSelected: service.selection?.id == product.id,
                    canUseTrial: service.canUseTrial
                ) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        service.selection = product
                    }
                    AppsFlyerService.shared.logProductSelected(
                        productId: product.id,
                        placementId: service.activePaywallId?.rawValue
                    )
                }
            }
        }
    }

    private var trialCaption: some View {
        Text(footerCaption)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.white.opacity(0.4))
            .multilineTextAlignment(.center)
            .frame(minHeight: 14)
    }

    private var footerCaption: String {
        guard let sel = service.selection else { return "" }
        if sel.includesTrial && service.canUseTrial {
            return String(localized: "\(trialDaysLabel) then \(sel.pricePerPeriod) / \(sel.periodly.capitalized)")
        }
        return "\(sel.pricePerPeriod) / \(sel.periodly.capitalized)"
    }

    private var trialDaysLabel: String {
        guard let sel = service.selection else { return "" }
        switch sel.periodly.lowercased() {
        case "week": return String(localized: "3 Days Free Trial")
        default:     return String(localized: "7 Days Free Trial")
        }
    }

    private var ctaButton: some View {
        Button {
            Task { await service.completePurchase() }
        } label: {
            HStack(spacing: 8) {
                if service.purchaseState == .purchasing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(service.purchaseBtnTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(ctaBackground)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .opacity(isCtaEnabled ? 1.0 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!isCtaEnabled)
        .frame(maxWidth: 245)
    }

    private var isCtaEnabled: Bool {
        service.selection != nil && service.purchaseState != .purchasing
    }

    private var ctaBackground: some View {
        RadialGradient(
            stops: [
                .init(color: Color(hex: "8FC0FF"), location: 0.0),
                .init(color: Color(hex: "5B9BFF"), location: 0.38),
                .init(color: Color(hex: "2F63D8"), location: 1.0)
            ],
            center: UnitPoint(x: 0.38, y: 0.26),
            startRadius: 0,
            endRadius: 240
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.6), lineWidth: 2)
                .blur(radius: 1)
                .mask(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white, .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color(hex: "143282").opacity(0.5)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
                .blendMode(.multiply)
        )
        .shadow(color: Color(hex: "468CFF").opacity(0.2), radius: 15)
    }

    private var footerLinks: some View {
        HStack(spacing: 20) {
            footerLink("Privacy Policy") {
                openExternal(AppConstants.Foundation.privacyURLString)
            }
            footerLink("Restore") {
                Task { await service.restore() }
            }
            footerLink("Terms of use") {
                openExternal(AppConstants.Foundation.termsURLString)
            }
        }
        .opacity(0.5)
    }

    private func footerLink(_ title: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func openExternal(_ string: String) {
        guard !string.isEmpty, let url = URL(string: string) else { return }
        openURL(url)
    }
}

#Preview {
    PaywallHaloView()
        .environment(SubscriptionService.shared)
}
