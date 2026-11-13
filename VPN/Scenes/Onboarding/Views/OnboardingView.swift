import SwiftUI

struct OnboardingView: View {
    @AppStorage(AppConstants.UDKeys.obStatusFlag) private var isObFinished: Bool = false
    @State private var currentTab: OnboardingTabs = .first
    
    var body: some View {
        TabView(selection: $currentTab) {
            ForEach(OnboardingTabs.allCases) { tab in
                pageView(for: tab)
                    .tag(tab)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .tabViewStyle(.page(indexDisplayMode: .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .overlay(alignment: .bottom) {
            OnboardingBtnView(title: currentTab.nextBtnTitle, action: nextTapped)
        }
    }
    
    private func pageView(for tab: OnboardingTabs) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            titleView(for: tab)
                .font(.system(size: 33, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)
            
            Text(tab.subtitle)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 125)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .padding(.leading, 16)
        .background(
            Image(tab.bgImage)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .scaleEffect(1.1)
        )
    }
    
    private func titleView(for tab: OnboardingTabs) -> some View {
        let items = tab.titleTextes
        let firstLine = items.first
        let secondLine = items.dropFirst().enumerated().reduce(Text("")) { partial, pair in
            let piece = Text(pair.element.text).foregroundStyle(pair.element.color)
            return pair.offset == 0 ? partial + piece : partial + Text(" ") + piece
        }

        return VStack(alignment: .center, spacing: 4) {
            if let firstLine {
                Text(firstLine.text)
                    .foregroundStyle(firstLine.color)
            }
            secondLine
        }
    }
}

private extension OnboardingView {
    func nextTapped() {
        withAnimation(.linear(duration: 0.34)) {
            switch currentTab {
            case .first:
                currentTab = .second
            case .second:
                currentTab = .third
            case .third:
                isObFinished = true
                SubscriptionService.shared.limitedButtonTapped()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    SubscriptionService.shared.showPaywall(.main)
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
}
