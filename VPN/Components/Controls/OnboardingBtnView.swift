import SwiftUI

struct OnboardingBtnView: View {
    var title: LocalizedStringResource
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(.onboardingButton)
                .overlay {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
    }
}

#Preview {
    OnboardingBtnView(title: "dasdas", action: {})
}
