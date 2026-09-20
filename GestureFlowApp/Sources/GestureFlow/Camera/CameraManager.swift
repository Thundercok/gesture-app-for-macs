import AVFoundation
import CoreVideo
import VideoToolbox
import AppKit

final class CameraManager: NSObject, @unchecked Sendable {
    private let captureSession = AVCaptureSession()
    var session: AVCaptureSession { captureSession }
    private let processingQueue = DispatchQueue(label: "com.gestureflow.camera", qos: .userInteractive)
    private var videoOutput: AVCaptureVideoDataOutput?
    private var isProcessing = false
    var isThrottled: Bool = false
    private var throttleCounter: Int = 0

    private(set) var deviceName: String = "Default Camera"
    private(set) var bufferWidth: Int = 1280
    private(set) var bufferHeight: Int = 720

    var onFrame: ((_ pixelBuffer: CVPixelBuffer, _ image: NSImage?, _ aspectRatio: CGFloat, _ pts: CMTime) -> Void)?

    func start() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                self.configureSession()
                self.captureSession.startRunning()
            }
        }
    }

    func stop() {
        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    private func configureSession() {
        guard captureSession.inputs.isEmpty else { return }
        if captureSession.canSetSessionPreset(.hd1280x720) {
            captureSession.sessionPreset = .hd1280x720 // High spatial resolution for 4x landmark pixel density
        } else {
            captureSession.sessionPreset = .vga640x480
        }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("[CameraManager] Error: No video device found")
            return
        }
        self.deviceName = device.localizedName

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(self, queue: processingQueue)

        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }
        videoOutput = output

        // Lock hardware frame rate to 60 FPS
        do {
            try device.lockForConfiguration()
            var matched60Format = false
            for format in device.formats {
                for range in format.videoSupportedFrameRateRanges {
                    if range.maxFrameRate >= 59.9 {
                        device.activeFormat = format
                        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
                        matched60Format = true
                        break
                    }
                }
                if matched60Format { break }
            }
            device.unlockForConfiguration()
        } catch {
            print("[CameraManager] Could not lock device for 60fps: \(error)")
        }

        // Request 60 FPS on output connection
        if let conn = output.connection(with: .video) {
            if conn.isVideoMinFrameDurationSupported {
                conn.videoMinFrameDuration = CMTime(value: 1, timescale: 60)
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessing else { return }

        // Adaptive power throttling: when idle, process 1 out of every 4 frames (15 FPS instead of 60 FPS)
        if isThrottled {
            throttleCounter += 1
            if throttleCounter % 4 != 0 {
                return
            }
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        self.bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        self.bufferHeight = CVPixelBufferGetHeight(pixelBuffer)

        isProcessing = true

        // Blazing fast hardware-accelerated CGImage creation via VideoToolbox
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)

        let aspectRatio: CGFloat = {
            if let cg = cgImage, cg.height > 0 {
                return CGFloat(cg.width) / CGFloat(cg.height)
            }
            return 16.0 / 9.0
        }()

        let nsImage: NSImage? = {
            guard let cg = cgImage else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }()

        onFrame?(pixelBuffer, nsImage, aspectRatio, pts)
        isProcessing = false
    }
}
