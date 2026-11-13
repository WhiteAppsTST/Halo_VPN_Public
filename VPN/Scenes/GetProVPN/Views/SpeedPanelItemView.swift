import SwiftUI

struct SpeedPanelItemView: View {
    enum Direction {
        case download, upload

        var title: LocalizedStringResource {
            switch self {
            case .download: return "Download"
            case .upload:   return "Upload"
            }
        }

        var iconName: String {
            switch self {
            case .download: return "arrow.down"
            case .upload:   return "arrow.up"
            }
        }
    }

    let direction: Direction
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iconBadge
                .padding(.bottom, 6)

            Text(direction.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.bottom, 7)

            valueLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassedEffect(
            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
            isClear: false,
            tint: .white.opacity(0.06),
            interactive: false
        )
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(hex: "5B9BFF"))
            .frame(width: 25, height: 25)
            .overlay {
                Image(systemName: direction.iconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
            }
    }

    @ViewBuilder
    private var valueLabel: some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", value))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                Text("KB/s")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
            }
        } else {
            Text("--")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
