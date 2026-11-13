import SwiftUI

struct PaywallTrustView: View {
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
                    titleBlock
                        .padding(.horizontal, 20)
                        .padding(.top, 30)

                    subtitleText
                        .padding(.horizontal, 40)
                        .padding(.top, 18)

                    badgesRow
                        .padding(.top, 22)

                    planCards
                        .padding(.horizontal, 20)
                        .padding(.top, 40)

                    seePlansLink
                        .padding(.top, 32)
                        .padding(.bottom, 24)
                }
            }

            bottomPinned
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var titleBlock: some View {
        let text = Text("Trusted")
            .foregroundStyle(Color(hex: "4F8CFF"))
        + Text(" Protection")
            .foregroundStyle(.white)
        return text
            .font(.system(size: 30, weight: .bold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    private var subtitleText: some View {
        Text("JOIN THOUSANDS WHO BROWSE WITHOUT LIMITS.")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.white.opacity(0.72))
            .multilineTextAlignment(.center)
            .tracking(0.4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    private var badgesRow: some View {
        HStack(spacing: 16) {
            laurelBadge {
                VStack(spacing: 2) {
                    Text("Browse without")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("Limits")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }

            laurelBadge {
                VStack(spacing: 4) {
                    Text("User choice")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "F5A623"))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func laurelBadge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.white)

            content()
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)

            Image(systemName: "laurel.trailing")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.white)
        }
        .frame(height: 69)
        .frame(maxWidth: .infinity)
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

    private var seePlansLink: some View {
        Button {
            selectYearlyIfPossible()
        } label: {
            Text("See weekly and monthly plans")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: "4F8CFF"))
                .underline()
        }
        .buttonStyle(.plain)
    }

    private func selectYearlyIfPossible() {
        guard let yearly = service.products.first(where: { $0.periodly.lowercased() == "year" }) else { return }
        if service.selection?.id != yearly.id {
            service.selection = yearly
        }
    }

    private var bottomPinned: some View {
        VStack(spacing: 0) {
            trialCaption
                .padding(.horizontal, 32)

            ctaButton
                .padding(.top, 12)
                .padding(.horizontal, 20)

            footerLinks
                .padding(.top, 20)
                .padding(.bottom, 12)
        }
    }

    private var trialCaption: some View {
        Text(trialCaptionText)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.white.opacity(0.4))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var trialCaptionText: String {
        guard let sel = service.selection else { return "" }
        if sel.includesTrial, service.canUseTrial, let days = sel.trialDays {
            return "\(days) Days Free Trial then \(sel.pricePerPeriod) / \(sel.periodly). Renews annually unless\ncanceled in Apple ID settings."
        }
        return "\(sel.pricePerPeriod) / \(sel.periodly). Renews automatically unless\ncanceled in Apple ID settings."
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
    PaywallTrustView()
        .environment(SubscriptionService.shared)
}
