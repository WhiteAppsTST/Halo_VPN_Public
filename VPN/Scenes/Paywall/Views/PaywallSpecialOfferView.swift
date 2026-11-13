import SwiftUI

struct PaywallSpecialOfferView: View {
    @Environment(SubscriptionService.self) private var service
    @Environment(\.openURL) private var openURL
    /// Дедлайн офера фиксируется один раз и живёт в UserDefaults. Раньше он
    /// пересоздавался на каждое открытие экрана — «осталось 15 минут» показывалось
    /// вечно, что и выглядит, и звучит как обман.
    @State private var deadline: Date = SpecialOfferDeadline.current()

    var body: some View {
        contentView
            .background(
                Image(.homeBG)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            )
            .onAppear { selectYearlyIfPossible() }
            .onChange(of: service.products) { _, _ in selectYearlyIfPossible() }
    }

    private func selectYearlyIfPossible() {
        guard let yearly = service.products.first(where: { $0.periodly.lowercased() == "year" }) else { return }
        if service.selection?.id != yearly.id {
            service.selection = yearly
        }
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            navBar
                .padding(.horizontal, 20)
                .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ticketBlock
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                    unlimitedTitle
                        .padding(.top, 24)

                    lowestPriceTitle
                        .padding(.top, 2)

                    countdownBlock
                        .padding(.top, 30)

                    featuresList
                        .padding(.horizontal, 20)
                        .padding(.top, 44)
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

    private var ticketBlock: some View {
        Image("premium_label_frame")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                VStack(spacing: 0) {
                    Text("GET YOUR")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
                        .padding(.top, 22)

                    Spacer(minLength: 0)

                    Text("76% OFF")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.white)
                        .tracking(-1)
                        .shadow(color: .black.opacity(0.07), radius: 5, y: 2)

                    Spacer(minLength: 0)

                    Text("TO BROWSE WITHOUT BORDERS")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
                        .padding(.bottom, 22)
                }
            }
    }

    private var unlimitedTitle: some View {
        Text("Full tunnel access at the")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
    }

    private var lowestPriceTitle: some View {
        let text = Text("Lowest ")
            .foregroundStyle(.white)
        + Text("Price")
            .foregroundStyle(Color(hex: "4F8CFF"))
        return text
            .font(.system(size: 30, weight: .bold))
            .multilineTextAlignment(.center)
    }

    private var countdownBlock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, deadline.timeIntervalSince(context.date))
            let hrs = Int(remaining) / 3600
            let mins = (Int(remaining) % 3600) / 60
            let secs = Int(remaining) % 60

            if remaining > 0 {
                HStack(spacing: 8) {
                    timeUnit(String(format: "%02d", hrs), label: "hrs")
                    colon
                    timeUnit(String(format: "%02d", mins), label: "min")
                    colon
                    timeUnit(String(format: "%02d", secs), label: "sec")
                }
            } else {
                Text("Limited-time offer")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private func timeUnit(_ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 55, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var colon: some View {
        Text(":")
            .font(.system(size: 36, weight: .heavy))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.top, 4)
    }

    private var featuresList: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "globe", text: "Kill Switch + DoH DNS included")
                featureRow(icon: "shield", text: "No logs, no throttling, no ads")
                featureRow(icon: "bolt", text: "Unlimited configs, every protocol")
            }
            Spacer(minLength: 0)
        }
    }

    private func featureRow(icon: String, text: LocalizedStringResource) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Color(hex: "5B9BFF"))
                .frame(width: 19, height: 19)

            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.82))
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
    PaywallSpecialOfferView()
        .environment(SubscriptionService.shared)
}

/// Дедлайн спецпредложения. Ставится один раз при первом показе пейвола
/// и переживает перезапуск приложения.
enum SpecialOfferDeadline {
    private static let key = "paywall.specialOffer.deadline"
    private static let window: TimeInterval = 15 * 60

    static func current() -> Date {
        let defaults = UserDefaults.standard
        let stored = defaults.double(forKey: key)
        if stored > 0 {
            return Date(timeIntervalSince1970: stored)
        }
        let deadline = Date().addingTimeInterval(window)
        defaults.set(deadline.timeIntervalSince1970, forKey: key)
        return deadline
    }
}
