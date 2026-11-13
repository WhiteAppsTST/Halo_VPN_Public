import SwiftUI

struct GetProVPNView: View {
    @State private var viewModel = GetProVPNViewModel()
    @Environment(SubscriptionService.self) private var subscription

    @Namespace private var serverTransitionNS

    var body: some View {
        mainContentView
            .safeAreaInset(edge: .top) { headerView }
            .fullScreenCover(isPresented: $viewModel.showServerList) {
                ServerListView()
                    .navigationTransition(.zoom(sourceID: "serverRow", in: serverTransitionNS))
                    .environment(viewModel)
            }
            .task {
                viewModel.refreshServers()
            }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: 0) {
            NavHeaderView(textWhite: "Halo", textColored: "VPN")
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(x: 37)

            PremiumNavBtn {
                subscription.showPaywall(.main)
            }
        }
        .padding(.trailing, 20)
        .padding(.top, 7)
    }

    // MARK: - Content
    private var mainContentView: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 100)

            VPNPowerButton(state: viewModel.connectionState, action: handlePowerTap)

            Spacer().frame(height: 20)

            statusLabels

            Spacer(minLength: 0)

            speedPanel
                .padding(.horizontal, 20)

            Spacer().frame(height: 20)

            serverRow
                .matchedTransitionSource(id: "serverRow", in: serverTransitionNS)
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image(.homeBG)
                .resizable()
                .ignoresSafeArea()
        )
    }

    // MARK: - Status
    private var statusLabels: some View {
        VStack(spacing: 4) {
            Text(statusTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(statusColor)

            statusSubtitle
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: "8F8F96"))
        }
        .multilineTextAlignment(.center)
    }

    private var statusTitle: LocalizedStringResource {
        switch viewModel.connectionState {
        case .disconnected: "Click to Connect"
        case .connecting:   "Connecting..."
        case .connected:    "Connected"
        }
    }

    @ViewBuilder
    private var statusSubtitle: some View {
        switch viewModel.connectionState {
        case .disconnected:
            Text("Connect to secure your privacy")
        case .connecting:
            Text("00:00:00")
        case .connected:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(viewModel.elapsedText(now: context.date))
            }
        }
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .disconnected: return .white
        case .connecting:   return .white
        case .connected:    return Color(hex: "5B9BFF")
        }
    }

    // MARK: - Speed panel
    private var speedPanel: some View {
        HStack(spacing: 20) {
            SpeedPanelItemView(direction: .download, value: viewModel.downloadKBps)
            SpeedPanelItemView(direction: .upload,   value: viewModel.uploadKBps)
        }
    }

    // MARK: - Server row
    private var serverRow: some View {
        SelectedServerRowView(
            server: viewModel.currentServer,
            pingMs: viewModel.currentPingMs,
            onTap: { viewModel.showServerList = true }
        )
    }

    // MARK: - Actions
    private func handlePowerTap() {
        viewModel.toggleVPN()
    }
}

#Preview {
    GetProVPNView()
}
