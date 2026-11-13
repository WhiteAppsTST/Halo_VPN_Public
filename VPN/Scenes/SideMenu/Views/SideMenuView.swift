import SwiftUI

struct SideMenuView: View {
    @AppStorage(AppConstants.UDKeys.userNameFlag) private var userName: String = "Username"

    @Binding var selectedRow: SideMenuRow
    @Binding var presentSideMenu: Bool

    @State private var showRenameSheet: Bool = false
    @State private var iconTriggers: [Int] = Array(repeating: 0, count: SideMenuRow.allCases.count)
    @State private var subscription = SubscriptionService.shared

    private var displayName: String {
        userName.isEmpty ? "Username" : userName
    }

    private var hasPremium: Bool { subscription.isActiveSubscription }

    private var planTitle: LocalizedStringResource {
        hasPremium ? "Premium" : "Free plan"
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                    .padding(.top, 60)

                divider
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    sectionHeader("SERVERS")
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ownerServersRow
                    vpnRow(isPremium: hasPremium)

                    sectionHeader("SECURITY")
                        .padding(.top, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    privacyRow

                    sectionHeader("PREFERENCES")
                        .padding(.top, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    speedRow
                    settingsRow
                    supportRow
                }

                Spacer()
            }
            .frame(width: 306)
            .background(Color("menuBG"))

            Spacer()
        }
        .background(.clear)
        .overlay {
            if showRenameSheet {
                ChangeNameSheet(
                    initial: userName,
                    onSave: { newName in
                        userName = newName
                        dismissRenameSheet()
                    },
                    onClose: dismissRenameSheet
                )
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .center)))
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: showRenameSheet)
        .task {
            try? await Task.sleep(for: .milliseconds(120))
            for i in iconTriggers.indices {
                iconTriggers[i] &+= 1
                try? await Task.sleep(for: .milliseconds(55))
            }
        }
    }

    //MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: 13) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "3D8BFD"), Color(hex: "2563EB")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 46, height: 46)
                .overlay {
                    Text(String(displayName.first ?? "?").uppercased())
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(spacing: 3) {
                Text(displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(planTitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(hex: "7D8BA3"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            nameEditBtn
        }
        .padding(20)
    }

    private var nameEditBtn: some View {
        Button {
            showRenameSheet = true
        } label: {
            Image(systemName: "pencil.line")
                .font(.title3)
                .foregroundStyle(Color(hex: "8B9DC3"))
                .padding(9.68)
                .glassedEffect(
                    in: RoundedRectangle(cornerRadius: 9),
                    isClear: false,
                    tint: Color(hex: "16203A"),
                    interactive: false
                )
        }
    }

    //MARK: - Section header + divider
    private func sectionHeader(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color(hex: "5A6A86"))
            .padding(.leading, 24)
            .padding(.bottom, 6)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(hex: "5A6A86"))
            .frame(height: 1)
    }

    //MARK: - Rows: Servers section
    private var ownerServersRow: some View {
        rowButton(
            row: .ownerServers,
            symbolTrigger: iconTriggers[0],
            trailing: { EmptyView() },
            action: { selectRow(.ownerServers) }
        )
    }

    /// Серверы из подписки — премиум-функция: без активной подписки
    /// строка ведёт на пейвол, а не на экран.
    private func vpnRow(isPremium: Bool) -> some View {
        rowButton(
            row: .vpn,
            symbolTrigger: iconTriggers[1],
            trailing: {
                if !isPremium {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "FBBF24"))
                }
            },
            action: {
                if isPremium {
                    selectRow(.vpn)
                } else {
                    presentSideMenu = false
                    subscription.showPaywall(.main)
                }
            }
        )
    }

    //MARK: - Rows: Security section
    private var privacyRow: some View {
        rowButton(
            row: .privacy,
            symbolTrigger: iconTriggers[2],
            trailing: { EmptyView() },
            action: { selectRow(.privacy) }
        )
    }

    //MARK: - Rows: Preferences section
    private var speedRow: some View {
        rowButton(
            row: .speed,
            symbolTrigger: iconTriggers[3],
            trailing: { EmptyView() },
            action: { selectRow(.speed) }
        )
    }

    private var settingsRow: some View {
        rowButton(
            row: .settings,
            symbolTrigger: iconTriggers[4],
            trailing: { EmptyView() },
            action: { selectRow(.settings) }
        )
    }

    private var supportRow: some View {
        rowButton(
            row: .support,
            symbolTrigger: iconTriggers[5],
            trailing: { EmptyView() },
            action: { selectRow(.support) }
        )
    }

    //MARK: - Row factory
    private func rowButton<Trailing: View>(
        row: SideMenuRow,
        isSelected: Bool? = nil,
        symbolTrigger: Int,
        @ViewBuilder trailing: () -> Trailing,
        action: @escaping () -> Void
    ) -> some View {
        let selected = isSelected ?? (selectedRow == row)
        let contentColor: Color = selected ? .white : Color(hex: "8B9DC3")
        let iconColor: Color = {
            switch row {
            case .ownerServers, .vpn, .privacy: return Color(hex: "3D8BFD")
            default: return contentColor
            }
        }()

        return Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: row.iconName)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .symbolEffect(.bounce.up, options: .nonRepeating, value: symbolTrigger)

                Text(row.title)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(contentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                trailing()

                if selected {
                    Circle()
                        .fill(Color(hex: "5B9BFF"))
                        .frame(width: 9, height: 9)
                }
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 12)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: "101A2E"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(hex: "1E2A44"), lineWidth: 1)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    //MARK: - Actions
    private func selectRow(_ row: SideMenuRow) {
        selectedRow = row
        presentSideMenu = false
    }

    private func dismissRenameSheet() {
        showRenameSheet = false
    }
}

//MARK: - Change-name modal

private struct ChangeNameSheet: View {
    let initial: String
    let onSave: (String) -> Void
    let onClose: () -> Void

    @State private var name: String = ""
    @FocusState private var focused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool { !trimmed.isEmpty }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            // Card
            VStack(spacing: 0) {
                title
                inputField
                    .padding(.top, 20)
                saveButton
                    .padding(.top, 24)
            }
            .padding(EdgeInsets(top: 24, leading: 20, bottom: 28, trailing: 20))
            .frame(width: 347)
            .background(cardBackground)
            .overlay(alignment: .top) { topHairline }
            .overlay(alignment: .topTrailing) { closeButton }
            .compositingGroup()
            .shadow(color: .black.opacity(0.4),  radius: 10, y: 8)
            .shadow(color: .black.opacity(0.55), radius: 28, y: 24)
            .shadow(color: .black.opacity(0.75), radius: 65, y: 48)
            .padding(.horizontal, 20)
        }
        .onAppear {
            name = initial
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                focused = true
            }
        }
    }

    // MARK: - Sub-views

    private var title: some View {
        Text("Change name")
            .font(.system(size: 17, weight: .bold))
            .tracking(-0.55)
            .foregroundStyle(.white)
    }

    private var inputField: some View {
        TextField(
            "",
            text: $name,
            prompt: Text("Enter your Name…")
                .foregroundStyle(.white.opacity(0.5))
        )
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled(true)
        .focused($focused)
        .submitLabel(.done)
        .onSubmit { if canSave { onSave(trimmed) } }
        .font(.system(size: 14, weight: .regular))
        .foregroundStyle(.white)
        .frame(height: 53)
        .padding(.horizontal, 15)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var saveButton: some View {
        Button {
            guard canSave else { return }
            onSave(trimmed)
        } label: {
            Text("Save")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.25)
                .foregroundStyle(.white.opacity(canSave ? 1 : 0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.white.opacity(0.05))
                        if canSave {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "5A9FF5"), Color(hex: "2563EB")],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .transition(.opacity)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .animation(.easeInOut(duration: 0.22), value: canSave)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 19)
        .padding(.top, 19)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(Color(hex: "0B1424"))
            .overlay(
                // Subtle blue radial glow inside the card (see Figma #424:427).
                RadialGradient(
                    colors: [Color(hex: "4E8CFF").opacity(0.06), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 220
                )
                .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(.white.opacity(0.09), lineWidth: 1)
            )
    }

    private var topHairline: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.18), location: 0.4),
                .init(color: .white.opacity(0.18), location: 0.6),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.horizontal, 41)
        .padding(.top, 1)
        .allowsHitTesting(false)
    }
}

#Preview {
    SideMenuView(
        selectedRow: .constant(.ownerServers),
        presentSideMenu: .constant(true)
    )
}
