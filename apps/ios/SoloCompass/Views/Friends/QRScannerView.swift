import AVFoundation
import SwiftUI

/// US-014: a thin SwiftUI wrapper over an `AVCaptureSession` QR reader.
///
/// Streams the *first* decoded `qr` payload back via `onCode`, then stops the
/// session (one-shot — the parent dismisses the scanner on a hit). Camera
/// permission is requested lazily; a denial routes to `onError` so the caller
/// can fall back to manual entry (NSCameraUsageDescription is declared in
/// Info.plist). No frames leave the device.
struct QRScannerView: UIViewControllerRepresentable {
    /// Called once with the raw decoded string on the first QR detection.
    var onCode: (String) -> Void
    /// Called when the camera is unavailable or permission was denied.
    var onError: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onError: onError)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onCode: (String) -> Void
        private let onError: () -> Void
        private var didFire = false

        init(onCode: @escaping (String) -> Void, onError: @escaping () -> Void) {
            self.onCode = onCode
            self.onError = onError
        }

        func reportError() {
            guard !didFire else { return }
            didFire = true
            onError()
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didFire,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue
            else { return }
            didFire = true
            onCode(value)
        }
    }
}

// MARK: - Capture controller

/// Owns the `AVCaptureSession`. Starts/stops on appear/disappear and routes
/// permission/setup failures through the coordinator so SwiftUI can recover.
final class ScannerViewController: UIViewController {
    weak var coordinator: QRScannerView.Coordinator?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccessThenConfigure()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            Task.detached { [session] in session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - Setup

    private func requestAccessThenConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.configureSession()
                        self.startIfPossible()
                    } else {
                        self.coordinator?.reportError()
                    }
                }
            }
        default:
            coordinator?.reportError()
        }
    }

    private func configureSession() {
        guard previewLayer == nil else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            coordinator?.reportError()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            coordinator?.reportError()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(coordinator, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func startIfPossible() {
        guard previewLayer != nil, !session.isRunning else { return }
        Task.detached { [session] in session.startRunning() }
    }
}
