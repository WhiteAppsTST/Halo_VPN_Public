import SwiftUI

struct MainTabView: View {
    @State private var selectedRow: SideMenuRow = .ownerServers
    @State private var presentSideMenu: Bool = false
    @Environment(SubscriptionService.self) private var subscription

    var body: some View {
        @Bindable var subscription = subscription
        ZStack(alignment: .topLeading) {
            TabView(selection: $selectedRow) {
                ForEach(SideMenuRow.allCases, id: \.self) { row in
                    row.destinationView
                        .toolbar(.hidden, for: .tabBar)
                        .tag(row)
                }
            }

            menuButton

            SideMenuRootView(isShowing: $presentSideMenu) {
                SideMenuView(
                    selectedRow: $selectedRow,
                    presentSideMenu: $presentSideMenu
                )
            }
        }
        .fullScreenCover(isPresented: $subscription.isPaywallShown) {
            PaywallView()
                .environment(subscription)
                .preferredColorScheme(.dark)
        }
    }

    private var menuButton: some View {
        Button {
            withAnimation(.easeInOut) {
                presentSideMenu = true
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.title3)
                .foregroundStyle(.white)
                .padding(16)
                .glassedEffect(
                    in: .circle,
                    isClear: false,
                    tint: .white.opacity(0.06),
                    interactive: false
                )
        }
        .padding(.leading, 16)
        .padding(.top, 8)
        .opacity(presentSideMenu ? 0 : 1)
    }
}

#Preview {
    MainTabView()
}
