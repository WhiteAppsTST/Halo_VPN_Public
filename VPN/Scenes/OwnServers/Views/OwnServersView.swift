import SwiftUI
import UniformTypeIdentifiers

struct OwnServersView: View {
    @State private var viewModel = OwnServersViewModel()
    @State private var foldersStore = CustomServerFoldersStore.shared
    @State private var foldersContentHeight: CGFloat = .infinity
    @Environment(SubscriptionService.self) private var subscription

    @Namespace private var transitionNS

    var body: some View {
        mainContentView
            .safeAreaInset(edge: .top) { headerView }
            // Sub-screens
            .fileImporter(
                isPresented: $viewModel.showFileImporter,
                allowedContentTypes: [.data, .plainText, .text],
                allowsMultipleSelection: false,
                onCompletion: viewModel.handleImportedFile
            )
            .fullScreenCover(isPresented: $viewModel.showScanner) {
                ScanView()
                    .navigationTransition(.zoom(sourceID: "scan", in: transitionNS))
                    .environment(viewModel)
            }
            .fullScreenCover(isPresented: $viewModel.showManualEd) {
                ManualEdView()
                    .navigationTransition(.zoom(sourceID: "manual", in: transitionNS))
                    .environment(viewModel)
            }
            .sheet(isPresented: $viewModel.showAddServerSheet) {
                AddServerSheet()
                    .environment(viewModel)
                    .presentationDetents([.height(470)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.thinMaterial)
            }
            .alert(
                "Rename folder",
                isPresented: $viewModel.showRenameFolderAlert,
                actions: {
                    TextField("Name", text: $viewModel.renameFolderText)
                    Button("Save") { viewModel.confirmRenameFolder() }
                    Button("Cancel", role: .cancel) {}
                },
                message: { Text("Enter a new name for this folder.") }
            )
            // Result alert (import success/empty/failed/addServer prompt etc.)
            .overlay(alignment: .center) {
                if let alert = viewModel.alert {
                    AppAlertView(
                        model: alert,
                        onClose: { viewModel.dismissAlert() },
                        onUnlock: {
                            viewModel.dismissAlert()
                            subscription.showPaywall(.manualServer)
                        },
                        onAddServer: {
                            viewModel.dismissAlert()
                            viewModel.showAddServerSheet = true
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.alert)
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: 0) {
            NavHeaderView(textWhite: "Halo", textColored: "Hub")
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(x: 37)

            PremiumNavBtn {
                subscription.showPaywall(.main)
            }
        }
        .padding(.trailing, 20)
        .padding(.top, 7)
    }

    // MARK: - Content
    private var mainContentView: some View {
        VStack(spacing: 0) {
            if foldersStore.isEmpty {
                Spacer(minLength: 20)
            } else {
                Color.clear.frame(height: 100)
            }

            VPNPowerButton(state: viewModel.connectionState, action: handlePowerTap)

            Spacer().frame(height: 20)

            statusLabels

            if foldersStore.isEmpty {
                Spacer(minLength: 20)
                bottomManualAddView
            } else {
                Spacer().frame(height: 33)
                foldersListView
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image(.homeBG)
                .resizable()
                .ignoresSafeArea()
        )
    }

    // MARK: - Status
    private var statusLabels: some View {
        VStack(spacing: 4) {
            Text(statusTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(statusColor)

            statusSubtitle
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: "8F8F96"))
        }
        .multilineTextAlignment(.center)
    }

    private var statusTitle: LocalizedStringResource {
        switch viewModel.connectionState {
        case .disconnected: "Click to Connect"
        case .connecting:   "Connecting..."
        case .connected:    "Connected"
        }
    }

    @ViewBuilder
    private var statusSubtitle: some View {
        switch viewModel.connectionState {
        case .disconnected:
            if let error = viewModel.connectionError {
                Text(error)
                    .foregroundStyle(Color(hex: "FF7070"))
                    .padding(.horizontal, 24)
            } else {
                Text("Connect to secure your privacy")
            }
        case .connecting:
            Text("00:00:00")
        case .connected:
            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(viewModel.elapsedText(now: context.date))
                }
                liveThroughput
            }
        }
    }

    /// Реальная скорость по счётчикам utun-интерфейса (SpeedTracker).
    private var liveThroughput: some View {
        HStack(spacing: 16) {
            Label(viewModel.downloadText, systemImage: "arrow.down")
            Label(viewModel.uploadText, systemImage: "arrow.up")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color(hex: "5B9BFF"))
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .disconnected: return .white
        case .connecting:   return .white
        case .connected:    return Color(hex: "5B9BFF")
        }
    }

    // MARK: - Empty state
    private var emptyServersText: some View {
        Text("􀁞 To start using the application, add a\nproxy server or activate a subscription\nfrom the server list.")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Color(hex: "#8F8F96"))
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private var manualAddButtonsStackView: some View {
        HStack(alignment: .center, spacing: 13) {
            // Раньше эта кнопка открывала файловый пикер — вставить
            // скопированную ссылку было нельзя вообще.
            ManualAddBtnView(type: .clipboard) {
                viewModel.addFromClipboard()
            }

            ManualAddBtnView(type: .scan) {
                viewModel.showScanner = true
            }
            .matchedTransitionSource(id: "scan", in: transitionNS)

            ManualAddBtnView(type: .manual) {
                viewModel.showManualEd = true
            }
            .matchedTransitionSource(id: "manual", in: transitionNS)
        }
    }

    private var importFileButton: some View {
        Button {
            viewModel.showFileImporter = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.plus")
                Text("Import from file")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color(hex: "5B9BFF"))
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bottomManualAddView: some View {
        VStack(alignment: .center, spacing: 12) {
            emptyServersText
                .padding(.bottom, 8)
            manualAddButtonsStackView
            importFileButton
        }
    }

    // MARK: - Folders list
    private var foldersListView: some View {
        VStack(spacing: 0) {
            // Header: + Add new server
            Button {
                // Лимит проверяется в момент сохранения — там же показывается
                // алерт с апгрейдом. Сразу бросать в пейвол по нажатию «добавить»
                // означало, что бесплатный юзер вообще не видит форму.
                viewModel.showAddServerSheet = true
            } label: {
                Text("+ Add new server")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color(hex: "5B9BFF"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.06))
            }

            // Folders container — hugs content when short, fills to bottom when tall
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(foldersStore.folders) { folder in
                        CustomFolderRowView(
                            folder: folder,
                            selectedServerId: viewModel.selectedServerId,
                            onSelectServer: { server in viewModel.selectServer(server) },
                            onTestPing: { viewModel.pingFolder(folder) },
                            onEdit: { viewModel.beginRenameFolder(folder) },
                            onDelete: { viewModel.deleteFolder(folder) }
                        )
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    guard newHeight > 0 else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        foldersContentHeight = newHeight
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: foldersContentHeight, alignment: .top)
            .background(Color.white.opacity(0.03))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Actions
    private func handlePowerTap() {
        guard !foldersStore.isEmpty else {
            viewModel.alert = .addServerPrompt
            return
        }
        viewModel.toggleVPN()
    }
}

#Preview {
    OwnServersView()
}
