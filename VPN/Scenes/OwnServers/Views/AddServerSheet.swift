import SwiftUI

struct AddServerSheet: View {
    @Environment(OwnServersViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add server")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            Text("Choose how to import your configuration")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "8B9DC3"))
                .padding(.bottom, 24)

            VStack(spacing: 12) {
                actionRow(
                    icon: ManualAddBtnViewType.clipboard.icon,
                    title: "Clipboard",
                    subtitle: "Paste a vless / vmess / trojan / ss link"
                ) {
                    closeAndTrigger { viewModel.addFromClipboard() }
                }

                actionRow(
                    icon: "doc.badge.plus",
                    title: "Import file",
                    subtitle: "Subscription or list of links"
                ) {
                    closeAndTrigger { viewModel.showFileImporter = true }
                }

                actionRow(
                    icon: ManualAddBtnViewType.scan.icon,
                    title: "Scan QR",
                    subtitle: "Scan a configuration QR code"
                ) {
                    closeAndTrigger { viewModel.showScanner = true }
                }

                actionRow(
                    icon: ManualAddBtnViewType.manual.icon,
                    title: "Manual entry",
                    subtitle: "Host, port, protocol, key"
                ) {
                    closeAndTrigger { viewModel.showManualEd = true }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }

    // MARK: - Row
    private func actionRow(
        icon: String,
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: "5B9BFF"))
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: "8B9DC3"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "8B9DC3"))
            }
            .padding(.horizontal, 21.75)
            .padding(.vertical, 14)
            .glassedEffect(
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                isClear: false,
                tint: .white.opacity(0.05),
                interactive: false
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions
    private func closeAndTrigger(_ trigger: @escaping () -> Void) {
        viewModel.showAddServerSheet = false
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            await MainActor.run { trigger() }
        }
    }
}

#Preview {
    Color.gray.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AddServerSheet()
                .environment(OwnServersViewModel())
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
}
