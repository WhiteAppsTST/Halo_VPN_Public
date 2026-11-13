import SwiftUI

struct PaywallProductCard: View {
    let product: PremiumProduct
    let isSelected: Bool
    let canUseTrial: Bool
    var height: CGFloat = 78
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(product.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)

                        if let badge = product.label, !badge.isEmpty {
                            badgePill(badge)
                        }
                    }

                    Text(subtitleText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(hex: "8A8A8A"))
                }
                .padding(.leading, 20)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(product.pricePerPeriod)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    if let trial = trialText {
                        Text(trial)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color(hex: "5B9BFF"))
                    }
                }
                .padding(.trailing, 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(background)
            .overlay(border)
            .compositingGroup()
            .shadow(color: isSelected ? Color(hex: "4F8CFF").opacity(0.14) : .clear, radius: 26)
        }
        .buttonStyle(.plain)
    }

    private func badgePill(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(hex: "2563EB"))
            )
    }

    private var subtitleText: String {
        switch product.periodly.lowercased() {
        case "year":
            if let perMonth = product.pricePerMonth { return "\(perMonth) / month" }
            return String(localized: "billed yearly")
        case "month": return String(localized: "billed monthly")
        case "week":  return String(localized: "billed weekly")
        default:      return ""
        }
    }

    private var trialText: String? {
        guard product.includesTrial, canUseTrial else { return nil }
        switch product.periodly.lowercased() {
        case "year":  return String(localized: "7-day free trial")
        case "week":  return String(localized: "3-day free trial")
        default:      return String(localized: "free trial")
        }
    }

    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.05))

            if isSelected {
                glows
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var glows: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "2563EB").opacity(0.25))
                .frame(width: 75, height: 75)
                .blur(radius: 25)
                .offset(x: -170, y: 12)

            Circle()
                .fill(Color(hex: "2563EB").opacity(0.25))
                .frame(width: 84, height: 74)
                .blur(radius: 25)
                .offset(x: -95, y: -30)
        }
        .allowsHitTesting(false)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                isSelected
                ? AnyShapeStyle(LinearGradient(
                    colors: [Color(hex: "3D8BFD"), Color(hex: "2159D8")],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                : AnyShapeStyle(Color.white.opacity(0.05)),
                lineWidth: 1
            )
    }
}
