import SwiftUI

struct ScanView: View {
    @Environment(OwnServersViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var torchOn: Bool = false
    @State private var permissionDenied: Bool = false
    @State private var isProcessing: Bool = false
    @State private var command = ScanCameraCommand()

    var body: some View {
        ZStack {
            ScanCameraView(
                torchOn: $torchOn,
                command: command,
                onCaptured: { image in
                    Task { @MainActor in await handleCaptured(image) }
                },
                onPermissionDenied: {
                    Task { @MainActor in permissionDenied = true }
                }
            )
            .ignoresSafeArea()

            Color.black.opacity(0.35)
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            ScanFrameView()
                .frame(height: 353)
                .padding(.horizontal, 53)
                .padding(.top, 70)
        }
        .overlay(alignment: .topLeading) {
            closeButton
                .padding(.leading, 20)
                .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            torchButton
                .padding(.trailing, 20)
                .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            captureBtn
                .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .alert(
            "Camera Access Needed",
            isPresented: $permissionDenied,
            actions: {
                Button("Cancel", role: .cancel) { finish(with: nil) }
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    finish(with: nil)
                }
            },
            message: {
                Text("Enable camera access in Settings to scan QR codes.")
            }
        )
    }

    private var closeButton: some View {
        Button {
            finish(with: nil)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .contentShape(Rectangle())
        }
    }

    /// Фонарик: состояние было заведено, но включить его было нечем.
    private var torchButton: some View {
        Button {
            torchOn.toggle()
        } label: {
            Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(torchOn ? Color(hex: "FBBF24") : .white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private var captureBtn: some View {
        Button {
            guard !isProcessing else { return }
            isProcessing = true
            command.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 96, height: 96)

                Circle()
                    .fill(Color.white)
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.black)
                    }
            }
        }
        .disabled(isProcessing)
    }

    // MARK: - Actions
    private func handleCaptured(_ image: UIImage?) async {
        guard let image else {
            finish(with: nil)
            return
        }
        let payload = await QRScannerService.scan(image: image)
        finish(with: payload)
    }

    private func finish(with payload: String?) {
        viewModel.handleScannedPayload(payload)
        dismiss()
    }
}

// MARK: - Scan Frame (4 corner brackets + 4 mid-edge strips + animated gradient beam)
private struct ScanFrameView: View {
    var color: Color = .white
    var lineWidth: CGFloat = 4
    var cornerLength: CGFloat = 40
    var cornerRadius: CGFloat = 20
    var edgeStripLength: CGFloat = 60
    var beamHeight: CGFloat = 44
    var animationDuration: Double = 2.2

    @State private var beamAtBottom: Bool = false

    private var beamGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "5B9BFF").opacity(0.54), location: 0.0),
                .init(color: Color(hex: "5B9BFF").opacity(0.0),  location: 0.5)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let r = cornerRadius
            let strip = edgeStripLength

            ZStack(alignment: .top) {
                Path { p in
                    // Top-left corner
                    p.move(to: CGPoint(x: 0, y: cornerLength))
                    p.addLine(to: CGPoint(x: 0, y: r))
                    p.addArc(tangent1End: CGPoint(x: 0, y: 0),
                             tangent2End: CGPoint(x: r, y: 0),
                             radius: r)
                    p.addLine(to: CGPoint(x: cornerLength, y: 0))

                    // Top-right corner
                    p.move(to: CGPoint(x: w - cornerLength, y: 0))
                    p.addLine(to: CGPoint(x: w - r, y: 0))
                    p.addArc(tangent1End: CGPoint(x: w, y: 0),
                             tangent2End: CGPoint(x: w, y: r),
                             radius: r)
                    p.addLine(to: CGPoint(x: w, y: cornerLength))

                    // Right-center strip
                    p.move(to: CGPoint(x: w, y: (h - strip) / 2))
                    p.addLine(to: CGPoint(x: w, y: (h + strip) / 2))

                    // Bottom-right corner
                    p.move(to: CGPoint(x: w, y: h - cornerLength))
                    p.addLine(to: CGPoint(x: w, y: h - r))
                    p.addArc(tangent1End: CGPoint(x: w, y: h),
                             tangent2End: CGPoint(x: w - r, y: h),
                             radius: r)
                    p.addLine(to: CGPoint(x: w - cornerLength, y: h))

                    // Bottom-left corner
                    p.move(to: CGPoint(x: cornerLength, y: h))
                    p.addLine(to: CGPoint(x: r, y: h))
                    p.addArc(tangent1End: CGPoint(x: 0, y: h),
                             tangent2End: CGPoint(x: 0, y: h - r),
                             radius: r)
                    p.addLine(to: CGPoint(x: 0, y: h - cornerLength))

                    // Left-center strip
                    p.move(to: CGPoint(x: 0, y: (h - strip) / 2))
                    p.addLine(to: CGPoint(x: 0, y: (h + strip) / 2))
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                // Animated scanning beam — classic Bool-toggle pattern
                // (widely used in SwiftUI scanner examples).
                // Offset animates between 0 and (h - beamHeight), so beam
                // strictly stays inside [0, h] regardless of h.
                Rectangle()
                    .fill(beamGradient)
                    .frame(width: w - 4, height: beamHeight)
                    .offset(x: 2, y: beamAtBottom ? max(h - beamHeight, 0) : 0)
                    .animation(
                        .linear(duration: animationDuration).repeatForever(autoreverses: true),
                        value: beamAtBottom
                    )
            }
            .frame(width: w, height: h, alignment: .top)
            .clipped()
            .onAppear {
                beamAtBottom = true
            }
        }
    }
}

#Preview {
    ScanView()
        .environment(OwnServersViewModel())
}
