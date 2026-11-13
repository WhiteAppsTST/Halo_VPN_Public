import SwiftUI

enum VPNConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
}

struct VPNPowerButton: View {
    let state: VPNConnectionState
    let action: () -> Void

    private let buttonSize: CGFloat = 158
    private let ringInset: CGFloat = 18
    private let ringLineWidth: CGFloat = 1
    private let iconSize: CGFloat = 50
    private let connectingTrimStart: CGFloat = 0.2
    private let connectingDuration: Double = 2.0

    @State private var trim: CGFloat = 0
    @State private var trimColor: Color = .clear

    private var ringDiameter: CGFloat { buttonSize + ringInset * 2 }

    var body: some View {
        Button(action: action) {
            ZStack {
                ringView
                buttonCircle
            }
            .frame(width: ringDiameter, height: ringDiameter)
        }
        .buttonStyle(.plain)
        .onAppear { apply(state, animated: false) }
        .onChange(of: state) { _, newValue in
            apply(newValue, animated: true)
        }
    }

    // MARK: - Ring
    private var ringView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: ringLineWidth)

            Circle()
                .trim(from: 0, to: trim)
                .stroke(trimColor, lineWidth: ringLineWidth)
                .rotationEffect(.degrees(-90 - Double(trim) * 180))
                .shadow(color: Color(hex: "5B8CFF").opacity(0.6), radius: 4)
        }
        .frame(width: ringDiameter, height: ringDiameter)
    }

    // MARK: - Button
    private var buttonCircle: some View {
        Circle()
            .fill(buttonGradient)
            .frame(width: buttonSize, height: buttonSize)
            .overlay {
                Image(systemName: "power")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(iconColor)
            }
    }

    // MARK: - Styles
    private var buttonGradient: RadialGradient {
        switch state {
        case .disconnected, .connecting:
            return RadialGradient(
                stops: [
                    .init(color: Color(hex: "2E3E5A"), location: 0),
                    .init(color: Color(hex: "141D2E"), location: 0.72)
                ],
                center: .center,
                startRadius: 0,
                endRadius: buttonSize / 2
            )
        case .connected:
            return RadialGradient(
                stops: [
                    .init(color: Color(hex: "8FC0FF"), location: 0.0),
                    .init(color: Color(hex: "5B9BFF"), location: 0.4),
                    .init(color: Color(hex: "3F7EF0"), location: 0.72),
                    .init(color: Color(hex: "2F63D8"), location: 1.0)
                ],
                center: UnitPoint(x: 0.5, y: 0.35),
                startRadius: 0,
                endRadius: buttonSize / 2 + 10
            )
        }
    }

    private var iconColor: Color {
        switch state {
        case .disconnected, .connected: return .white
        case .connecting:               return Color(hex: "5B8CFF").opacity(0.9)
        }
    }

    // MARK: - Animation driver
    private func apply(_ state: VPNConnectionState, animated: Bool) {
        switch state {
        case .disconnected:
            withAnimation(animated ? .easeInOut(duration: 0.35) : nil) {
                trim = 0
                trimColor = .clear
            }
        case .connecting:
            trim = connectingTrimStart
            trimColor = Color(hex: "5B8CFF")
            withAnimation(animated ? .easeInOut(duration: connectingDuration) : nil) {
                trim = 1
            }
        case .connected:
            trim = 1
            withAnimation(animated ? .easeInOut(duration: 0.35) : nil) {
                trimColor = Color(hex: "5A96FF").opacity(0.45)
            }
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var state: VPNConnectionState = .disconnected

        var body: some View {
            ZStack {
                Color(hex: "0B1120").ignoresSafeArea()

                VStack(spacing: 40) {
                    VPNPowerButton(state: state) {
                        switch state {
                        case .disconnected:
                            state = .connecting
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                state = .connected
                            }
                        case .connecting, .connected:
                            state = .disconnected
                        }
                    }

                    Picker("", selection: $state) {
                        Text("Off").tag(VPNConnectionState.disconnected)
                        Text("Connecting").tag(VPNConnectionState.connecting)
                        Text("On").tag(VPNConnectionState.connected)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 40)
                }
            }
        }
    }
    return Demo()
}
