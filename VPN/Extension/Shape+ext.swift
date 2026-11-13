import SwiftUI

extension Shape {
    @ViewBuilder
    func glassed() -> some View {
        ZStack {
            self.fill(.ultraThinMaterial)
            self.stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        }
    }
}
