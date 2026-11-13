import SwiftUI
import AVFoundation
import UIKit

/// Command wrapper — держит ссылку на активный контроллер и триггерит capture по тапу из SwiftUI.
@MainActor
final class ScanCameraCommand {
    fileprivate weak var controller: ScanCameraController?

    func capturePhoto() {
        controller?.capturePhoto()
    }
}

/// SwiftUI-обёртка над AVCaptureSession с AVCapturePhotoOutput (tap-to-capture).
struct ScanCameraView: UIViewControllerRepresentable {
    @Binding var torchOn: Bool
    let command: ScanCameraCommand
    let onCaptured: (UIImage?) -> Void
    let onPermissionDenied: () -> Void

    func makeUIViewController(context: Context) -> ScanCameraController {
        let vc = ScanCameraController()
        vc.onCaptured = onCaptured
        vc.onPermissionDenied = onPermissionDenied
        command.controller = vc
        return vc
    }

    func updateUIViewController(_ vc: ScanCameraController, context: Context) {
        vc.setTorch(on: torchOn)
    }
}

// MARK: - Underlying UIViewController
final class ScanCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCaptured: ((UIImage?) -> Void)?
    var onPermissionDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var device: AVCaptureDevice?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccessAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }

    // MARK: - Setup
    private func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.configure() : self?.onPermissionDenied?()
                }
            }
        default:
            onPermissionDenied?()
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        self.device = device

        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        self.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    private func stop() {
        setTorch(on: false)
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }

    // MARK: - Capture
    func capturePhoto() {
        guard session.isRunning else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let image: UIImage? = {
            guard error == nil,
                  let data = photo.fileDataRepresentation()
            else { return nil }
            return UIImage(data: data)
        }()
        DispatchQueue.main.async { [weak self] in
            self?.onCaptured?(image)
        }
    }

    // MARK: - Torch
    func setTorch(on: Bool) {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }
}
