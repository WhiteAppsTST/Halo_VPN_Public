import SwiftUI

enum ManualAddBtnViewType: Identifiable, CaseIterable {
    var id: Self {self}
    
    case clipboard, scan, manual
    
    var icon: String {
        switch self {
        case .clipboard:
            "chart.line.text.clipboard"
        case .scan:
            "qrcode.viewfinder"
        case .manual:
            "pencil.line"
        }
    }
    
    var title: String {
        switch self {
        case .clipboard:
            "Clipboard"
        case .scan:
            "Scan QR"
        case .manual:
            "Manual Entry"
        }
    }
}

struct ManualAddBtnView: View {
    let type: ManualAddBtnViewType
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Color.white
                .opacity(0.06)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(width: 100, height: 100)
                .overlay {
                    VStack(alignment: .center, spacing: 10) {
                        Image(systemName: type.icon)
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.5))
                        
                        Text(type.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                    }
                }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        ManualAddBtnView(type: .clipboard, action: {})
    }
}
