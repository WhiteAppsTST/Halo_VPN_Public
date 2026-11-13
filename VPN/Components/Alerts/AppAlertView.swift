import SwiftUI

enum AppAlertKind: Hashable {
    case info
    /// Предлагает добавить конфиг (кнопка «+ Add Server»).
    case addServer
    /// Упёрлись в лимит бесплатного плана — показываем и апгрейд, и добавление.
    case upgrade
}

struct AppAlertModel: Identifiable, Hashable {
    let id = UUID()
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let kind: AppAlertKind

    static func == (lhs: AppAlertModel, rhs: AppAlertModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension AppAlertModel {
    static var disconnectFirst: AppAlertModel {
        AppAlertModel(
            title: "Disconnect first",
            message: "Please end your current connection before selecting another server.",
            kind: .info
        )
    }
}

struct AppAlertView: View {
    let model: AppAlertModel
    var onClose: () -> Void = {}
    var onUnlock: () -> Void = {}
    var onAddServer: () -> Void = {}

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                closeBtn
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text(model.title)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                Text(model.message)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                switch model.kind {
                case .upgrade:
                    unlockBtn
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    orDivider
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    addServerBtn
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                case .addServer:
                    addServerBtn
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                case .info:
                    Spacer().frame(height: 12)
                }
            }
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "0B1424"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.094), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Close X
    private var closeBtn: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 10, height: 10)
                .padding(10)
                .glassedEffect(
                    in: Circle(),
                    isClear: false,
                    tint: .white.opacity(0.07),
                    interactive: false
                )
        }
    }

    // MARK: - Unlock (gradient)
    private var unlockBtn: some View {
        Button(action: onUnlock) {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white.opacity(0.18)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock Unlimited Configs")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("No limit on saved servers")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        stops: [
                            .init(color: Color(hex: "5295FF"), location: 0.0),
                            .init(color: Color(hex: "2F6BFF"), location: 0.55),
                            .init(color: Color(hex: "2459E8"), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            )
        }
    }

    // MARK: - "or" divider
    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 0.5)
            Text("or")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 0.5)
        }
    }

    // MARK: - Add server
    private var addServerBtn: some View {
        Button(action: onAddServer) {
            Text("+ Add Server")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassedEffect(
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                    isClear: false,
                    tint: .white.opacity(0.06),
                    interactive: false
                )
        }
    }
}

#Preview("Add server style") {
    Color.gray.ignoresSafeArea().overlay {
        AppAlertView(
            model: AppAlertModel(
                title: "You're Almost Ready",
                message: "Add your first proxy server to start browsing securely.",
                kind: .addServer
            )
        )
    }
}

#Preview("Info style") {
    Color.gray.ignoresSafeArea().overlay {
        AppAlertView(
            model: AppAlertModel(
                title: "Import failed",
                message: "Something went wrong while reading the configuration file.",
                kind: .info
            )
        )
    }
}
