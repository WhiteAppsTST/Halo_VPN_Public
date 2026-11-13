import SwiftUI

//MARK: - ViewBuilders
extension View {
    @ViewBuilder
    func glassedEffect(
        in shape: some Shape,
        isClear: Bool = false,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26, *) {
            if interactive {
                self.glassEffect(isClear ? .clear.interactive().tint(tint) : .regular.interactive().tint(tint), in: shape)
            } else {
                self.glassEffect(isClear ? .clear.tint(tint) : .regular.tint(tint), in: shape)
            }
        } else {
            self
                .background {
                    shape.glassed()
                }
                .background(tint)
        }
    }

    @ViewBuilder
    func glassedEffect(
        in shape: some Shape,
        interactive: Bool = false) -> some View {

            if #available(iOS 26, *) {
                if interactive {
                    self.glassEffect(.clear.interactive(), in: shape)
                } else {
                    self.glassEffect(.clear.interactive(), in: shape)
                }
            } else {
                self.background {
                    shape.glassed()
                }
            }
    }
}
