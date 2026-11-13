import SwiftUI

struct CustomFolderRowView: View {
    let folder: CustomServerFolder
    let selectedServerId: UUID?
    let onSelectServer: (VPNServerConfig) -> Void
    let onTestPing: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 10) {
            header

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(folder.servers) { server in
                        CustomServerRowView(
                            server: server,
                            isSelected: selectedServerId == server.id,
                            onTap: { onSelectServer(server) }
                        )
                    }
                }
                .task(id: folder.id) {
                    await PingCache.shared.measureAll(folder.servers)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "8B9DC3"))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)

                Text("\(Self.dateFormatter.string(from: folder.addedAt)) · \(folder.servers.count) location\(folder.servers.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(hex: "8B9DC3"))
            }

            Spacer()

            menuButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var menuButton: some View {
        Menu {
            Button {
                onTestPing()
            } label: {
                Label("Test Ping", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}
