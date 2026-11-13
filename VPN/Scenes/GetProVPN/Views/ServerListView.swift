import SwiftUI

struct ServerListView: View {
    @Environment(GetProVPNViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isSearching: Bool = false
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    private var displayedServers: [VPNServerConfig] {
        let base = viewModel.serversPerCountry
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }
        return base.filter { server in
            let iso = (server.countryCode ?? "").lowercased()
            let country = (countryName(server.countryCode) ?? "").lowercased()
            let remark = server.remark.lowercased()
            let host = server.host.lowercased()
            return iso.contains(query) || country.contains(query) || remark.contains(query) || host.contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
                .padding(.horizontal, 16)
                .padding(.bottom, isSearching ? 12 : 20)

            if isSearching {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    fastestRow
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    if displayedServers.isEmpty {
                        emptyState
                            .padding(.horizontal, 16)
                            .padding(.top, 40)
                    } else {
                        ForEach(Array(displayedServers.enumerated()), id: \.element.id) { pair in
                            countryRow(pair.element)
                            if pair.offset < displayedServers.count - 1 {
                                rowDivider
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(
            Image(.homeBG)
                .resizable()
                .ignoresSafeArea()
        )
        .task {
            viewModel.measurePings()
        }
    }

    // MARK: - Пустой список
    /// Пустой экран без объяснения — худшее, что можно показать. Здесь всегда
    /// видно, что именно произошло: идёт загрузка, ошибка панели или ничего
    /// не нашлось по поиску.
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            if viewModel.isLoadingServers {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Loading servers…")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
            } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                Text("No servers match your search.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color(hex: "5B9BFF"))
                Text(viewModel.loadError ?? String(localized: "No servers available yet."))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button {
                    viewModel.refreshServers()
                } label: {
                    Text("Try again")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color(hex: "2F63D8")))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Nav bar
    private var navBar: some View {
        HStack(spacing: 12) {
            circleButton(icon: "chevron.left") { dismiss() }
            // Фантомный балансир слева — чтобы левая сторона по ширине
            // равнялась правой (2 кнопки), и Spacer'ы честно центрировали тайтл.
            Color.clear.frame(width: 40, height: 40)

            Spacer()

            Text(isSearching ? "Search" : "Location")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            refreshPingsButton
            searchToggleButton
        }
    }

    /// Тумблер: открывает / скрывает search-bar. В открытом состоянии иконка залита
    /// голубым — визуальная индикация активного режима.
    private var searchToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isSearching {
                    isSearching = false
                    searchText = ""
                    searchFocused = false
                } else {
                    isSearching = true
                }
            }
            if isSearching {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    searchFocused = true
                }
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSearching ? .white : .white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(isSearching ? Color(hex: "5B9BFF").opacity(0.25) : .white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search bar
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            TextField("", text: $searchText, prompt: Text("Search…").foregroundStyle(.white.opacity(0.5)))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.08))
        )
    }

    /// Кнопка force-refresh пингов. В measuring-стейте иконка сменяется на кастомный
    /// круговой прогресс (тот же паттерн что в VPNPowerButton .connecting).
    @ViewBuilder
    private var refreshPingsButton: some View {
        Button {
            viewModel.measurePings(force: true)
        } label: {
            Group {
                if viewModel.isMeasuringPings {
                    MeasuringSpinner()
                } else {
                    Image(systemName: "gauge.open.with.lines.needle.33percent")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
            .background(Circle().fill(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isMeasuringPings)
    }

    private func circleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fastest server row
    @ViewBuilder
    private var fastestRow: some View {
        let fastest = viewModel.fastestServer
        let ping = fastest.flatMap { viewModel.ping(for: $0) }
        let isSelected = viewModel.isFastestSelected

        Button {
            viewModel.selectFastestServer()
        } label: {
            HStack(spacing: 12) {
                boltCircle

                VStack(alignment: .leading, spacing: 4) {
                    Text("Fastest server")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text(fastestSubtitle(server: fastest))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 8)

                pingText(ping)

                SignalBars(pingMs: ping)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "5B9BFF"))
                        .padding(.leading, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "5B9BFF").opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(hex: "5B9BFF").opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pingText(_ ping: Int?) -> some View {
        Text(ping.map { "\($0)ms" } ?? "...")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.white.opacity(0.7))
    }

    private var boltCircle: some View {
        Circle()
            .fill(Color(hex: "5B9BFF").opacity(0.2))
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: "5B9BFF"))
            }
            .fixedSize()
    }

    private func fastestSubtitle(server: VPNServerConfig?) -> String {
        if viewModel.isMeasuringPings {
            return String(localized: "Auto · Measuring…")
        }
        guard let server else { return String(localized: "Auto") }
        let country = countryName(server.countryCode) ?? server.remark
        return "Auto · \(country)"
    }

    // MARK: - Country rows
    private func countryRow(_ server: VPNServerConfig) -> some View {
        let ping = viewModel.ping(for: server)
        // Country подсвечивается ТОЛЬКО если fastest-mode выключен и выбран именно этот сервер.
        let isSelected = !viewModel.isFastestSelected
            && VPNService.shared.currentServer?.rawURL == server.rawURL

        return Button {
            viewModel.selectServer(server)
        } label: {
            HStack(spacing: 12) {
                flagCircle(iso: server.countryCode)

                VStack(alignment: .leading, spacing: 4) {
                    Text(countryName(server.countryCode) ?? server.remark)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(cityText(server: server))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                pingText(ping)

                SignalBars(pingMs: ping)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "5B9BFF"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 68)
    }

    private func flagCircle(iso: String?) -> some View {
        let flag = flagEmoji(iso ?? "")
        return Group {
            if !flag.isEmpty {
                Text(flag)
                    .font(.system(size: 44))
                    .fixedSize()
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(hex: "1E2A44"))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text(iso ?? "?")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .fixedSize()
    }

    // MARK: - Helpers
    private func countryName(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        return Locale.current.localizedString(forRegionCode: iso)
    }

    private func cityText(server: VPNServerConfig) -> String {
        // Backend не отдаёт city отдельно — используем remark если он не совпадает с country.
        server.remark.isEmpty ? server.host : server.remark
    }

    private func flagEmoji(_ iso: String) -> String {
        guard iso.count == 2 else { return "" }
        let base: UInt32 = 127397
        var scalars = String.UnicodeScalarView()
        for u in iso.uppercased().unicodeScalars {
            if let s = UnicodeScalar(base + u.value) {
                scalars.append(s)
            }
        }
        return String(scalars)
    }
}

// MARK: - Signal Bars (4 bars, filled by ping strength)
private struct SignalBars: View {
    let pingMs: Int?

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(barColor(index: i))
                    .frame(width: 3, height: barHeights[i])
            }
        }
    }

    private var barHeights: [CGFloat] { [5, 8, 11, 14] }

    private func barColor(index: Int) -> Color {
        let (level, activeColor) = signalLevelAndColor
        return index < level ? activeColor : .white.opacity(0.15)
    }

    private var signalLevelAndColor: (level: Int, color: Color) {
        guard let ping = pingMs else { return (0, .white.opacity(0.15)) }
        switch ping {
        case ..<80:   return (4, Color(hex: "34D27A"))
        case ..<150:  return (3, Color(hex: "34D27A"))
        case ..<250:  return (2, Color(hex: "F0B429"))
        case ..<500:  return (1, Color(hex: "E85A5A"))
        default:      return (1, Color(hex: "E85A5A"))
        }
    }
}

// MARK: - Measuring spinner
// Кастомный круговой прогресс: base-circle (white 0.4) + trim-arc (голубой),
// который растёт симметрично из верхней точки (12 часов) в обе стороны и обратно.
// Тот же паттерн, что использует VPNPowerButton в .connecting.
private struct MeasuringSpinner: View {
    var size: CGFloat = 19
    var bgColor: Color = .white.opacity(0.4)
    var activeColor: Color = Color(hex: "5B9BFF")
    var lineWidth: CGFloat = 2
    var duration: Double = 1.4

    @State private var trim: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(bgColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: trim)
                .stroke(activeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90 - Double(trim) * 180))
        }
        .frame(width: size, height: size)
        .onAppear {
            trim = 0
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: true)) {
                trim = 1
            }
        }
    }
}
