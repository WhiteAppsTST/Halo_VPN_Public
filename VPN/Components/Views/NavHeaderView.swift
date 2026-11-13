import SwiftUI

struct NavHeaderView: View {
    let textWhite: String
    let textColored: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(textWhite)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
            
            Text(textColored)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(hex: "#5B9BFF"))
        }
    }
}

#Preview {
    NavHeaderView(textWhite: "adsa", textColored: "dd22")
}
