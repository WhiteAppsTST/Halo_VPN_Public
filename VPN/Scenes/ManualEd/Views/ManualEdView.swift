import SwiftUI

struct ManualEdView: View {
    @Environment(OwnServersViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, host, port, uuid, password, sni, publicKey, shortID
        case path, wsHost, serviceName, alterId, flow
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                protocolSection
                serverDetailsSection
                finalMaskSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .safeAreaInset(edge: .top) { topBar }
        .background(
            Image("subScreenBG")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack(alignment: .center) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(17)
                    .glassedEffect(
                        in: Circle(),
                        isClear: false,
                        tint: .white.opacity(0.06),
                        interactive: false
                    )
            }

            Spacer()

            Text("Manual Setup")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)

            Spacer()

            Button {
                if viewModel.saveManual() { dismiss() }
            } label: {
                Text("Save")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(viewModel.canSaveManual ? Color(hex: "5B9BFF") : Color(hex: "5A6A86"))
            }
            .disabled(!viewModel.canSaveManual)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Sections
    private var protocolSection: some View {
        @Bindable var vm = viewModel
        return section(title: "PROTOCOL") {
            row(label: "Protocol") {
                menuPicker(
                    selection: $vm.manualForm.proto,
                    cases: ManualEdProtocol.allCases,
                    title: { $0.title }
                )
            }
        }
    }

    @ViewBuilder
    private var serverDetailsSection: some View {
        @Bindable var vm = viewModel

        section(title: "SERVER DETAILS") {
            row(label: "Name") {
                textField("Server Name", text: $vm.manualForm.name, focus: .name)
            }
            divider

            row(label: "Server Address") {
                textField("enter IP or Domain", text: $vm.manualForm.host, focus: .host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            divider

            row(label: "Port") {
                textField("enter Port", text: $vm.manualForm.port, focus: .port)
                    .keyboardType(.numberPad)
            }
            divider

            protocolSpecificRows

            row(label: "Network") {
                menuPicker(
                    selection: $vm.manualForm.network,
                    cases: ManualEdNetwork.allCases,
                    title: { $0.title }
                )
            }

            transportRows

            divider

            row(label: "Security") {
                switch vm.manualForm.proto {
                case .vmess:
                    menuPicker(
                        selection: $vm.manualForm.vmessSecurity,
                        cases: ManualEdVmessSecurity.allCases,
                        title: { $0.title }
                    )
                default:
                    menuPicker(
                        selection: $vm.manualForm.security,
                        cases: ManualEdSecurity.allCases,
                        title: { $0.title }
                    )
                }
            }

            if vm.manualForm.proto == .vmess {
                divider
                row(label: "TLS") {
                    Toggle("", isOn: $vm.manualForm.vmessTLS)
                        .labelsHidden()
                        .tint(Color(hex: "34D27A"))
                }
            }

            tlsRealityRows
        }
    }

    /// Параметры транспорта. Без них WS/gRPC-конфиги собирались без path
    /// и сервер такие соединения отбивал.
    @ViewBuilder
    private var transportRows: some View {
        @Bindable var vm = viewModel

        switch vm.manualForm.network {
        case .ws:
            divider
            row(label: "Path") {
                textField("/path", text: $vm.manualForm.path, focus: .path)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            divider
            row(label: "Host header") {
                textField("optional", text: $vm.manualForm.wsHost, focus: .wsHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        case .grpc:
            divider
            row(label: "Service Name") {
                textField("serviceName", text: $vm.manualForm.path, focus: .serviceName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        case .tcp:
            divider
            row(label: "Header Type") {
                menuPicker(
                    selection: $vm.manualForm.headerType,
                    cases: ManualEdHeaderType.allCases,
                    title: { $0.title }
                )
            }
        }
    }

    @ViewBuilder
    private var protocolSpecificRows: some View {
        @Bindable var vm = viewModel

        switch vm.manualForm.proto {
        case .vless:
            row(label: "UUID") {
                textField("Enter UUID", text: $vm.manualForm.uuid, focus: .uuid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            divider
        case .vmess:
            row(label: "UUID") {
                textField("Enter UUID", text: $vm.manualForm.uuid, focus: .uuid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            divider
            row(label: "alterId") {
                textField("0", text: $vm.manualForm.alterId, focus: .alterId)
                    .keyboardType(.numberPad)
            }
            divider
        case .trojan:
            row(label: "Password") {
                textField("Enter Password", text: $vm.manualForm.password, focus: .password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            divider
        case .shadowsocks:
            row(label: "Password") {
                textField("Enter Password", text: $vm.manualForm.password, focus: .password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            divider
            row(label: "Method") {
                menuPicker(
                    selection: $vm.manualForm.ssMethod,
                    cases: ManualEdSSMethod.allCases,
                    title: { $0.title }
                )
            }
            divider
        }
    }

    @ViewBuilder
    private var tlsRealityRows: some View {
        @Bindable var vm = viewModel

        let showSNI: Bool = {
            switch vm.manualForm.proto {
            case .vless:  return vm.manualForm.security != .none
            case .trojan: return vm.manualForm.security == .tls
            case .vmess:  return vm.manualForm.vmessTLS
            case .shadowsocks: return false
            }
        }()

        if showSNI {
            divider
            row(label: "SNI") {
                textField("example.com", text: $vm.manualForm.sni, focus: .sni)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }

        if showSNI, vm.manualForm.proto != .vmess {
            divider
            row(label: "Fingerprint") {
                menuPicker(
                    selection: $vm.manualForm.fingerprint,
                    cases: ManualEdFingerprint.allCases,
                    title: { $0.title }
                )
            }
        }

        if vm.manualForm.proto == .vless, vm.manualForm.security == .reality {
            divider
            row(label: "Public Key") {
                textField("pbk", text: $vm.manualForm.publicKey, focus: .publicKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            divider
            row(label: "Short ID") {
                textField("sid", text: $vm.manualForm.shortID, focus: .shortID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            divider
            row(label: "Flow") {
                textField("xtls-rprx-vision", text: $vm.manualForm.flow, focus: .flow)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    // MARK: - FinalMask preview
    private var finalMaskSection: some View {
        section(title: "SERVER DETAILS") {
            VStack(alignment: .leading, spacing: 10) {
                Text("FinalMask")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text(viewModel.previewShareLink.isEmpty ? "{FinalMaskObject}" : viewModel.previewShareLink)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: "5A6A86").opacity(0.35))
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Helpers
    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "8E8E93"))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0, content: content)
                .glassedEffect(
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                    isClear: false,
                    tint: .white.opacity(0.05),
                    interactive: false
                )
        }
    }

    private func row<Trailing: View>(
        label: LocalizedStringResource,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 19)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(height: 0.5)
    }

    private func textField(_ placeholder: String, text: Binding<String>, focus: Field) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.25)))
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.white)
            .multilineTextAlignment(.trailing)
            .focused($focusedField, equals: focus)
    }

    private func menuPicker<T: Identifiable & Hashable>(
        selection: Binding<T>,
        cases: [T],
        title: @escaping (T) -> String
    ) -> some View {
        Menu {
            ForEach(cases, id: \.self) { value in
                Button {
                    selection.wrappedValue = value
                } label: {
                    if value == selection.wrappedValue {
                        Label(title(value), systemImage: "checkmark")
                    } else {
                        Text(title(value))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title(selection.wrappedValue))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "5B9BFF"))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "5B9BFF"))
            }
        }
    }
}

#Preview {
    ManualEdView()
        .environment(OwnServersViewModel())
}
