import SwiftUI

struct SelectedServerRowView: View {
    let server: VPNServerConfig?
    let pingMs: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                flagCircle

                VStack(alignment: .leading, spacing: 6) {
                    Text(countryTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(subtitleText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                pingLabel

                signalBars

                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 26)
            .contentShape(Rectangle())
            .glassedEffect(
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                isClear: false,
                tint: .white.opacity(0.06),
                interactive: false
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Flag
    private var flagCircle: some View {
        let flag = flagEmoji(server?.countryCode ?? "")
        return Group {
            if !flag.isEmpty {
                Text(flag)
                    .font(.system(size: 44))
                    .fixedSize()
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(hex: "1E2A44"))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text(server?.countryCode ?? "?")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .fixedSize()
    }

    private func flagEmoji(_ iso: String) -> String {
        guard iso.count == 2 else { return "" }
        let base: UInt32 = 127397
        var scalars = String.UnicodeScalarView()
        for u in iso.uppercased().unicodeScalars {
            if let s = UnicodeScalar(base + u.value) {
                scalars.append(s)
            }
        }
        return String(scalars)
    }

    // MARK: - Labels
    private var countryTitle: String {
        guard let server else { return String(localized: "Select server") }
        if let iso = server.countryCode, !iso.isEmpty {
            return "\(iso) — \(server.remark)"
        }
        return server.remark
    }

    private var subtitleText: String {
        guard let server else { return String(localized: "No server selected") }
        return server.host
    }

    @ViewBuilder
    private var pingLabel: some View {
        if let pingMs {
            Text("\(pingMs)ms")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Signal bars (4 bars, filled per signal strength)
    private var signalBars: some View {
        let level = signalLevel  // 0…4
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Color(hex: "34D27A").opacity(i < level ? 1 : 0.25))
                    .frame(width: 3, height: barHeights[i])
            }
        }
    }

    private var barHeights: [CGFloat] { [5, 8, 11, 14] }

    private var signalLevel: Int {
        guard let ping = pingMs else { return 0 }
        switch ping {
        case ..<80:   return 4
        case ..<150:  return 3
        case ..<250:  return 2
        case ..<500:  return 1
        default:      return 0
        }
    }
}
