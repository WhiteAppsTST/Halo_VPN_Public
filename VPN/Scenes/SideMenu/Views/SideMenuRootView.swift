import SwiftUI
 
struct SideMenuRootView<Content: View>: View {
    @Binding var isShowing: Bool
    var edgeTransition: AnyTransition = .move(edge: .leading)
    @ViewBuilder var content: () -> Content
 
    var body: some View {
        ZStack(alignment: .bottom) {
            if isShowing {
                Color.black
                    .opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isShowing.toggle()
                    }
                content()
                    .transition(edgeTransition)
                    .background(Color.clear)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .animation(.easeInOut, value: isShowing)
    }
}
 
#Preview {
    SideMenuRootView(isShowing: .constant(true)) {
        Text("Menu content")
    }
}
 
