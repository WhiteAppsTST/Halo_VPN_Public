import SwiftUI

struct SpeedTestView: View {
    @State private var viewModel = SpeedTestViewModel()

    var body: some View {
        contentView
            .background(
                Image(.homeBG)
                    .resizable()
                    .ignoresSafeArea()
            )
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    stepChips
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    gaugeBlock
                        .padding(.top, 32)

                    actionButton
                        .padding(.horizontal, 100)
                        .padding(.top, 12)

                    if let caption = viewModel.attemptsCaption {
                        Text(caption)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 8)
                    }

                    if let banner = viewModel.errorBanner {
                        alertBanner(banner)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    infoCard
                        .padding(.horizontal, 20)
                        .padding(.top, viewModel.errorBanner == nil ? 24 : 12)
                        .padding(.bottom, 40)
                }
                .animation(.easeInOut(duration: 0.35), value: viewModel.failedStep)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var navBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Text("DNS Leak Test")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(height: 50)
    }

    private var stepChips: some View {
        HStack(spacing: 12) {
            ForEach(SpeedTestViewModel.Step.allCases) { step in
                chipView(step: step)
            }
        }
    }

    private func chipView(step: SpeedTestViewModel.Step) -> some View {
        let state = viewModel.chipState(for: step)
        return HStack(spacing: 6) {
            chipIcon(state: state)
                .frame(width: 14, height: 14)

            Text(step.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(chipTextColor(state: state))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(chipFill(state: state))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(chipStroke(state: state), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.35), value: state)
    }

    @ViewBuilder
    private func chipIcon(state: SpeedTestViewModel.ChipState) -> some View {
        switch state {
        case .active:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(0.7)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "5B9BFF"))
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: "FF7070"))
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
        case .pending, .skipped:
            EmptyView()
        }
    }

    private func chipFill(state: SpeedTestViewModel.ChipState) -> Color {
        switch state {
        case .active: return Color(hex: "5B9BFF")
        case .completed, .pending: return .white.opacity(0.03)
        case .failed: return Color(red: 224 / 255, green: 58 / 255, blue: 58 / 255, opacity: 0.1)
        case .skipped: return Color(hex: "111A2C")
        }
    }

    private func chipStroke(state: SpeedTestViewModel.ChipState) -> Color {
        switch state {
        case .active: return .clear
        case .completed, .pending: return Color(hex: "5B9BFF").opacity(0.3)
        case .failed: return Color(red: 224 / 255, green: 58 / 255, blue: 58 / 255, opacity: 0.35)
        case .skipped: return Color(hex: "1C2740")
        }
    }

    private func chipTextColor(state: SpeedTestViewModel.ChipState) -> Color {
        switch state {
        case .active: return .white
        case .completed, .pending: return Color(hex: "5B9BFF")
        case .failed: return Color(hex: "FF7070")
        case .skipped: return Color(hex: "7D8BA3")
        }
    }

    private var gaugeBlock: some View {
        VStack(spacing: 0) {
            SpeedGaugeView(progress: gaugeProgress)
                .frame(height: 160)

            speedValueLabel
                .padding(.top, 24)
        }
    }

    private var gaugeProgress: Double {
        if viewModel.failedStep == .speed { return 0 }
        return gaugeFraction(for: viewModel.currentSpeedMbps)
    }

    private func gaugeFraction(for mbps: Double) -> Double {
        let anchors: [(mbps: Double, frac: Double)] = [
            (0, 0.0), (50, 0.25), (100, 0.5), (200, 0.75), (300, 1.0)
        ]
        if mbps <= 0 { return 0 }
        if mbps >= 300 { return 1 }
        for i in 0..<(anchors.count - 1) {
            let a = anchors[i]
            let b = anchors[i + 1]
            if mbps >= a.mbps && mbps <= b.mbps {
                let t = (mbps - a.mbps) / (b.mbps - a.mbps)
                return a.frac + t * (b.frac - a.frac)
            }
        }
        return 1
    }

    @ViewBuilder
    private var speedValueLabel: some View {
        VStack(spacing: 6) {
            if viewModel.failedStep == .speed {
                Text("-- --")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(.white)
                    .transition(.opacity)
            } else if viewModel.showsGaugeValue {
                Text("\(Int(viewModel.currentSpeedMbps))")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .fill(.white)
                            .frame(width: 12, height: 3)
                            .cornerRadius(1.5)
                    }
                }
                .frame(height: 56)
            }

            if viewModel.failedStep == .speed {
                Text("Connection failed")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: "FF7070"))
                    .tracking(2.2)
                    .transition(.opacity)
            } else {
                Text("MBPS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(gaugeSubtitleColor)
                    .tracking(2)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.failedStep)
    }

    private var gaugeSubtitleColor: Color {
        viewModel.failedStep == nil ? .white.opacity(0.6) : Color(hex: "7D8BA3")
    }

    private var actionButton: some View {
        Button {
            viewModel.actionButtonTapped()
        } label: {
            HStack(spacing: 8) {
                if !viewModel.isRunning {
                    Image(systemName: actionIconName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
                Text(viewModel.actionButtonTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Capsule().fill(actionButtonFill))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRunning)
        .animation(.easeInOut(duration: 0.35), value: viewModel.isRunning)
        .animation(.easeInOut(duration: 0.35), value: viewModel.failedStep)
    }

    private var actionIconName: String {
        switch viewModel.failedStep {
        case .speed: return "arrow.clockwise"
        case .ip, .dns: return "arrow.triangle.2.circlepath"
        case .none: return "play.fill"
        }
    }

    private var actionButtonFill: AnyShapeStyle {
        if viewModel.isRunning {
            return AnyShapeStyle(Color.white.opacity(0.08))
        }
        switch viewModel.failedStep {
        case .speed:
            return AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: Color(hex: "E03A3A"), location: 0.0),
                    .init(color: Color(hex: "B02828"), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
        case .ip, .dns:
            return AnyShapeStyle(RadialGradient(
                colors: [Color(hex: "F0A020"), Color(hex: "C27A07")],
                center: .center,
                startRadius: 0,
                endRadius: 140
            ))
        case .none:
            return AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: Color(hex: "5295FF"), location: 0.0),
                    .init(color: Color(hex: "2F6BFF"), location: 0.55),
                    .init(color: Color(hex: "2459E8"), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
    }

    private func alertBanner(_ model: ErrorBannerModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(model.iconColor)
            Text(model.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(model.textColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(model.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(model.border, lineWidth: 1)
        )
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let card = viewModel.errorCard {
                errorCardView(card)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }

            sectionHeader("CONNECTION")
                .padding(.horizontal, 16)
                .padding(.top, viewModel.errorCard == nil ? 16 : 12)
                .padding(.bottom, 4)

            infoRowConnection(title: "Server", role: .vpnServer)
            divider
            infoRowConnection(title: "Protocol", role: .protocolName)
            divider
            infoRowConnection(title: "Endpoint IP", role: .endpoint)
            divider
            infoRowConnection(title: "Tunnel latency", role: .latency)
            divider
            infoRowConnection(title: "Session traffic", role: .sessionTraffic)

            sectionHeader("SPEED")
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 4)

            infoRowConnection(title: "Download", role: .download)
            divider
            infoRowConnection(title: "Upload", role: .upload)
        }
        .padding(.bottom, 12)
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

    private func errorCardView(_ model: ErrorCardModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(model.iconColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(model.titleColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(model.message)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(model.messageColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(model.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(model.border, lineWidth: 1)
        )
    }

    private enum InfoRole {
        case vpnServer, protocolName, endpoint, download, upload, latency, sessionTraffic
    }

    private func infoRowConnection(title: LocalizedStringResource, role: InfoRole) -> some View {
        let (value, color) = infoValue(for: role)
        return infoRow(title: title, value: value, valueColor: color)
    }

    private func infoValue(for role: InfoRole) -> (String, Color) {
        let failed = viewModel.failedStep
        let dashColor = Color(hex: "2C3A58")
        let redValue = Color(hex: "FF7070")

        switch role {
        case .vpnServer:
            if failed == .speed { return ("Unreachable", redValue) }
            return (viewModel.vpnServerLabel, Color(hex: "34D27A"))
        case .protocolName:
            if failed == .speed { return ("—", dashColor) }
            return (viewModel.protocolLabel, .white)
        case .endpoint:
            if failed == .speed { return ("—", dashColor) }
            return (viewModel.endpointLabel, .white)
        case .download:
            if failed == .speed { return ("—", dashColor) }
            return (viewModel.downloadLabel, .white)
        case .upload:
            if failed == .speed { return ("—", dashColor) }
            return (viewModel.uploadLabel, .white)
        case .latency:
            return (viewModel.tunnelLatencyLabel, .white)
        case .sessionTraffic:
            return (viewModel.sessionTrafficLabel, .white)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hex: "5B9BFF"))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(title: LocalizedStringResource, value: String, valueColor: Color = .white) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(valueColor)
                .contentTransition(.opacity)
                .id(value)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.35), value: value)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }
}

#Preview {
    SpeedTestView()
}
