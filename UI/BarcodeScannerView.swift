//
//  BarcodeScannerView.swift
//  HealthBar
//
//  Created by Claude on 1/23/26.
//

import SwiftUI
import AVFoundation

/// Camera-based barcode scanner view using AVFoundation
///
/// Features:
/// - Real-time barcode detection (UPC-A, UPC-E, EAN-13)
/// - Scanning frame overlay for visual guidance
/// - Haptic feedback on successful scan
/// - Auto-dismiss after detection
/// - Clean design matching DesignSystem aesthetic
struct BarcodeScannerView: View {

    // MARK: - Properties

    /// Callback when barcode is detected
    let onBarcodeDetected: (String) -> Void

    /// Dismiss action
    @Environment(\.dismiss) private var dismiss

    /// Scanner coordinator state
    @State private var coordinator = ScannerCoordinator()

    // MARK: - Body

    var body: some View {
        ZStack {
            // Camera preview (full screen)
            CameraPreviewView(coordinator: coordinator)
                .ignoresSafeArea()

            // Dark overlay with cutout for scanning area
            scannerOverlay

            // Top bar with cancel button
            VStack {
                topBar
                Spacer()
            }

            // Bottom status text
            VStack {
                Spacer()
                statusText
                    .padding(.bottom, DesignSystem.Spacing.xl)
            }
        }
        .onAppear {
            coordinator.startScanning { barcode in
                handleBarcodeDetected(barcode)
            }
        }
        .onDisappear {
            coordinator.stopScanning()
        }
    }

    // MARK: - Subviews

    /// Top bar with cancel button
    private var topBar: some View {
        HStack {
            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 40, height: 40)
                    )
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    /// Scanning frame overlay with instructions
    private var scannerOverlay: some View {
        ZStack {
            // Dark overlay
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            // Scanning frame cutout
            VStack(spacing: DesignSystem.Spacing.xl) {
                Spacer()

                // Scanning frame
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .stroke(DesignSystem.Colors.primary, lineWidth: 3)
                    .frame(width: 280, height: 180)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .fill(Color.clear)
                    )
                    .overlay(
                        // Animated scanning line
                        scanningLine
                    )

                Spacer()
            }
        }
        .allowsHitTesting(false) // Allow camera to receive touches
    }

    /// Animated scanning line
    private var scanningLine: some View {
        VStack {
            Rectangle()
                .fill(DesignSystem.Colors.primary.opacity(0.5))
                .frame(height: 2)
                .padding(.horizontal, 4)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(
            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
            value: coordinator.isScanning
        )
    }

    /// Status text at bottom
    private var statusText: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Text("Position barcode within frame")
                .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)

            Text("Scanning for UPC and EAN codes")
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .regular))
                .foregroundColor(.white.opacity(0.8))
                .shadow(color: .black.opacity(0.5), radius: 4)
        }
    }

    // MARK: - Actions

    /// Handles barcode detection
    private func handleBarcodeDetected(_ barcode: String) {
        // Provide haptic feedback
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif

        // Call completion handler
        onBarcodeDetected(barcode)

        // Dismiss after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }
}

// MARK: - Scanner Coordinator

/// Coordinator for managing AVFoundation barcode scanning
@Observable
class ScannerCoordinator: NSObject {

    // MARK: - Properties

    /// Capture session for camera
    var captureSession: AVCaptureSession?

    /// Is currently scanning
    var isScanning = false

    /// Callback for barcode detection
    private var onBarcodeDetected: ((String) -> Void)?

    // MARK: - Public Methods

    /// Starts the barcode scanning session
    /// - Parameter completion: Callback when barcode is detected
    func startScanning(onBarcodeDetected: @escaping (String) -> Void) {
        self.onBarcodeDetected = onBarcodeDetected

        // Check camera authorization
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCaptureSession()
                    }
                }
            }
        default:
            // Permission denied - handle in UI
            break
        }
    }

    /// Stops the scanning session
    func stopScanning() {
        captureSession?.stopRunning()
        isScanning = false
    }

    // MARK: - Private Methods

    /// Sets up the AVCaptureSession for barcode scanning
    private func setupCaptureSession() {
        let session = AVCaptureSession()

        // Get camera device
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            return
        }

        // Create input
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        // Add input to session
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            return
        }

        // Create metadata output
        let metadataOutput = AVCaptureMetadataOutput()

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)

            // Set barcode types to detect (UPC-A, UPC-E, EAN-13)
            metadataOutput.metadataObjectTypes = [
                .upce,
                .ean8,
                .ean13,
                .code128
            ]
        } else {
            return
        }

        // Save session and start
        self.captureSession = session

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.startRunning()
            DispatchQueue.main.async {
                self?.isScanning = true
            }
        }
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension ScannerCoordinator: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        // Stop scanning once we detect a barcode
        captureSession?.stopRunning()
        isScanning = false

        // Extract barcode string
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let barcodeString = metadataObject.stringValue {
            onBarcodeDetected?(barcodeString)
        }
    }
}

// MARK: - Camera Preview View

/// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {

    let coordinator: ScannerCoordinator

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Remove existing preview layers
        uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        // Add preview layer if session exists
        if let captureSession = coordinator.captureSession {
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = uiView.bounds
            previewLayer.videoGravity = .resizeAspectFill
            uiView.layer.addSublayer(previewLayer)
        }
    }
}

// MARK: - Preview

#Preview("Barcode Scanner") {
    BarcodeScannerView { barcode in
        print("Detected barcode: \(barcode)")
    }
}
