import SwiftUI

struct PremiumNavBtn: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "crown.fill")
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 13)
                .glassedEffect(
                    in: Circle(),
                    isClear: false,
                    tint: Color(hex: "#2F63D8"),
                    interactive: false
                )
        }
    }
}

#Preview {
    PremiumNavBtn(action: {})
}
