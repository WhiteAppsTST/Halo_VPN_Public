import SwiftUI

struct CustomServerRowView: View {
    let server: VPNServerConfig
    let isSelected: Bool
    let onTap: () -> Void

    @State private var pingCache = PingCache.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                if isSelected {
                    Rectangle()
                        .fill(Color(hex: "34D27A"))
                        .frame(width: 2, height: 36)
                }

                HStack(spacing: 12) {
                    flagCircle

                    VStack(alignment: .leading, spacing: 2) {
                        Text(countryTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(server.host)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color(hex: "8F8F96"))
                            .lineLimit(1)
                    }

                    Spacer()

                    pingIndicator
                }
                .padding(.leading, 14)
                .padding(.trailing, 36)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassedEffect(
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                isClear: false,
                tint: .white.opacity(isSelected ? 0.1 : 0.05),
                interactive: false
            )
        }
        .buttonStyle(.plain)
    }

    private var countryTitle: String {
        let iso = server.countryCode ?? ""
        return iso.isEmpty ? server.remark : "\(iso) — \(server.remark)"
    }

    private var flagCircle: some View {
        Circle()
            .fill(Color(hex: "1E2A44"))
            .frame(width: 22, height: 22)
            .overlay {
                Text(server.countryCode ?? "?")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    // MARK: - Ping indicator

    private var measured: Bool { pingCache.wasMeasured(server.rawURL) }
    private var pingMs: Int? { pingCache.ping(for: server.rawURL) }

    /// 0…4 активных сегмента (кол-во «зелёных» палочек).
    private var activeBars: Int {
        guard let ms = pingMs else { return 0 }
        switch ms {
        case ..<100:  return 4
        case ..<200:  return 3
        case ..<400:  return 2
        case ..<800:  return 1
        default:      return 1
        }
    }

    private var barColor: Color {
        guard let ms = pingMs else { return Color(hex: "5A6A86") }
        switch ms {
        case ..<200:  return Color(hex: "34D27A")
        case ..<400:  return Color(hex: "F0C020")
        default:      return Color(hex: "F07070")
        }
    }

    private var pingLabel: String {
        if !measured { return "…" }
        guard let ms = pingMs else { return "—" }
        return "\(ms) ms"
    }

    private var pingIndicator: some View {
        HStack(spacing: 6) {
            Text(pingLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "8F8F96"))

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i < activeBars ? barColor : Color(hex: "2A3145"))
                        .frame(width: 3, height: CGFloat(6 + i * 3))
                }
            }
        }
    }
}
